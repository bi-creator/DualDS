// DualDS headless core tests: drive the real melonDS core through DSSession with the
// original DualDS test ROM (Tests/Fixtures/testrom). No mocks: every assertion is on
// pixels, samples and states produced by actual emulation.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.

#include "DualDSCore/DSSession.h"

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iterator>
#include <string>
#include <thread>
#include <vector>

using namespace dualds;

static int gFailures = 0;
#define CHECK(cond, msg)                                                         \
    do {                                                                         \
        if (!(cond)) { std::printf("  FAIL: %s (%s:%d)\n", msg, __FILE__, __LINE__); ++gFailures; } \
        else std::printf("  ok:   %s\n", msg);                                   \
    } while (0)

struct RGB { int r, g, b; };
static RGB rgb(uint32_t bgra) { return { int((bgra >> 16) & 0xFF), int((bgra >> 8) & 0xFF), int(bgra & 0xFF) }; }

enum class Colour { Red, Green, Blue, Other };
static Colour classify(const std::vector<uint32_t>& px)
{
    // Every pixel must agree, so a partially drawn or garbage frame fails.
    Colour first = Colour::Other;
    for (size_t i = 0; i < px.size(); ++i)
    {
        RGB c = rgb(px[i]);
        Colour k = (c.r > 200 && c.g < 40 && c.b < 40) ? Colour::Red
                 : (c.g > 200 && c.r < 40 && c.b < 40) ? Colour::Green
                 : (c.b > 200 && c.r < 40 && c.g < 40) ? Colour::Blue : Colour::Other;
        if (i == 0) first = k;
        else if (k != first) return Colour::Other;
    }
    return first;
}

// The fixture repaints VRAM from uncached main RAM (~1.5 frames per pass), so give
// input changes a few frames to fully land before asserting on pixels.
static constexpr uint64_t kSettleFrames = 10;

static std::string tmpPath(const char* name) { return std::string("/tmp/dualds-test-") + name; }

