// DualDS — implementation of melonDS's Platform interface (src/Platform.h).
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.
//
// Pure C++17 / POSIX so it builds for iOS, the iOS Simulator and the Linux/macOS host test runner.
// Features DualDS does not implement yet are reported honestly as absent (no data, no device),
// never simulated: local multiplayer, Wi-Fi, DSi camera/AAC, Slot-2 add-ons, microphone (Phase 8).

#include "SessionImpl.h"

#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <unistd.h>

#include "Platform.h"
#include "SPI_Firmware.h"

namespace dualds {
namespace {
std::mutex gLogMutex;
DSSession::Impl* gLogSink = nullptr;
std::string gLocalDirectory = ".";
} // namespace

void registerLogSink(DSSession::Impl* impl)
{
    std::lock_guard<std::mutex> lk(gLogMutex);
    gLogSink = impl;
}

void unregisterLogSink(DSSession::Impl* impl)
{
    std::lock_guard<std::mutex> lk(gLogMutex);
    if (gLogSink == impl) gLogSink = nullptr;
}
} // namespace dualds

namespace melonDS::Platform {

using dualds::DSSession;
static DSSession::Impl* implFrom(void* userdata) { return static_cast<DSSession::Impl*>(userdata); }

void SignalStop(StopReason reason, void* userdata)
{
    auto* impl = implFrom(userdata);
    if (!impl) return;
    const char* text = "stopped";
    switch (reason)
    {
    case StopReason::External: text = "Stopped by the user"; break;
    case StopReason::GBAModeNotSupported: text = "The game tried to enter GBA mode, which melonDS does not support"; break;
    case StopReason::BadExceptionRegion: text = "The emulated console crashed (bad exception region)"; break;
    case StopReason::PowerOff: text = "The emulated console powered off"; break;
    default: text = "The emulator stopped"; break;
    }
    {
        std::lock_guard<std::mutex> lk(impl->stopReasonMutex);
        impl->stopReason = text;
    }
    impl->coreStopped.store(true);
}

// ---- Files -----------------------------------------------------------------

std::string GetLocalFilePath(const std::string& filename)
{
    if (!filename.empty() && filename[0] == '/') return filename;
    return dualds::gLocalDirectory + "/" + filename;
}

static bool fileExistsPosix(const std::string& path) { return ::access(path.c_str(), F_OK) == 0; }

FileHandle* OpenFile(const std::string& path, FileMode mode)
{
    if ((mode & (FileMode::ReadWrite | FileMode::Append)) == FileMode::None)
    {
        Log(LogLevel::Error, "OpenFile: \"%s\" opened in neither read nor write mode\n", path.c_str());
        return nullptr;
    }
    const bool exists = fileExistsPosix(path);
    if ((mode & FileMode::NoCreate) && !exists) return nullptr;

    std::string m;
    const bool rw = (mode & FileMode::ReadWrite) == FileMode::ReadWrite;
    if (mode & FileMode::Append) m = rw ? "a+" : "a";
    else if (!(mode & FileMode::Write)) m = "r";
    else if ((mode & FileMode::NoCreate) || ((mode & FileMode::Preserve) && exists)) m = "r+";
    else m = rw ? "w+" : "w";
    if (!(mode & FileMode::Text)) m += 'b';

    FILE* f = std::fopen(path.c_str(), m.c_str());
    if (!f) Log(LogLevel::Debug, "OpenFile: failed to open \"%s\" (%s)\n", path.c_str(), m.c_str());
    return reinterpret_cast<FileHandle*>(f);
}

FileHandle* OpenLocalFile(const std::string& path, FileMode mode) { return OpenFile(GetLocalFilePath(path), mode); }
bool FileExists(const std::string& name) { return fileExistsPosix(name); }
bool LocalFileExists(const std::string& name) { return fileExistsPosix(GetLocalFilePath(name)); }

bool CheckFileWritable(const std::string& filepath)
{
    if (fileExistsPosix(filepath)) return ::access(filepath.c_str(), W_OK) == 0;
    FILE* f = std::fopen(filepath.c_str(), "ab");
    if (!f) return false;
    std::fclose(f);
    std::remove(filepath.c_str());
    return true;
}

bool CheckLocalFileWritable(const std::string& filepath) { return CheckFileWritable(GetLocalFilePath(filepath)); }

static FILE* F(FileHandle* h) { return reinterpret_cast<FILE*>(h); }

bool CloseFile(FileHandle* file) { return file && std::fclose(F(file)) == 0; }
bool IsEndOfFile(FileHandle* file) { return std::feof(F(file)) != 0; }
bool FileReadLine(char* str, int count, FileHandle* file) { return std::fgets(str, count, F(file)) != nullptr; }
u64 FilePosition(FileHandle* file) { long p = std::ftell(F(file)); return p < 0 ? 0 : static_cast<u64>(p); }

bool FileSeek(FileHandle* file, s64 offset, FileSeekOrigin origin)
{
    int whence = SEEK_SET;
    if (origin == FileSeekOrigin::Current) whence = SEEK_CUR;
    else if (origin == FileSeekOrigin::End) whence = SEEK_END;
    return fseeko(F(file), static_cast<off_t>(offset), whence) == 0;
}

void FileRewind(FileHandle* file) { std::rewind(F(file)); }
u64 FileRead(void* data, u64 size, u64 count, FileHandle* file) { return std::fread(data, size, count, F(file)); }
bool FileFlush(FileHandle* file) { return std::fflush(F(file)) == 0; }
u64 FileWrite(const void* data, u64 size, u64 count, FileHandle* file) { return std::fwrite(data, size, count, F(file)); }

u64 FileWriteFormatted(FileHandle* file, const char* fmt, ...)
{
    va_list args;
    va_start(args, fmt);
    int n = std::vfprintf(F(file), fmt, args);
    va_end(args);
    return n < 0 ? 0 : static_cast<u64>(n);
}

u64 FileLength(FileHandle* file)
{
    FILE* f = F(file);
    off_t pos = ftello(f);
    fseeko(f, 0, SEEK_END);
    off_t len = ftello(f);
    fseeko(f, pos, SEEK_SET);
    return len < 0 ? 0 : static_cast<u64>(len);
}

// ---- Logging ---------------------------------------------------------------

void Log(LogLevel level, const char* fmt, ...)
{
    char buf[1024];
    va_list args;
    va_start(args, fmt);
    std::vsnprintf(buf, sizeof(buf), fmt, args);
    va_end(args);

    std::lock_guard<std::mutex> lk(dualds::gLogMutex);
    if (dualds::gLogSink && dualds::gLogSink->callbacks.onLog)
        dualds::gLogSink->callbacks.onLog(static_cast<int>(level), buf);
    else if (level >= LogLevel::Warn)
        std::fputs(buf, stderr);
}

// ---- Threads and synchronisation ---------------------------------------------

struct Thread { std::thread t; };
Thread* Thread_Create(std::function<void()> func) { return new Thread{std::thread(std::move(func))}; }
void Thread_Free(Thread* thread) { if (thread && thread->t.joinable()) thread->t.detach(); delete thread; }
void Thread_Wait(Thread* thread) { if (thread && thread->t.joinable()) thread->t.join(); }

struct Semaphore { std::mutex m; std::condition_variable cv; int count = 0; };
Semaphore* Semaphore_Create() { return new Semaphore(); }
void Semaphore_Free(Semaphore* s) { delete s; }
void Semaphore_Reset(Semaphore* s) { std::lock_guard<std::mutex> lk(s->m); s->count = 0; }

void Semaphore_Wait(Semaphore* s)
{
    std::unique_lock<std::mutex> lk(s->m);
    s->cv.wait(lk, [s] { return s->count > 0; });
    --s->count;
}

bool Semaphore_TryWait(Semaphore* s, int timeout_ms)
{
    std::unique_lock<std::mutex> lk(s->m);
    if (timeout_ms <= 0)
    {
        if (s->count <= 0) return false;
    }
    else if (!s->cv.wait_for(lk, std::chrono::milliseconds(timeout_ms), [s] { return s->count > 0; }))
    {
        return false;
    }
    --s->count;
    return true;
}

void Semaphore_Post(Semaphore* s, int count)
{
    {
        std::lock_guard<std::mutex> lk(s->m);
        s->count += count;
    }
    if (count == 1) s->cv.notify_one();
    else s->cv.notify_all();
}

struct Mutex { std::mutex m; };
Mutex* Mutex_Create() { return new Mutex(); }
void Mutex_Free(Mutex* m) { delete m; }
void Mutex_Lock(Mutex* m) { m->m.lock(); }
void Mutex_Unlock(Mutex* m) { m->m.unlock(); }
bool Mutex_TryLock(Mutex* m) { return m->m.try_lock(); }

void Sleep(u64 usecs) { std::this_thread::sleep_for(std::chrono::microseconds(usecs)); }

u64 GetMSCount()
{
    using namespace std::chrono;
    return duration_cast<milliseconds>(steady_clock::now().time_since_epoch()).count();
}

u64 GetUSCount()
{
    using namespace std::chrono;
    return duration_cast<microseconds>(steady_clock::now().time_since_epoch()).count();
}

// ---- Persistence callbacks -----------------------------------------------------

void WriteNDSSave(const u8* savedata, u32 savelen, u32 /*writeoffset*/, u32 /*writelen*/, void* userdata)
{
    // The whole image is buffered; DSSession writes it out atomically after a quiet period.
    if (auto* impl = implFrom(userdata)) impl->onSaveWritten(savedata, savelen);
}

// Slot-2 (GBA) carts are not exposed by DualDS yet.
void WriteGBASave(const u8*, u32, u32, u32, void*) {}
// Generated firmware is rebuilt on every boot; user firmware settings arrive with Phase 8.
void WriteFirmware(const Firmware&, u32, u32, void*) {}
// The RTC is seeded from the device clock at load; in-game clock changes are not persisted.
void WriteDateTime(int, int, int, int, int, int, void*) {}

// ---- Local wireless multiplayer / Wi-Fi: not implemented (see KNOWN_ISSUES.md) -------

void MP_Begin(void*) {}
void MP_End(void*) {}
int MP_SendPacket(u8*, int, u64, void*) { return 0; }
int MP_RecvPacket(u8*, u64*, void*) { return 0; }
int MP_SendCmd(u8*, int, u64, void*) { return 0; }
int MP_SendReply(u8*, int, u64, u16, void*) { return 0; }
int MP_SendAck(u8*, int, u64, void*) { return 0; }
int MP_RecvHostPacket(u8*, u64*, void*) { return 0; }
u16 MP_RecvReplies(u8*, u64, u16, void*) { return 0; }
int Net_SendPacket(u8*, int, void*) { return 0; }
int Net_RecvPacket(u8*, void*) { return 0; }

// ---- DSi camera (DSi mode is not offered) ----------------------------------------

void Camera_Start(int, void*) {}
void Camera_Stop(int, void*) {}
void Camera_CaptureFrame(int, u32* frame, int width, int height, bool, void*)
{
    std::memset(frame, 0, static_cast<size_t>(width) * height * sizeof(u32));
}

// ---- Microphone: no input source yet (Phase 8) -> the console hears silence ------------

void Mic_Start(void*) {}
void Mic_Stop(void*) {}
int Mic_ReadInput(s16*, int, void*) { return 0; }

// ---- DSi AAC decoding (DSi mode is not offered) -----------------------------------

AACDecoder* AAC_Init() { return nullptr; }
void AAC_DeInit(AACDecoder*) {}
bool AAC_Configure(AACDecoder*, int, int) { return false; }
bool AAC_DecodeFrame(AACDecoder*, const void*, int, void*, int) { return false; }

// ---- Slot-2 add-ons ----------------------------------------------------------------

bool Addon_KeyDown(KeyType, void*) { return false; }
void Addon_RumbleStart(u32, void*) {}
void Addon_RumbleStop(void*) {}
float Addon_MotionQuery(MotionQueryType, void*) { return 0.0f; }

// ---- Dynamic libraries: iOS apps cannot load them --------------------------------------

DynamicLibrary* DynamicLibrary_Load(const char*) { return nullptr; }
void DynamicLibrary_Unload(DynamicLibrary*) {}
void* DynamicLibrary_LoadFunction(DynamicLibrary*, const char*) { return nullptr; }

} // namespace melonDS::Platform
