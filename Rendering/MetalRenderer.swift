// DualDS — Metal view that shows both DS screens and turns touches into DS touch input.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.
//
// Frame path: the emulation thread publishes each frame inside DSSession; on every display refresh
// this view asks the core to copy the latest frame straight into a shared MTLBuffer (the only CPU
// copy, no per-frame allocation), then a GPU blit moves it into two private textures that are drawn.
// Three buffers rotate so the CPU never writes a buffer the GPU is still reading. (Buffer-backed or
// shared-storage textures would save the blit but are not supported by the iOS Simulator's Metal.)

import MetalKit
import UIKit

enum ScreenFilter: String, CaseIterable, Identifiable, Sendable {
    case nearest = "Sharp (Nearest)", linear = "Smooth (Linear)"
    var id: String { rawValue }
}

final class DSMetalView: MTKView {
    var core: DSCore?
    var layout = DSScreenLayout() { didSet { if layout != oldValue { setNeedsLayout() } } }
    /// When set (iPhone Duo clamshell layout), these frames are used instead of `layout`.
    var explicitFrames: DSScreenLayout.Frames? { didSet { if explicitFrames != oldValue { setNeedsLayout() } } }
    var filter: ScreenFilter = .nearest
    /// Called with DS touch coordinates; `touching == false` on release.
    var onTouch: ((Int, Int, Bool) -> Void)?

    private(set) var frames = DSScreenLayout.Frames(top: .zero, bottom: .zero)
    private let renderer: Renderer?
    private var activeTouch: UITouch?
    private let topElement: UIAccessibilityElement
    private let bottomElement: UIAccessibilityElement

    init() {
        let device = MTLCreateSystemDefaultDevice()
        renderer = device.flatMap(Renderer.init(device:))
        topElement = UIAccessibilityElement(accessibilityContainer: NSObject())
        bottomElement = UIAccessibilityElement(accessibilityContainer: NSObject())
        super.init(frame: .zero, device: device)
        colorPixelFormat = .bgra8Unorm
        framebufferOnly = true
        // Transparent outside the two screens, so the shell, bezels and hinge band behind show through.
        clearColor = MTLClearColorMake(0, 0, 0, 0)
        isOpaque = false
        layer.isOpaque = false
        preferredFramesPerSecond = 60
        isMultipleTouchEnabled = false
        backgroundColor = .clear

        for (element, id, label) in [(topElement, "emulator.topScreen", "Top screen"),
                                     (bottomElement, "emulator.bottomScreen", "Touch screen")] {
            element.accessibilityContainer = self
            element.accessibilityIdentifier = id
            element.accessibilityLabel = label
            element.accessibilityTraits = .image
        }
        isAccessibilityElement = false
        accessibilityElements = [topElement, bottomElement]
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        frames = explicitFrames ?? layout.frames(in: bounds, scale: contentScaleFactor)
        topElement.accessibilityFrameInContainerSpace = frames.top
        bottomElement.accessibilityFrameInContainerSpace = frames.bottom
    }

    override func draw(_ rect: CGRect) {
        guard let renderer, let core else { return }
        renderer.draw(in: self, core: core, frames: frames, filter: filter)
    }

