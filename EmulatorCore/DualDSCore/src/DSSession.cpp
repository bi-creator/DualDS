// DualDS — portable C++ session layer on top of the melonDS core.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.

#include "DualDSCore/DSSession.h"
#include "SessionImpl.h"

#include <algorithm>
#include <cerrno>
#include <cstdio>
#include <cstring>
#include <ctime>

#include "GPU_Soft.h"
#include "NDSCart.h"
#include "Savestate.h"
#include "version.h"

namespace dualds {

using namespace std::chrono;

const char* describe(SessionError e)
{
    switch (e)
    {
    case SessionError::None: return "No error";
    case SessionError::FileNotFound: return "The file could not be found";
    case SessionError::ReadFailed: return "The file could not be read";
    case SessionError::InvalidROM: return "The file is not a valid Nintendo DS ROM";
    case SessionError::NoROMLoaded: return "No game is loaded";
    case SessionError::AlreadyRunning: return "The emulator is already running";
    case SessionError::StateIOFailed: return "The save state could not be read or written";
    case SessionError::StateIncompatible: return "The save state is not compatible with this game or emulator version";
    case SessionError::SaveIOFailed: return "The game save could not be written";
    }
    return "Unknown error";
}

const char* melonDSVersion() { return MELONDS_VERSION; }

// ---------------------------------------------------------------------------
// File helpers

bool readWholeFile(const std::string& path, std::vector<uint8_t>& out, SessionError& err)
{
    FILE* f = std::fopen(path.c_str(), "rb");
    if (!f) { err = (errno == ENOENT) ? SessionError::FileNotFound : SessionError::ReadFailed; return false; }
    if (std::fseek(f, 0, SEEK_END) != 0) { std::fclose(f); err = SessionError::ReadFailed; return false; }
    long len = std::ftell(f);
    if (len < 0) { std::fclose(f); err = SessionError::ReadFailed; return false; }
    std::rewind(f);
    out.resize(static_cast<size_t>(len));
    size_t got = len > 0 ? std::fread(out.data(), 1, out.size(), f) : 0;
    std::fclose(f);
    if (got != out.size()) { err = SessionError::ReadFailed; return false; }
    err = SessionError::None;
    return true;
}

bool writeFileAtomically(const std::string& path, const void* data, size_t len)
{
    const std::string tmp = path + ".tmp";
    FILE* f = std::fopen(tmp.c_str(), "wb");
    if (!f) return false;
    bool ok = (len == 0) || (std::fwrite(data, 1, len, f) == len);
    ok = (std::fflush(f) == 0) && ok;
    ok = (std::fclose(f) == 0) && ok;
    if (!ok) { std::remove(tmp.c_str()); return false; }
    // rename() replaces the destination atomically on POSIX file systems, so a crash
    // mid-write leaves either the old save or the new one — never a truncated file.
    if (std::rename(tmp.c_str(), path.c_str()) != 0) { std::remove(tmp.c_str()); return false; }
    return true;
}

// ---------------------------------------------------------------------------
// Impl

DSSession::Impl::Impl(SessionConfig c, Callbacks cb)
    : config(c), callbacks(std::move(cb)),
      audio(static_cast<size_t>(c.audioSampleRate / 4)) // 250 ms of headroom
{
    frameTop.resize(kScreenPixels);
    frameBottom.resize(kScreenPixels);
    audioScratch.resize(4096 * 2);
}

void DSSession::Impl::applyInput()
{
    // melonDS expects active-low bits: 0 = pressed.
    const uint32_t pressed = (buttons.load(std::memory_order_relaxed) | latched.exchange(0, std::memory_order_relaxed)) & 0xFFF;
    nds->SetKeyMask(~pressed & 0xFFF);

    const uint32_t t = touch.load(std::memory_order_relaxed);
    if (t & kTouchActiveBit)
        nds->TouchScreen(static_cast<melonDS::u16>(t & 0xFF), static_cast<melonDS::u16>((t >> 8) & 0xFF));
    else
        nds->ReleaseScreen();

    const bool lid = lidClosed.load(std::memory_order_relaxed);
    if (lid != appliedLid) { nds->SetLidClosed(lid); appliedLid = lid; }
}

void DSSession::Impl::publishFrameAndAudio()
{
    void* top = nullptr;
    void* bottom = nullptr;
    if (nds->GPU.GetFramebuffers(&top, &bottom) && top && bottom)
    {
        std::lock_guard<std::mutex> lk(frameMutex);
        std::memcpy(frameTop.data(), top, kScreenPixels * sizeof(uint32_t));
        std::memcpy(frameBottom.data(), bottom, kScreenPixels * sizeof(uint32_t));
        frameNumber = framesEmulated.load(std::memory_order_relaxed);
        hasFrame = true;
    }

    // Always drain the SPU so its internal buffer never saturates.
    const bool ff = fastForward.load(std::memory_order_relaxed);
    int avail = nds->SPU.GetOutputSize();
    while (avail > 0)
    {
        const int chunk = std::min(avail, static_cast<int>(audioScratch.size() / 2));
        const int got = nds->SPU.ReadOutput(audioScratch.data(), chunk);
        if (got <= 0) break;
        if (!ff) // fast-forward output would be pitch-shifted noise; drop it
        {
            size_t pushed = audio.push(audioScratch.data(), static_cast<size_t>(got));
            if (pushed < static_cast<size_t>(got))
                audioOverflows.fetch_add(got - pushed, std::memory_order_relaxed);
        }
        avail -= got;
    }
}

void DSSession::Impl::runOneFrameLocked()
{
    applyInput();
    nds->RunFrame();
    framesEmulated.fetch_add(1, std::memory_order_relaxed);
    publishFrameAndAudio();
}

void DSSession::Impl::onSaveWritten(const uint8_t* data, uint32_t len)
{
    std::lock_guard<std::mutex> lk(saveMutex);
    pendingSave.assign(data, data + len);
    saveDirty = true;
    lastSaveWrite = steady_clock::now();
}

SessionError DSSession::Impl::flushSaveIfDirty(bool force)
{
    std::vector<uint8_t> snapshot;
    std::string path;
    {
        std::lock_guard<std::mutex> lk(saveMutex);
        if (!saveDirty) return SessionError::None;
        // Games write save memory in many small bursts; wait for a quiet second unless forced.
        if (!force && steady_clock::now() - lastSaveWrite < seconds(1)) return SessionError::None;
        snapshot = pendingSave;
        path = savePath;
        saveDirty = false;
    }
    if (path.empty()) return SessionError::None;
    if (!writeFileAtomically(path, snapshot.data(), snapshot.size()))
    {
        std::lock_guard<std::mutex> lk(saveMutex);
        saveDirty = true; // keep it pending so a later flush retries
        log(3, "DualDS: failed to write game save to " + path);
        return SessionError::SaveIOFailed;
    }
    return SessionError::None;
}

void DSSession::Impl::log(int level, const std::string& msg)
{
    if (callbacks.onLog) callbacks.onLog(level, msg);
}

void DSSession::Impl::threadMain()
{
    const auto period = duration_cast<steady_clock::duration>(duration<double>(1.0 / kNativeFrameRate));
    auto next = steady_clock::now();
    auto fpsWindowStart = next;
    uint64_t fpsWindowFrames = 0;

    while (!stopRequested.load())
    {
        {
            std::unique_lock<std::mutex> lk(pauseMutex);
            if (paused)
            {
                state.store(RunState::Paused);
                pauseCV.wait(lk, [&] { return !paused || stopRequested.load(); });
                if (stopRequested.load()) break;
                state.store(RunState::Running);
                next = steady_clock::now();
                fpsWindowStart = next;
                fpsWindowFrames = 0;
            }
        }

        uint64_t frameNo;
        {
            std::lock_guard<std::mutex> lk(coreMutex);
            if (!nds || coreStopped.load()) break;
            runOneFrameLocked();
            frameNo = framesEmulated.load(std::memory_order_relaxed);
        }
        if (coreStopped.load()) break;

        flushSaveIfDirty(false);
        if (callbacks.onFrame) callbacks.onFrame(frameNo);

        // FPS over a rolling ~1 s window.
        ++fpsWindowFrames;
        const auto now = steady_clock::now();
        const auto elapsed = now - fpsWindowStart;
        if (elapsed >= seconds(1))
        {
            measuredFPS.store(fpsWindowFrames / duration<double>(elapsed).count());
            fpsWindowStart = now;
            fpsWindowFrames = 0;
        }

        if (fastForward.load(std::memory_order_relaxed))
        {
            next = now;
            continue;
        }
        next += period;
        if (now > next + milliseconds(100)) next = now; // fell far behind (e.g. app was suspended): don't sprint
        std::this_thread::sleep_until(next);
    }

    state.store(RunState::Stopped);
    flushSaveIfDirty(true);

    std::string reason;
    {
        std::lock_guard<std::mutex> lk(stopReasonMutex);
        reason = stopReason;
    }
    if (coreStopped.load() && callbacks.onStopped) callbacks.onStopped(reason);
}

// ---------------------------------------------------------------------------
// DSSession

DSSession::DSSession(SessionConfig config, Callbacks callbacks)
    : impl_(std::make_unique<Impl>(config, std::move(callbacks)))
{
    registerLogSink(impl_.get());
}

DSSession::~DSSession()
{
    stop();
    unregisterLogSink(impl_.get());
}

SessionError DSSession::loadROM(const std::string& romPath, const std::string& savePath, std::string* detail)
{
    auto& d = *impl_;
    if (d.thread.joinable()) return SessionError::AlreadyRunning;

    std::vector<uint8_t> rom;
    SessionError err;
    if (!readWholeFile(romPath, rom, err))
    {
        if (detail) *detail = romPath;
        return err;
    }
    if (rom.size() < 0x200 || rom.size() > 512u * 1024 * 1024)
    {
        if (detail) *detail = "unexpected file size";
        return SessionError::InvalidROM;
    }

    // Battery save: missing file is normal (first launch). Unreadable existing file is an error,
    // because silently starting with a blank save would overwrite the player's progress.
    std::vector<uint8_t> save;
    if (!readWholeFile(savePath, save, err) && err != SessionError::FileNotFound)
    {
        if (detail) *detail = "could not read existing save file " + savePath;
        return SessionError::ReadFailed;
    }

    melonDS::NDSCart::NDSCartArgs cartArgs;
    if (!save.empty())
    {
        cartArgs.SRAM = std::make_unique<melonDS::u8[]>(save.size());
        std::memcpy(cartArgs.SRAM.get(), save.data(), save.size());
        cartArgs.SRAMLength = static_cast<melonDS::u32>(save.size());
    }

    auto romData = std::make_unique<melonDS::u8[]>(rom.size());
    std::memcpy(romData.get(), rom.data(), rom.size());
    const auto romLen = static_cast<melonDS::u32>(rom.size());
    rom.clear();
    rom.shrink_to_fit();

    auto cart = melonDS::NDSCart::ParseROM(std::move(romData), romLen, impl_.get(), std::move(cartArgs));
    if (!cart)
    {
        if (detail) *detail = "melonDS rejected the ROM header";
        return SessionError::InvalidROM;
    }

    std::lock_guard<std::mutex> lk(d.coreMutex);
    d.nds.reset();

    melonDS::NDSArgs args;   // defaults: FreeBIOS ARM9/ARM7 + generated firmware
    args.JIT = std::nullopt; // iOS App Store builds cannot map executable memory
    args.OutputSampleRate = d.config.audioSampleRate;
    d.nds = std::make_unique<melonDS::NDS>(std::move(args), impl_.get());

    d.nds->SetRenderer(std::make_unique<melonDS::SoftRenderer>(*d.nds));
    melonDS::RendererSettings rs{};
    rs.ScaleFactor = 1;
    rs.Threaded = d.config.threaded3D;
    d.nds->GetRenderer().SetRenderSettings(rs);

    d.nds->SetNDSCart(std::move(cart));
    d.nds->Reset();
    // FreeBIOS cannot boot the DS firmware menu, so melonDS must direct-boot the cartridge.
    const std::string romName = romPath.substr(romPath.find_last_of('/') + 1);
    d.nds->SetupDirectBoot(romName);

    const std::time_t t = std::time(nullptr);
    std::tm local{};
    localtime_r(&t, &local);
    d.nds->RTC.SetDateTime(local.tm_year + 1900, local.tm_mon + 1, local.tm_mday,
                           local.tm_hour, local.tm_min, local.tm_sec);

    d.nds->Start();

    {
        std::lock_guard<std::mutex> slk(d.saveMutex);
        d.savePath = savePath;
        d.saveDirty = false;
        d.pendingSave.clear();
    }
    d.romPath = romPath;
    d.framesEmulated.store(0);
    d.coreStopped.store(false);
    d.appliedLid = false;
    {
        std::lock_guard<std::mutex> flk(d.frameMutex);
        d.hasFrame = false;
        d.frameNumber = 0;
    }
    d.audio.clear();
    d.state.store(RunState::Idle);
    return SessionError::None;
}

SessionError DSSession::start()
{
    auto& d = *impl_;
    if (d.thread.joinable()) return SessionError::AlreadyRunning;
    {
        std::lock_guard<std::mutex> lk(d.coreMutex);
        if (!d.nds) return SessionError::NoROMLoaded;
    }
    d.stopRequested.store(false);
    {
        std::lock_guard<std::mutex> lk(d.pauseMutex);
        d.paused = false;
    }
    d.state.store(RunState::Running);
    d.thread = std::thread([&d] { d.threadMain(); });
    return SessionError::None;
}

void DSSession::pause()
{
    auto& d = *impl_;
    {
        std::lock_guard<std::mutex> lk(d.pauseMutex);
        d.paused = true;
    }
    d.flushSaveIfDirty(true);
}

void DSSession::resume()
{
    auto& d = *impl_;
    {
        std::lock_guard<std::mutex> lk(d.pauseMutex);
        d.paused = false;
    }
    d.pauseCV.notify_all();
}

void DSSession::stop()
{
    auto& d = *impl_;
    d.stopRequested.store(true);
    d.pauseCV.notify_all();
    if (d.thread.joinable()) d.thread.join();
    d.flushSaveIfDirty(true);
    std::lock_guard<std::mutex> lk(d.coreMutex);
    if (d.nds)
    {
        d.nds->Stop(melonDS::Platform::StopReason::External);
        d.nds.reset();
    }
    d.state.store(RunState::Stopped);
}

SessionError DSSession::reset()
{
    auto& d = *impl_;
    d.flushSaveIfDirty(true);
    std::lock_guard<std::mutex> lk(d.coreMutex);
    if (!d.nds) return SessionError::NoROMLoaded;
    d.nds->Reset();
    d.nds->SetupDirectBoot(d.romPath.substr(d.romPath.find_last_of('/') + 1));
    d.nds->Start();
    return SessionError::None;
}

RunState DSSession::runState() const { return impl_->state.load(); }

uint64_t DSSession::runFramesBlocking(uint64_t count)
{
    auto& d = *impl_;
    if (d.thread.joinable()) return 0;
    uint64_t ran = 0;
    for (; ran < count; ++ran)
    {
        std::lock_guard<std::mutex> lk(d.coreMutex);
        if (!d.nds || d.coreStopped.load()) break;
        d.runOneFrameLocked();
    }
    d.flushSaveIfDirty(false);
    return ran;
}

void DSSession::setButton(Button button, bool pressed)
{
    const uint32_t bit = 1u << static_cast<uint32_t>(button);
    if (pressed) { impl_->buttons.fetch_or(bit); impl_->latched.fetch_or(bit); }
    else impl_->buttons.fetch_and(~bit);
}

void DSSession::setButtonMask(uint32_t pressedMask)
{
    const uint32_t newly = pressedMask & ~impl_->buttons.load();
    impl_->buttons.store(pressedMask & 0xFFF);
    impl_->latched.fetch_or(newly & 0xFFF);
}

uint32_t DSSession::buttonsForNextFrame() const
{
    return (impl_->buttons.load() | impl_->latched.load()) & 0xFFF;
}

void DSSession::setTouch(int x, int y, bool touching)
{
    x = std::clamp(x, 0, kScreenWidth - 1);
    y = std::clamp(y, 0, kScreenHeight - 1);
    impl_->touch.store(static_cast<uint32_t>(x) | (static_cast<uint32_t>(y) << 8) |
                       (touching ? Impl::kTouchActiveBit : 0u));
}

void DSSession::setFastForward(bool enabled) { impl_->fastForward.store(enabled); }
void DSSession::setLidClosed(bool closed) { impl_->lidClosed.store(closed); }

bool DSSession::copyLatestFrame(uint32_t* top, uint32_t* bottom, uint64_t* frameNumber) const
{
    auto& d = *impl_;
    std::lock_guard<std::mutex> lk(d.frameMutex);
    if (!d.hasFrame) return false;
    if (top) std::memcpy(top, d.frameTop.data(), kScreenPixels * sizeof(uint32_t));
    if (bottom) std::memcpy(bottom, d.frameBottom.data(), kScreenPixels * sizeof(uint32_t));
    if (frameNumber) *frameNumber = d.frameNumber;
    return true;
}

uint64_t DSSession::latestFrameNumber() const
{
    std::lock_guard<std::mutex> lk(impl_->frameMutex);
    return impl_->frameNumber;
}

size_t DSSession::readAudio(int16_t* interleaved, size_t frames)
{
    const size_t got = impl_->audio.pop(interleaved, frames);
    if (got < frames) impl_->audioUnderruns.fetch_add(1, std::memory_order_relaxed);
    return got;
}

size_t DSSession::audioFramesAvailable() const { return impl_->audio.size(); }
double DSSession::audioSampleRate() const { return impl_->config.audioSampleRate; }

SessionError DSSession::flushSave() { return impl_->flushSaveIfDirty(true); }

bool DSSession::hasPendingSave() const
{
    std::lock_guard<std::mutex> lk(impl_->saveMutex);
    return impl_->saveDirty;
}

SessionError DSSession::saveState(const std::string& path, std::string* detail)
{
    auto& d = *impl_;
    std::unique_ptr<melonDS::Savestate> state;
    {
        std::lock_guard<std::mutex> lk(d.coreMutex);
        if (!d.nds) return SessionError::NoROMLoaded;
        state = std::make_unique<melonDS::Savestate>();
        if (state->Error) { if (detail) *detail = "out of memory"; return SessionError::StateIOFailed; }
        d.nds->DoSavestate(state.get());
        if (state->Error) { if (detail) *detail = "melonDS failed to serialise the state"; return SessionError::StateIOFailed; }
        state->Finish();
    }
    if (!writeFileAtomically(path, state->Buffer(), state->Length()))
    {
        if (detail) *detail = "could not write " + path;
        return SessionError::StateIOFailed;
    }
    return SessionError::None;
}

SessionError DSSession::loadState(const std::string& path, std::string* detail)
{
    auto& d = *impl_;
    std::vector<uint8_t> buf;
    SessionError err;
    if (!readWholeFile(path, buf, err)) { if (detail) *detail = path; return SessionError::StateIOFailed; }

    std::lock_guard<std::mutex> lk(d.coreMutex);
    if (!d.nds) return SessionError::NoROMLoaded;

    // Back up the current state first so a bad file cannot leave the console half-restored.
    auto backup = std::make_unique<melonDS::Savestate>();
    if (backup->Error || !d.nds->DoSavestate(backup.get()) || backup->Error)
    {
        if (detail) *detail = "could not create a safety backup of the current state";
        return SessionError::StateIOFailed;
    }

    melonDS::Savestate incoming(buf.data(), static_cast<melonDS::u32>(buf.size()), false);
    if (incoming.Error)
    {
        if (detail) *detail = "not a melonDS savestate (bad magic or version)";
        return SessionError::StateIncompatible;
    }
    if (!d.nds->DoSavestate(&incoming) || incoming.Error)
    {
        backup->Rewind(false);
        d.nds->DoSavestate(backup.get());
        if (detail) *detail = "state did not match this console configuration; previous state restored";
        return SessionError::StateIncompatible;
    }
    // Note: melonDS savestates do not contain the rendered framebuffers; the restored
    // picture appears after the next RunFrame.
    return SessionError::None;
}

SessionStats DSSession::stats() const
{
    SessionStats s;
    s.framesEmulated = impl_->framesEmulated.load();
    s.measuredFPS = impl_->measuredFPS.load();
    s.audioUnderruns = impl_->audioUnderruns.load();
    s.audioOverflows = impl_->audioOverflows.load();
    return s;
}

} // namespace dualds
