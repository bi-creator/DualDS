// DualDS — portable C++ session layer on top of the melonDS core.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.
//
// This header deliberately exposes no melonDS types. Everything Apple-specific
// (Metal, AVAudioEngine, Objective-C) lives in EmulatorBridge/, on top of this.
//
// Threading model
//  * One DSSession owns one emulated console and (after start()) one emulation thread.
//  * Input setters, frame/audio readers and stats are safe to call from any thread.
//  * Lifecycle and state operations (loadROM, reset, saveState, loadState, flushSave, stop)
//    are safe to call from any thread except the emulation thread; they serialise
//    with the running emulator through an internal mutex held for one frame at most.
#pragma once

#include <cstddef>
#include <cstdint>
#include <functional>
#include <memory>
#include <string>

namespace dualds {

constexpr int kScreenWidth = 256;
constexpr int kScreenHeight = 192;
constexpr int kScreenPixels = kScreenWidth * kScreenHeight;
/// Native DS refresh rate (33.513982 MHz / (2130 * 263)).
constexpr double kNativeFrameRate = 59.8260982881;

/// Bit positions match the DS KEYINPUT/EXTKEYIN layout that melonDS's NDS::SetKeyMask expects.
enum class Button : uint32_t {
    A = 0, B = 1, Select = 2, Start = 3,
    Right = 4, Left = 5, Up = 6, Down = 7,
    R = 8, L = 9, X = 10, Y = 11,
};

enum class SessionError {
    None = 0,
    FileNotFound,
    ReadFailed,
    InvalidROM,
    NoROMLoaded,
    AlreadyRunning,
    StateIOFailed,
    StateIncompatible,
    SaveIOFailed,
};

const char* describe(SessionError e);

enum class RunState { Idle, Running, Paused, Stopped };

struct SessionConfig {
    /// Output sample rate requested from the melonDS SPU (stereo, s16 interleaved).
    double audioSampleRate = 48000.0;
    /// Run the software 3D rasteriser on its own thread (melonDS option).
    bool threaded3D = true;
};

struct Callbacks {
    /// Called on the emulation thread after each completed frame (keep it cheap).
    std::function<void(uint64_t frameNumber)> onFrame;
    /// Called when the core stops itself (power-off, unsupported GBA mode, crash region).
    std::function<void(const std::string& reason)> onStopped;
    /// melonDS log lines. Called from whichever thread logged.
    std::function<void(int level, const std::string& message)> onLog;
};

struct SessionStats {
    uint64_t framesEmulated = 0;
    double measuredFPS = 0.0;       // rolling, over the last ~1 s of wall time
    uint64_t audioUnderruns = 0;    // reads that found fewer frames than requested
    uint64_t audioOverflows = 0;    // sample frames dropped because the ring was full
};

class DSSession {
public:
    explicit DSSession(SessionConfig config = {}, Callbacks callbacks = {});
    ~DSSession();
    DSSession(const DSSession&) = delete;
    DSSession& operator=(const DSSession&) = delete;

    // ---- Lifecycle -------------------------------------------------------
    /// Loads a .nds file and its battery save (savePath may not exist yet; it is created on first write).
    /// Builds a fresh console using melonDS's FreeBIOS + generated firmware and direct-boots the ROM.
    SessionError loadROM(const std::string& romPath, const std::string& savePath, std::string* detail = nullptr);
    /// Starts the paced emulation thread.
    SessionError start();
    void pause();
    void resume();
    /// Stops the thread, flushes the battery save and releases the console.
    void stop();
    SessionError reset();
    RunState runState() const;

    /// Runs `count` frames synchronously on the calling thread. Only valid while not started
    /// (used by tests and benchmarks). Returns frames actually run.
    uint64_t runFramesBlocking(uint64_t count);

    // ---- Input (any thread) -------------------------------------------------
    void setButton(Button button, bool pressed);
    void setButtonMask(uint32_t pressedMask);       // bit i set == Button(i) held
    /// Mask the next frame will see: held buttons plus any pressed-and-released since the last
    /// frame (every press lasts at least one frame).
    uint32_t buttonsForNextFrame() const;
    /// x in [0,255], y in [0,191] bottom-screen pixels. Values outside are clamped.
    void setTouch(int x, int y, bool touching);
    void setFastForward(bool enabled);
    /// Lid state. Closing the lid puts many games to sleep.
    void setLidClosed(bool closed);

    // ---- Video (any thread) ---------------------------------------------------
    /// Copies the latest completed frame. Pixels are 32-bit little-endian BGRA (melonDS soft renderer).
    /// Returns false if no frame has been produced yet. `frameNumber` (optional) receives its sequence number.
    bool copyLatestFrame(uint32_t* top, uint32_t* bottom, uint64_t* frameNumber = nullptr) const;
    uint64_t latestFrameNumber() const;

    // ---- Audio (any thread; single consumer) -----------------------------------
    /// Reads up to `frames` stereo sample frames (2 * frames int16 values). Returns frames read.
    size_t readAudio(int16_t* interleaved, size_t frames);
    size_t audioFramesAvailable() const;
    double audioSampleRate() const;

    // ---- Saves ----------------------------------------------------------------
    /// Writes pending battery-save data to disk atomically (tmp file + rename).
    SessionError flushSave();
    bool hasPendingSave() const;
    /// Serialises the full console state (melonDS savestate format) to `path`, atomically.
    SessionError saveState(const std::string& path, std::string* detail = nullptr);
    /// Restores a state; on failure the previous state is restored and an error is returned.
    /// The screens update on the next emulated frame (savestates do not store rendered output).
    SessionError loadState(const std::string& path, std::string* detail = nullptr);

    SessionStats stats() const;

    // ---- Called from the melonDS Platform layer (not part of the public API) -----
    struct Impl;
private:
    std::unique_ptr<Impl> impl_;
};

/// melonDS version string this layer was built against.
const char* melonDSVersion();

} // namespace dualds
