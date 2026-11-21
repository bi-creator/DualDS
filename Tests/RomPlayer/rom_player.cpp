// DualDS — headless ROM player for automated game tests (host only, never shipped).
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.
//
// Plays a .nds with a scripted input sequence on the DualDS core and saves PNG screenshots
// (top screen above bottom screen, 256x384). Used to test FoldPlay Originals quickly on the Mac.
//
//   rom_player <game.nds> <script.txt> <output dir>
//
// Script: one command per line, '#' comments.
//   wait <frames>                 run frames with the current input
//   hold <buttons...>             hold buttons (A B X Y L R START SELECT UP DOWN LEFT RIGHT)
//   release [buttons...]          release the listed buttons (all when none listed)
//   tap <button> [frames]         press for N frames (default 2), then release and run 2 frames
//   touch <x> <y> [frames]        touch the bottom screen for N frames (default 3), then lift
//   drag <x0> <y0> <x1> <y1> <frames>   touch moving from (x0,y0) to (x1,y1)
//   shot <name>                   save <output dir>/<name>.png
//   expect-diff <a> <b>           fail unless shots a and b differ (input changed the picture)
//   expect-same <a> <b>           fail unless shots a and b are identical (e.g. pause)
//   expect-alive                  fail if the core stopped (crash / power off)
//   repeat <n> ... end            repeat the enclosed commands n times
// Exit code 0 when every expectation passed.

#include "DualDSCore/DSSession.h"

#include <zlib.h>

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <map>
#include <sstream>
#include <string>
#include <vector>

using namespace dualds;

namespace {

struct Frame { std::vector<uint32_t> top, bottom; };

void put32(std::vector<uint8_t>& v, uint32_t x) { for (int i = 3; i >= 0; --i) v.push_back(uint8_t(x >> (8 * i))); }

void chunk(std::vector<uint8_t>& png, const char* type, const std::vector<uint8_t>& data)
{
    put32(png, uint32_t(data.size()));
    std::vector<uint8_t> body(type, type + 4);
    body.insert(body.end(), data.begin(), data.end());
    png.insert(png.end(), body.begin(), body.end());
    put32(png, uint32_t(crc32(0, body.data(), uInt(body.size()))));
}

bool writePNG(const std::string& path, const Frame& f)
{
    const int w = 256, h = 384;
    std::vector<uint8_t> raw;
    raw.reserve(size_t(h) * (1 + w * 3));
    for (int y = 0; y < h; ++y)
    {
        raw.push_back(0);
        const uint32_t* row = y < 192 ? &f.top[size_t(y) * w] : &f.bottom[size_t(y - 192) * w];
        for (int x = 0; x < w; ++x)
        {
            uint32_t p = row[x];
            raw.push_back(uint8_t(p >> 16)); raw.push_back(uint8_t(p >> 8)); raw.push_back(uint8_t(p));
        }
    }
    uLongf len = compressBound(uLong(raw.size()));
    std::vector<uint8_t> z(len);
    if (compress2(z.data(), &len, raw.data(), uLong(raw.size()), 6) != Z_OK) return false;
    z.resize(len);
    std::vector<uint8_t> png = { 0x89, 'P', 'N', 'G', '\r', '\n', 0x1A, '\n' };
    std::vector<uint8_t> ihdr;
    put32(ihdr, w); put32(ihdr, h);
    ihdr.insert(ihdr.end(), { 8, 2, 0, 0, 0 });
    chunk(png, "IHDR", ihdr);
    chunk(png, "IDAT", z);
    chunk(png, "IEND", {});
    std::ofstream out(path, std::ios::binary);
    out.write(reinterpret_cast<const char*>(png.data()), std::streamsize(png.size()));
    return bool(out);
}

bool buttonNamed(std::string n, Button& b)
{
    for (auto& c : n) c = char(std::toupper(c));
    static const std::map<std::string, Button> names = {
        {"A", Button::A}, {"B", Button::B}, {"SELECT", Button::Select}, {"START", Button::Start},
        {"RIGHT", Button::Right}, {"LEFT", Button::Left}, {"UP", Button::Up}, {"DOWN", Button::Down},
        {"R", Button::R}, {"L", Button::L}, {"X", Button::X}, {"Y", Button::Y}};
    auto it = names.find(n);
    if (it == names.end()) return false;
    b = it->second;
    return true;
}

struct Player {
    DSSession& s;
    std::string outDir;
    uint32_t held = 0;
    std::map<std::string, Frame> shots;
    int failures = 0;
    bool stopped = false;
    uint64_t frames = 0;

    void run(uint64_t n) { s.setButtonMask(held); frames += s.runFramesBlocking(n); }
    Frame grab()
    {
        Frame f{ std::vector<uint32_t>(kScreenPixels), std::vector<uint32_t>(kScreenPixels) };
        s.copyLatestFrame(f.top.data(), f.bottom.data());
        return f;
    }
    void fail(int line, const std::string& msg) { std::printf("  FAIL line %d: %s\n", line, msg.c_str()); ++failures; }

