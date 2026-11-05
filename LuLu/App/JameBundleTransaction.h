// jameLuLu - staged, reversible application bundle replacement.
// Designed for use from macOS AppKit installers; no private frameworks.
// GNU GPL-3.0-or-later.
#ifndef JameBundleTransaction_h
#define JameBundleTransaction_h

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Native same-volume bundle replacement. The previous bundle is retained
/// until an explicit health-verified finalize, not merely after process launch.
/// This class checks bundle metadata and filesystem identity; signing and
/// Network Extension health verification are separate release requirements.
@interface JameBundleTransaction : NSObject

@property (nonatomic, readonly, strong) NSURL *destinationURL;
@property (nonatomic, readonly, strong, nullable) NSURL *backupURL;

- (instancetype)initWithSourceURL:(NSURL *)sourceURL
                  destinationURL:(NSURL *)destinationURL
                expectedBundleID:(NSString *)expectedBundleID NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// Copy and inspect an isolated bundle on the destination volume.
/// The currently installed app is never modified by this step.
- (BOOL)prepareWithError:(NSError * _Nullable * _Nullable)error;

/// Atomically replace existing bundle using NSFileManager with a retained
/// backup; first-time install uses a same-directory move.
- (BOOL)activateWithError:(NSError * _Nullable * _Nullable)error;

/// Restore the prior installed bundle after a failed launch.
- (BOOL)rollbackWithError:(NSError * _Nullable * _Nullable)error;

/// Delete the previous version only after external runtime health checks pass.
- (BOOL)finalizeWithError:(NSError * _Nullable * _Nullable)error;

/// Release uncommitted staged data and the cross-process installation lock.
/// Never deletes a backup produced by an activated replacement.
- (void)discardStaging;

@end

NS_ASSUME_NONNULL_END
#endif
