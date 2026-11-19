// DualDS — Objective-C interface to the emulator core, the only API Swift uses.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.
//
// No C++ types appear here, so Swift imports it through the bridging header.
// Threading: input, frame and audio methods are safe from any thread. Lifecycle and state
// methods may be called from any thread except the emulation thread (never from onFrame).

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Pixels per DS screen (256 × 192). Framebuffers are 32-bit little-endian BGRA.
extern const NSInteger DSScreenWidth NS_SWIFT_NAME(DSCore.screenWidth);
extern const NSInteger DSScreenHeight NS_SWIFT_NAME(DSCore.screenHeight);
extern const double DSNativeFrameRate NS_SWIFT_NAME(DSCore.nativeFrameRate);

extern NSErrorDomain const DSCoreErrorDomain;
typedef NS_ERROR_ENUM(DSCoreErrorDomain, DSCoreErrorCode) {
    DSCoreErrorFileNotFound = 1,
    DSCoreErrorReadFailed,
    DSCoreErrorInvalidROM,
    DSCoreErrorNoROMLoaded,
    DSCoreErrorAlreadyRunning,
    DSCoreErrorStateIOFailed,
    DSCoreErrorStateIncompatible,
    DSCoreErrorSaveIOFailed,
};

/// Raw values match the DS key bit positions used by melonDS.
typedef NS_ENUM(NSInteger, DSButton) {
    DSButtonA = 0, DSButtonB = 1, DSButtonSelect = 2, DSButtonStart = 3,
    DSButtonRight = 4, DSButtonLeft = 5, DSButtonUp = 6, DSButtonDown = 7,
    DSButtonR = 8, DSButtonL = 9, DSButtonX = 10, DSButtonY = 11,
};

typedef NS_ENUM(NSInteger, DSRunState) {
    DSRunStateIdle, DSRunStateRunning, DSRunStatePaused, DSRunStateStopped,
};

/// Thread-safe per the contract at the top of this file, hence Sendable in Swift.
NS_SWIFT_NAME(DSCore) NS_SWIFT_SENDABLE
@interface DSCoreBridge : NSObject

@property (class, nonatomic, readonly) NSString *melonDSVersion;

- (instancetype)init;

/// Called on the emulation thread after each frame. Keep it trivial (e.g. signal a display link).
@property (atomic, copy, nullable) void (^onFrame)(uint64_t frameNumber);
/// Called on the emulation thread when the core stops by itself (power-off, crash, GBA mode).
@property (atomic, copy, nullable) void (^onStopped)(NSString *reason);

// Lifecycle
- (BOOL)loadGameAtURL:(NSURL *)romURL saveURL:(NSURL *)saveURL error:(NSError **)error
    NS_SWIFT_NAME(loadGame(at:save:));
- (BOOL)startWithError:(NSError **)error NS_SWIFT_NAME(start());
- (void)pause;
- (void)resume;
- (void)stop;
- (BOOL)resetWithError:(NSError **)error NS_SWIFT_NAME(reset());
@property (nonatomic, readonly) DSRunState runState;
/// Runs frames on the calling thread; only while not started. For tests and benchmarks.
- (NSInteger)runFramesBlocking:(NSInteger)count NS_SWIFT_NAME(runFramesBlocking(_:));

// Input
- (void)setButton:(DSButton)button pressed:(BOOL)pressed NS_SWIFT_NAME(setButton(_:pressed:));
- (void)setTouchX:(NSInteger)x y:(NSInteger)y touching:(BOOL)touching NS_SWIFT_NAME(setTouch(x:y:touching:));
- (void)setFastForward:(BOOL)enabled;
- (void)setLidClosed:(BOOL)closed;

// Video: each buffer must hold DSScreenWidth * DSScreenHeight pixels. Either may be NULL.
- (BOOL)copyFramebufferTop:(nullable uint32_t *)top bottom:(nullable uint32_t *)bottom
               frameNumber:(nullable uint64_t *)frameNumber NS_SWIFT_NAME(copyFramebuffer(top:bottom:frameNumber:));
@property (nonatomic, readonly) uint64_t latestFrameNumber;

// Audio: interleaved stereo int16 at audioSampleRate. Single consumer.
- (NSInteger)readAudio:(int16_t *)interleaved frames:(NSInteger)frames NS_SWIFT_NAME(readAudio(into:frames:));
@property (nonatomic, readonly) NSInteger audioFramesAvailable;
@property (nonatomic, readonly) double audioSampleRate;

// Saves
- (BOOL)flushSaveWithError:(NSError **)error NS_SWIFT_NAME(flushSave());
@property (nonatomic, readonly) BOOL hasPendingSave;
- (BOOL)saveStateToURL:(NSURL *)url error:(NSError **)error NS_SWIFT_NAME(saveState(to:));
- (BOOL)loadStateFromURL:(NSURL *)url error:(NSError **)error NS_SWIFT_NAME(loadState(from:));

// Stats
@property (nonatomic, readonly) uint64_t framesEmulated;
@property (nonatomic, readonly) double measuredFPS;
@property (nonatomic, readonly) uint64_t audioUnderruns;
@property (nonatomic, readonly) uint64_t audioOverflows;

@end

NS_ASSUME_NONNULL_END