    // MARK: Touch screen

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch == nil,
              let touch = touches.first(where: { frames.bottom.contains($0.location(in: self)) }) else { return }
        activeTouch = touch
        send(touch, touching: true)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = activeTouch, touches.contains(touch) { send(touch, touching: true) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { release(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { release(touches) }

    private func send(_ touch: UITouch, touching: Bool) {
        // Dragging off the edge keeps the stylus on the nearest edge, as on hardware.
        let p = touch.location(in: self)
        let b = frames.bottom
        let clamped = CGPoint(x: min(max(p.x, b.minX), b.maxX - 0.01), y: min(max(p.y, b.minY), b.maxY - 0.01))
        guard let ds = DSScreenLayout.touchCoordinates(of: clamped, in: b) else { return }
        onTouch?(ds.x, ds.y, touching)
    }

    private func release(_ touches: Set<UITouch>) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        activeTouch = nil
        onTouch?(0, 0, false)
    }
}

@MainActor
private final class Renderer {
    private static let pixels = DSCore.screenWidth * DSCore.screenHeight
    private static let ringSize = 3

    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let samplers: [ScreenFilter: MTLSamplerState]
    private let buffers: [MTLBuffer]
    private let top: MTLTexture
    private let bottom: MTLTexture
    private let inFlight = DispatchSemaphore(value: ringSize)
    private var index = 0

    init?(device: MTLDevice) {
        guard let queue = device.makeCommandQueue(),
              let library = try? ShaderLibrary.make(device: device),
              let vertex = library.makeFunction(name: "ds_screen_vertex"),
              let fragment = library.makeFunction(name: "ds_screen_fragment") else { return nil }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertex
        desc.fragmentFunction = fragment
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: desc) else { return nil }

        var samplers: [ScreenFilter: MTLSamplerState] = [:]
        for f in ScreenFilter.allCases {
            let s = MTLSamplerDescriptor()
            s.minFilter = f == .nearest ? .nearest : .linear
            s.magFilter = s.minFilter
            s.sAddressMode = .clampToEdge
            s.tAddressMode = .clampToEdge
            guard let state = device.makeSamplerState(descriptor: s) else { return nil }
            samplers[f] = state
        }

        let screenBytes = Self.pixels * 4
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: DSCore.screenWidth,
                                                          height: DSCore.screenHeight, mipmapped: false)
        td.usage = .shaderRead
        td.storageMode = .private
        guard let top = device.makeTexture(descriptor: td), let bottom = device.makeTexture(descriptor: td) else { return nil }
        var buffers: [MTLBuffer] = []
        for _ in 0..<Self.ringSize {
            guard let buffer = device.makeBuffer(length: screenBytes * 2, options: .storageModeShared) else { return nil }
            buffers.append(buffer)
        }
        self.queue = queue
        self.pipeline = pipeline
        self.samplers = samplers
        self.buffers = buffers
        self.top = top
        self.bottom = bottom
    }

    /// Built outside the main actor: Metal calls the handler on its own thread, and a closure created
    /// in main-actor code would inherit main-actor isolation and trap there.
    nonisolated private static func signalWhenCompleted(_ commands: MTLCommandBuffer, _ semaphore: DispatchSemaphore) {
        commands.addCompletedHandler { _ in semaphore.signal() }
    }

    func draw(in view: MTKView, core: DSCore, frames: DSScreenLayout.Frames, filter: ScreenFilter) {
        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable else { return }
        inFlight.wait()
        index = (index + 1) % Self.ringSize
        let base = buffers[index].contents().bindMemory(to: UInt32.self, capacity: Self.pixels * 2)
        let hasFrame = core.copyFramebuffer(top: base, bottom: base + Self.pixels, frameNumber: nil)

        guard let commands = queue.makeCommandBuffer() else { inFlight.signal(); return }
        if hasFrame, let blit = commands.makeBlitCommandEncoder() {
            let rowBytes = DSCore.screenWidth * 4
            let size = MTLSize(width: DSCore.screenWidth, height: DSCore.screenHeight, depth: 1)
            for (texture, offset) in [(top, 0), (bottom, Self.pixels * 4)] {
                blit.copy(from: buffers[index], sourceOffset: offset, sourceBytesPerRow: rowBytes,
                          sourceBytesPerImage: rowBytes * DSCore.screenHeight, sourceSize: size,
                          to: texture, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin())
            }
            blit.endEncoding()
        }
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else {
            commands.commit(); inFlight.signal(); return
        }
        if hasFrame {
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentSamplerState(samplers[filter], index: 0)
            let scale = view.contentScaleFactor
            for (rect, texture) in [(frames.top, top), (frames.bottom, bottom)]
            where rect.width > 0 && rect.height > 0 {
                encoder.setViewport(MTLViewport(originX: rect.minX * scale, originY: rect.minY * scale,
                                                width: rect.width * scale, height: rect.height * scale,
                                                znear: 0, zfar: 1))
                encoder.setFragmentTexture(texture, index: 0)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            }
        }
        encoder.endEncoding()
        Self.signalWhenCompleted(commands, inFlight)
        commands.present(drawable)
        commands.commit()
    }
}
