// DualDS — Objective-C++ bridge: converts between Foundation types and dualds::DSSession.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.
//
// Deliberately logic-free: lifecycle, threading, pacing, buffering and saves live in
// EmulatorCore/DualDSCore (tested headless). This file only converts types and errors.

#import "DSCoreBridge.h"

#include <memory>
#include <string>

#include "DualDSCore/DSSession.h"

const NSInteger DSScreenWidth = dualds::kScreenWidth;
const NSInteger DSScreenHeight = dualds::kScreenHeight;
const double DSNativeFrameRate = dualds::kNativeFrameRate;
NSErrorDomain const DSCoreErrorDomain = @"DualDS.CoreError";

static DSCoreErrorCode codeFor(dualds::SessionError e)
{
    switch (e)
    {
    case dualds::SessionError::FileNotFound: return DSCoreErrorFileNotFound;
    case dualds::SessionError::ReadFailed: return DSCoreErrorReadFailed;
    case dualds::SessionError::InvalidROM: return DSCoreErrorInvalidROM;
    case dualds::SessionError::NoROMLoaded: return DSCoreErrorNoROMLoaded;
    case dualds::SessionError::AlreadyRunning: return DSCoreErrorAlreadyRunning;
    case dualds::SessionError::StateIOFailed: return DSCoreErrorStateIOFailed;
    case dualds::SessionError::StateIncompatible: return DSCoreErrorStateIncompatible;
    case dualds::SessionError::SaveIOFailed: return DSCoreErrorSaveIOFailed;
    case dualds::SessionError::None: break;
    }
    return DSCoreErrorReadFailed;
}

/// Returns YES for None; otherwise fills *error and returns NO.
static BOOL check(dualds::SessionError e, const std::string& detail, NSError** error)
{
    if (e == dualds::SessionError::None) return YES;
    if (error)
    {
        NSMutableDictionary* info = [NSMutableDictionary dictionary];
        info[NSLocalizedDescriptionKey] = @(dualds::describe(e));
        if (!detail.empty()) info[NSLocalizedFailureReasonErrorKey] = @(detail.c_str());
        *error = [NSError errorWithDomain:DSCoreErrorDomain code:codeFor(e) userInfo:info];
    }
    return NO;
}

static std::string pathOf(NSURL* url) { return url.fileSystemRepresentation ?: ""; }

@implementation DSCoreBridge {
    std::unique_ptr<dualds::DSSession> _session;
}

+ (NSString*)melonDSVersion { return @(dualds::melonDSVersion()); }

- (instancetype)init
{
    if ((self = [super init]))
    {
        __weak DSCoreBridge* weakSelf = self;
        dualds::Callbacks cb;
        cb.onFrame = [weakSelf](uint64_t n) {
            DSCoreBridge* strongSelf = weakSelf;
            void (^block)(uint64_t) = strongSelf.onFrame;
            if (block) block(n);
        };
        cb.onStopped = [weakSelf](const std::string& reason) {
            DSCoreBridge* strongSelf = weakSelf;
            void (^block)(NSString*) = strongSelf.onStopped;
            if (block) block(@(reason.c_str()));
        };
        cb.onLog = [](int level, const std::string& msg) {
            if (level >= 2) NSLog(@"[melonDS] %s", msg.c_str()); // warnings and errors only
        };
        _session = std::make_unique<dualds::DSSession>(dualds::SessionConfig{}, std::move(cb));
    }
    return self;
}

- (void)dealloc { _session->stop(); }

- (BOOL)loadGameAtURL:(NSURL*)romURL saveURL:(NSURL*)saveURL error:(NSError**)error
{
    std::string detail;
    return check(_session->loadROM(pathOf(romURL), pathOf(saveURL), &detail), detail, error);
}

- (BOOL)startWithError:(NSError**)error { return check(_session->start(), {}, error); }
- (void)pause { _session->pause(); }
- (void)resume { _session->resume(); }
- (void)stop { _session->stop(); }
- (BOOL)resetWithError:(NSError**)error { return check(_session->reset(), {}, error); }

- (DSRunState)runState
{
    switch (_session->runState())
    {
    case dualds::RunState::Idle: return DSRunStateIdle;
    case dualds::RunState::Running: return DSRunStateRunning;
    case dualds::RunState::Paused: return DSRunStatePaused;
    case dualds::RunState::Stopped: return DSRunStateStopped;
    }
    return DSRunStateStopped;
}

- (NSInteger)runFramesBlocking:(NSInteger)count
{
    return count <= 0 ? 0 : (NSInteger)_session->runFramesBlocking((uint64_t)count);
}

- (void)setButton:(DSButton)button pressed:(BOOL)pressed
{
    if (button < DSButtonA || button > DSButtonY) return;
    _session->setButton(static_cast<dualds::Button>(button), pressed);
}

- (void)setTouchX:(NSInteger)x y:(NSInteger)y touching:(BOOL)touching
{
    _session->setTouch((int)x, (int)y, touching);
}

- (void)setFastForward:(BOOL)enabled { _session->setFastForward(enabled); }
- (void)setLidClosed:(BOOL)closed { _session->setLidClosed(closed); }

- (BOOL)copyFramebufferTop:(uint32_t*)top bottom:(uint32_t*)bottom frameNumber:(uint64_t*)frameNumber
{
    return _session->copyLatestFrame(top, bottom, frameNumber);
}

- (uint64_t)latestFrameNumber { return _session->latestFrameNumber(); }

- (NSInteger)readAudio:(int16_t*)interleaved frames:(NSInteger)frames
{
    return frames <= 0 ? 0 : (NSInteger)_session->readAudio(interleaved, (size_t)frames);
}

- (NSInteger)audioFramesAvailable { return (NSInteger)_session->audioFramesAvailable(); }
- (double)audioSampleRate { return _session->audioSampleRate(); }

- (BOOL)flushSaveWithError:(NSError**)error { return check(_session->flushSave(), {}, error); }
- (BOOL)hasPendingSave { return _session->hasPendingSave(); }

- (BOOL)saveStateToURL:(NSURL*)url error:(NSError**)error
{
    std::string detail;
    return check(_session->saveState(pathOf(url), &detail), detail, error);
}

- (BOOL)loadStateFromURL:(NSURL*)url error:(NSError**)error
{
    std::string detail;
    return check(_session->loadState(pathOf(url), &detail), detail, error);
}

- (uint64_t)framesEmulated { return _session->stats().framesEmulated; }
- (double)measuredFPS { return _session->stats().measuredFPS; }
- (uint64_t)audioUnderruns { return _session->stats().audioUnderruns; }
- (uint64_t)audioOverflows { return _session->stats().audioOverflows; }

@end
