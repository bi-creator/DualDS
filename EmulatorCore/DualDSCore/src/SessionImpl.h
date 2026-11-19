// DualDS — internal session state shared by DSSession.cpp and DSPlatform.cpp.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.
#pragma once

#include "DualDSCore/DSSession.h"

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <mutex>
#include <thread>
#include <vector>

#include "NDS.h"

namespace dualds {

/// Lock-free single-producer / single-consumer ring of interleaved stereo s16 frames.
class AudioRing {
public:
    explicit AudioRing(size_t capacityFrames) : cap_(capacityFrames + 1), buf_(cap_ * 2) {}

    size_t push(const int16_t* src, size_t frames)
    {
        size_t w = write_.load(std::memory_order_relaxed);
        const size_t r = read_.load(std::memory_order_acquire);
        size_t freeFrames = (r + cap_ - w - 1) % cap_;
        size_t n = frames < freeFrames ? frames : freeFrames;
        for (size_t i = 0; i < n; ++i)
        {
            buf_[w * 2] = src[i * 2];
            buf_[w * 2 + 1] = src[i * 2 + 1];
            w = (w + 1) % cap_;
        }
        write_.store(w, std::memory_order_release);
        return n;
    }

    size_t pop(int16_t* dst, size_t frames)
    {
        size_t r = read_.load(std::memory_order_relaxed);
        const size_t w = write_.load(std::memory_order_acquire);
        size_t avail = (w + cap_ - r) % cap_;
        size_t n = frames < avail ? frames : avail;
        for (size_t i = 0; i < n; ++i)
        {
            dst[i * 2] = buf_[r * 2];
            dst[i * 2 + 1] = buf_[r * 2 + 1];
            r = (r + 1) % cap_;
        }
        read_.store(r, std::memory_order_release);
        return n;
    }

    size_t size() const
    {
        return (write_.load(std::memory_order_acquire) + cap_ - read_.load(std::memory_order_acquire)) % cap_;
    }

    /// Only call while neither side is active.
    void clear() { read_.store(0); write_.store(0); }

private:
    const size_t cap_;
    std::vector<int16_t> buf_;
    std::atomic<size_t> read_{0}, write_{0};
};

bool readWholeFile(const std::string& path, std::vector<uint8_t>& out, SessionError& err);
bool writeFileAtomically(const std::string& path, const void* data, size_t len);

struct DSSession::Impl {
    Impl(SessionConfig c, Callbacks cb);

    static constexpr uint32_t kTouchActiveBit = 1u << 16;

    SessionConfig config;
    Callbacks callbacks;

    // Console (guarded by coreMutex)
    std::mutex coreMutex;
    std::unique_ptr<melonDS::NDS> nds;
    std::string romPath;
    bool appliedLid = false;

    // Thread control
    std::thread thread;
    std::atomic<bool> stopRequested{false};
    std::atomic<bool> coreStopped{false};
    std::atomic<RunState> state{RunState::Idle};
    std::mutex pauseMutex;
    std::condition_variable pauseCV;
    bool paused = false;
    std::mutex stopReasonMutex;
    std::string stopReason;

    // Input (lock-free)
    std::atomic<uint32_t> buttons{0};
    std::atomic<uint32_t> touch{0};
    std::atomic<bool> fastForward{false};
    std::atomic<bool> lidClosed{false};

    // Video
    mutable std::mutex frameMutex;
    std::vector<uint32_t> frameTop, frameBottom;
    uint64_t frameNumber = 0;
    bool hasFrame = false;

    // Audio
    AudioRing audio;
    std::vector<int16_t> audioScratch;

    // Battery save
    mutable std::mutex saveMutex;
    std::string savePath;
    std::vector<uint8_t> pendingSave;
    bool saveDirty = false;
    std::chrono::steady_clock::time_point lastSaveWrite;

    // Stats
    std::atomic<uint64_t> framesEmulated{0};
    std::atomic<double> measuredFPS{0.0};
    std::atomic<uint64_t> audioUnderruns{0};
    std::atomic<uint64_t> audioOverflows{0};

    void applyInput();
    void publishFrameAndAudio();
    void runOneFrameLocked();
    void threadMain();
    void onSaveWritten(const uint8_t* data, uint32_t len);
    SessionError flushSaveIfDirty(bool force);
    void log(int level, const std::string& msg);
};

// melonDS's Platform::Log has no userdata, so logs go to the most recently created session.
void registerLogSink(DSSession::Impl* impl);
void unregisterLogSink(DSSession::Impl* impl);

} // namespace dualds