    void exec(const std::vector<std::pair<int, std::string>>& lines, size_t& i, size_t end)
    {
        while (i < end)
        {
            auto [ln, text] = lines[i++];
            std::istringstream in(text);
            std::string cmd; in >> cmd;
            if (cmd == "wait") { uint64_t n = 1; in >> n; run(n); }
            else if (cmd == "hold" || cmd == "release")
            {
                std::string name; bool any = false;
                while (in >> name)
                {
                    Button b;
                    if (!buttonNamed(name, b)) { fail(ln, "unknown button " + name); continue; }
                    any = true;
                    if (cmd == "hold") held |= 1u << uint32_t(b); else held &= ~(1u << uint32_t(b));
                }
                if (cmd == "release" && !any) held = 0;
                s.setButtonMask(held);
            }
            else if (cmd == "tap")
            {
                std::string name; uint64_t n = 2; in >> name >> n;
                Button b;
                if (!buttonNamed(name, b)) { fail(ln, "unknown button " + name); continue; }
                held |= 1u << uint32_t(b); run(n);
                held &= ~(1u << uint32_t(b)); run(2);
            }
            else if (cmd == "touch")
            {
                int x = 0, y = 0; uint64_t n = 3; in >> x >> y >> n;
                s.setTouch(x, y, true); run(n);
                s.setTouch(0, 0, false); run(2);
            }
            else if (cmd == "drag")
            {
                int x0, y0, x1, y1; uint64_t n = 10; in >> x0 >> y0 >> x1 >> y1 >> n;
                for (uint64_t k = 0; k <= n; ++k)
                {
                    int x = x0 + int((x1 - x0) * double(k) / double(n)), y = y0 + int((y1 - y0) * double(k) / double(n));
                    s.setTouch(x, y, true); run(1);
                }
                s.setTouch(0, 0, false); run(2);
            }
            else if (cmd == "shot")
            {
                std::string name; in >> name;
                Frame f = grab();
                if (!writePNG(outDir + "/" + name + ".png", f)) fail(ln, "could not write " + name);
                shots[name] = std::move(f);
                std::printf("  shot %s (frame %llu)\n", name.c_str(), (unsigned long long)frames);
            }
            else if (cmd == "expect-diff" || cmd == "expect-same")
            {
                std::string a, b; in >> a >> b;
                if (!shots.count(a) || !shots.count(b)) { fail(ln, "unknown shot"); continue; }
                bool same = shots[a].top == shots[b].top && shots[a].bottom == shots[b].bottom;
                if ((cmd == "expect-diff") == same) fail(ln, cmd + " " + a + " " + b);
                else std::printf("  ok   %s %s %s\n", cmd.c_str(), a.c_str(), b.c_str());
            }
            else if (cmd == "expect-alive")
            {
                if (stopped || s.runState() == RunState::Stopped) fail(ln, "core stopped");
                else std::printf("  ok   alive at frame %llu\n", (unsigned long long)frames);
            }
            else if (cmd == "repeat")
            {
                int n = 1; in >> n;
                size_t body = i, depth = 1, j = i;
                for (; j < end; ++j)
                {
                    std::string first; std::istringstream(lines[j].second) >> first;
                    if (first == "repeat") ++depth;
                    else if (first == "end" && --depth == 0) break;
                }
                for (int r = 0; r < n; ++r) { size_t k = body; exec(lines, k, j); }
                i = j + 1;
            }
            else if (cmd == "end") {}
            else fail(ln, "unknown command " + cmd);
        }
    }
};

} // namespace

int main(int argc, char** argv)
{
    if (argc < 4) { std::fprintf(stderr, "usage: %s <game.nds> <script.txt> <output dir>\n", argv[0]); return 2; }
    std::vector<std::pair<int, std::string>> lines;
    {
        std::ifstream in(argv[2]);
        if (!in) { std::fprintf(stderr, "cannot read %s\n", argv[2]); return 2; }
        std::string l; int n = 0;
        while (std::getline(in, l))
        {
            ++n;
            if (auto h = l.find('#'); h != std::string::npos) l.erase(h);
            if (l.find_first_not_of(" \t\r") == std::string::npos) continue;
            lines.emplace_back(n, l);
        }
    }
    std::string save = std::string(argv[3]) + "/game.sav";
    std::remove(save.c_str());
    Callbacks cb;
    bool stopped = false;
    cb.onStopped = [&](const std::string& why) { stopped = true; std::printf("  core stopped: %s\n", why.c_str()); };
    DSSession s({}, cb);
    std::string detail;
    if (s.loadROM(argv[1], save, &detail) != SessionError::None) { std::printf("  FAIL load: %s\n", detail.c_str()); return 1; }
    Player p{ s, argv[3] };
    size_t i = 0;
    p.exec(lines, i, lines.size());
    p.stopped = stopped;
    std::printf("%s: %llu frames, %d failure(s)\n", argv[1], (unsigned long long)p.frames, p.failures);
    return p.failures == 0 && !stopped ? 0 : 1;
}