int main(int argc, char** argv)
{
    if (argc < 2) { std::fprintf(stderr, "usage: %s <dualds-test.nds>\n", argv[0]); return 2; }
    const std::string rom = argv[1];
    const std::string save = tmpPath("game.sav");
    std::remove(save.c_str());
    std::printf("melonDS %s\n", melonDSVersion());

    std::vector<uint32_t> top(kScreenPixels), bottom(kScreenPixels);

    std::printf("[load failures]\n");
    {
        DSSession s;
        CHECK(s.loadROM("/nonexistent/x.nds", save) == SessionError::FileNotFound, "missing file -> FileNotFound");
        const std::string junk = tmpPath("junk.nds");
        { std::ofstream(junk, std::ios::binary) << std::string(0x2000, '\x7F'); }
        CHECK(s.loadROM(junk, save) == SessionError::InvalidROM, "garbage file -> InvalidROM");
        CHECK(s.start() == SessionError::NoROMLoaded, "start without ROM -> NoROMLoaded");
    }

    std::printf("[boot + video + input + audio]\n");
    {
        DSSession s;
        std::string detail;
        SessionError e = s.loadROM(rom, save, &detail);
        CHECK(e == SessionError::None, (std::string("test ROM loads: ") + describe(e) + " " + detail).c_str());
        CHECK(!s.copyLatestFrame(top.data(), bottom.data()), "no frame before emulation");
        CHECK(s.runFramesBlocking(60) == 60, "runs 60 frames");
        uint64_t fn = 0;
        CHECK(s.copyLatestFrame(top.data(), bottom.data(), &fn), "frame available");
        CHECK(fn == 60, "frame number tracks emulated frames");
        RGB t0 = rgb(top[0]), b0 = rgb(bottom[0]);
        std::printf("        top[0]=(%d,%d,%d) bottom[0]=(%d,%d,%d)\n", t0.r, t0.g, t0.b, b0.r, b0.g, b0.b);
        CHECK(classify(top) == Colour::Red, "top screen is uniformly red (ARM9 program ran, VRAM display)");
        CHECK(classify(bottom) == Colour::Blue, "bottom screen is uniformly blue (engine B backdrop)");

        s.setButton(Button::A, true);
        s.runFramesBlocking(kSettleFrames);
        s.copyLatestFrame(top.data(), nullptr);
        CHECK(classify(top) == Colour::Green, "holding A turns top screen green (KEYINPUT path)");
        s.setButton(Button::A, false);
        s.runFramesBlocking(kSettleFrames);
        s.copyLatestFrame(top.data(), nullptr);
        CHECK(classify(top) == Colour::Red, "releasing A turns it red again");

        CHECK(s.audioFramesAvailable() == 12000, "audio ring caps at 250 ms (overflow drops, never grows)");
        CHECK(s.stats().audioOverflows > 0, "overflow is counted");
        std::vector<int16_t> pcm(16384 * 2);
        s.readAudio(pcm.data(), 16384);
        CHECK(s.audioFramesAvailable() == 0, "ring drains");
        s.runFramesBlocking(1);
        const size_t perFrame = s.audioFramesAvailable();
        std::printf("        audio frames per video frame: %zu (expected ~802 = 48000/59.83)\n", perFrame);
        CHECK(perFrame > 760 && perFrame < 840, "SPU output rate matches 48 kHz");
        CHECK(s.readAudio(pcm.data(), 512) == 512, "audio can be read back");

        std::printf("[save states]\n");
        const std::string st = tmpPath("slot1.mln");
        CHECK(s.saveState(st, &detail) == SessionError::None, "saveState writes a file");
        s.setButton(Button::A, true);
        s.runFramesBlocking(kSettleFrames);
        s.copyLatestFrame(top.data(), nullptr);
        CHECK(classify(top) == Colour::Green, "state diverged (green) after save");
        s.setButton(Button::A, false);
        CHECK(s.loadState(st, &detail) == SessionError::None, (std::string("loadState succeeds ") + detail).c_str());
        const std::string st2 = tmpPath("slot1-again.mln");
        CHECK(s.saveState(st2) == SessionError::None, "re-save after load");
        auto slurp = [](const std::string& p) { std::ifstream f(p, std::ios::binary); return std::string(std::istreambuf_iterator<char>(f), {}); };
        const std::string a = slurp(st), b = slurp(st2);
        std::printf("        state size: %zu bytes\n", a.size());
        CHECK(!a.empty() && a == b, "restored console state is byte-identical to the saved one");
        s.runFramesBlocking(1);
        s.copyLatestFrame(top.data(), nullptr);
        CHECK(classify(top) == Colour::Red, "emulation continues from restored state");

        const std::string bad = tmpPath("bad.mln");
        { std::ofstream(bad, std::ios::binary) << std::string(4096, '\0'); }
        CHECK(s.loadState(bad, &detail) == SessionError::StateIncompatible, "corrupt state rejected");
        CHECK(s.runFramesBlocking(2) == 2, "emulation still runs after rejected state");
        CHECK(s.loadState("/nonexistent.mln") == SessionError::StateIOFailed, "missing state -> StateIOFailed");

        CHECK(s.reset() == SessionError::None, "reset");
        CHECK(s.runFramesBlocking(10) == 10, "runs after reset");
        s.copyLatestFrame(top.data(), nullptr);
        CHECK(classify(top) == Colour::Red, "ROM re-boots after reset");
    }

    std::printf("[threaded pacing]\n");
    {
        DSSession s;
        CHECK(s.loadROM(rom, save) == SessionError::None, "load");
        CHECK(s.start() == SessionError::None, "start");
        CHECK(s.start() == SessionError::AlreadyRunning, "double start rejected");
        std::this_thread::sleep_for(std::chrono::milliseconds(2200));
        SessionStats st = s.stats();
        std::printf("        frames=%llu fps=%.2f\n", (unsigned long long)st.framesEmulated, st.measuredFPS);
        CHECK(st.measuredFPS > 57.0 && st.measuredFPS < 62.5, "paced to native ~59.83 fps");

        s.pause();
        std::this_thread::sleep_for(std::chrono::milliseconds(150));
        const uint64_t a = s.stats().framesEmulated;
        std::this_thread::sleep_for(std::chrono::milliseconds(300));
        CHECK(s.stats().framesEmulated == a, "no frames while paused");
        CHECK(s.runState() == RunState::Paused, "state is Paused");
        s.resume();
        std::this_thread::sleep_for(std::chrono::milliseconds(300));
        CHECK(s.stats().framesEmulated > a, "frames resume");

        s.setButton(Button::A, true);
        std::this_thread::sleep_for(std::chrono::milliseconds(400));
        s.copyLatestFrame(top.data(), nullptr);
        CHECK(classify(top) == Colour::Green, "input from another thread reaches the running core");

        s.setFastForward(true);
        const uint64_t b = s.stats().framesEmulated;
        std::this_thread::sleep_for(std::chrono::milliseconds(1000));
        const uint64_t ffFrames = s.stats().framesEmulated - b;
        std::printf("        fast-forward: %llu frames in 1 s\n", (unsigned long long)ffFrames);
        CHECK(ffFrames > 70, "fast-forward runs faster than native");
        s.stop();
        CHECK(s.runState() == RunState::Stopped, "stopped");
    }

    std::printf("\n%s (%d failure%s)\n", gFailures ? "FAILED" : "PASSED", gFailures, gFailures == 1 ? "" : "s");
    return gFailures ? 1 : 0;
}
