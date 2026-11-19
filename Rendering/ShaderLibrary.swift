// DualDS — Metal shaders for drawing the DS screens.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.
//
// Compiled at runtime with MTLDevice.makeLibrary(source:) so building DualDS needs no separate
// Metal toolchain download (Xcode 26+ ships it as an optional component). Compilation takes a
// few milliseconds, once per emulator session.

import Metal

enum ShaderLibrary {
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexOut {
        float4 position [[position]];
        float2 uv;
    };

    constant float2 kPositions[4] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };
    constant float2 kUVs[4]       = { float2(0, 1),   float2(1, 1),  float2(0, 0),  float2(1, 0) };

    vertex VertexOut ds_screen_vertex(uint vid [[vertex_id]]) {
        VertexOut out;
        out.position = float4(kPositions[vid], 0.0, 1.0);
        out.uv = kUVs[vid];
        return out;
    }

    // melonDS's alpha byte is not meaningful for display; the DS screen is always opaque.
    fragment float4 ds_screen_fragment(VertexOut in [[stage_in]],
                                       texture2d<float> screen [[texture(0)]],
                                       sampler smp [[sampler(0)]]) {
        return float4(screen.sample(smp, in.uv).rgb, 1.0);
    }
    """

    static func make(device: MTLDevice) throws -> MTLLibrary {
        try device.makeLibrary(source: source, options: nil)
    }
}
