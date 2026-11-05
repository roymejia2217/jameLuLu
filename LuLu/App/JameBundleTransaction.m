// jameLuLu - transactional filesystem operations for app upgrades.
// GNU GPL-3.0-or-later.
#import "JameBundleTransaction.h"
#import "../Shared/JameIdentityPolicy.h"

#import <errno.h>
#import <fcntl.h>
#import <sys/file.h>
#import <sys/stat.h>
#import <unistd.h>

static NSString * const JameInstallErrorDomain = @"io.github.roymejia2217.jamelulu.install";

static BOOL JameInstallFail(NSError **error, NSInteger code, NSString *detail)
{
    if (error)
        *error = [NSError errorWithDomain:JameInstallErrorDomain
                                    code:code
                                userInfo:@{NSLocalizedDescriptionKey: detail}];
    return NO;
}

@interface JameBundleTransaction ()
{
    NSURL *_sourceURL;
    NSURL *_destinationURL;
    NSURL *_stagedURL;
    NSURL *_backupURL;
    NSString *_expectedBundleID;
    NSNumber *_originalInode;
    NSNumber *_originalDevice;
    BOOL _hadDestination;
    BOOL _prepared;
    BOOL _activated;
    int _lockFD;
}
@end

@implementation JameBundleTransaction

- (NSURL *)destinationURL { return _destinationURL; }
- (NSURL *)backupURL { return _backupURL; }

- (instancetype)initWithSourceURL:(NSURL *)sourceURL
                  destinationURL:(NSURL *)destinationURL
                expectedBundleID:(NSString *)expectedBundleID
{
    self = [super init];
    if (self) {
        _sourceURL = [sourceURL copy];
        _destinationURL = [destinationURL copy];
        _expectedBundleID = [expectedBundleID copy];
        _lockFD = -1;
    }
    return self;
}

- (void)unlock
{
    if (_lockFD >= 0) {
        flock(_lockFD, LOCK_UN);
        close(_lockFD);
        _lockFD = -1;
    }
}

- (void)discardStaging
{
    if (_stagedURL) {
        [[NSFileManager defaultManager] removeItemAtURL:_stagedURL error:NULL];
        _stagedURL = nil;
    }
    _prepared = NO;
    [self unlock];
}

- (void)dealloc
{
    // Crash recovery retains the old backup; never delete it implicitly.
    [self discardStaging];
}

- (BOOL)isExpectedBundle:(NSURL *)url
{
    NSString *identifier = [NSBundle bundleWithURL:url].bundleIdentifier;
    return JameIsOwnedBundle(identifier, url.path, _expectedBundleID, url.lastPathComponent) &&
           [identifier isEqualToString:_expectedBundleID];
}

- (BOOL)checkDestinationUnchanged:(NSError **)error
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *attrs = [fm attributesOfItemAtPath:_destinationURL.path error:NULL];
    if (_hadDestination) {
        if (![self isExpectedBundle:_destinationURL] ||
            ![attrs[NSFileSystemFileNumber] isEqual:_originalInode] ||
            ![attrs[NSFileSystemNumber] isEqual:_originalDevice]) {
            return JameInstallFail(error, 10, @"Installed bundle changed during preparation; refusing replacement");
        }
    } else if (attrs != nil || [fm fileExistsAtPath:_destinationURL.path]) {
        return JameInstallFail(error, 11, @"Destination appeared during preparation; refusing replacement");
    }
    return YES;
}

- (BOOL)prepareWithError:(NSError **)error
{
    if (_prepared || _activated || _lockFD >= 0)
        return JameInstallFail(error, 1, @"Installation transaction already started");
    if (!_sourceURL.isFileURL || !_destinationURL.isFileURL || !_expectedBundleID.length ||
        JameBundleLocationsEqual(_sourceURL.path, _destinationURL.path))
        return JameInstallFail(error, 2, @"Invalid source, destination or in-place installation");
    if (![self isExpectedBundle:_sourceURL])
        return JameInstallFail(error, 3, @"Source application does not have the expected fork identity");

    NSFileManager *fm = [NSFileManager defaultManager];
    NSURL *parent = [_destinationURL URLByDeletingLastPathComponent];
    NSString *lockName = @".jameLuLu.install.lock";
    NSString *lockPath = [[parent URLByAppendingPathComponent:lockName] path];
    _lockFD = open(lockPath.fileSystemRepresentation,
                   O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (_lockFD < 0)
        return JameInstallFail(error, errno, @"Cannot create a safe installation lock");
    struct stat lockStat;
    if (fstat(_lockFD, &lockStat) != 0 || !S_ISREG(lockStat.st_mode) ||
        flock(_lockFD, LOCK_EX | LOCK_NB) != 0) {
        [self unlock];
        return JameInstallFail(error, 4, @"Another installation is active or lock is unsafe");
    }

    NSDictionary *attrs = [fm attributesOfItemAtPath:_destinationURL.path error:NULL];
    _hadDestination = (attrs != nil);
    if (_hadDestination) {
        if ([attrs[NSFileType] isEqualToString:NSFileTypeSymbolicLink] ||
            ![self isExpectedBundle:_destinationURL] ||
            !attrs[NSFileSystemFileNumber] || !attrs[NSFileSystemNumber]) {
            [self unlock];
            return JameInstallFail(error, 5, @"Refusing to overwrite an unknown or symbolic-link bundle");
        }
        _originalInode = attrs[NSFileSystemFileNumber];
        _originalDevice = attrs[NSFileSystemNumber];
    }

    NSString *stageName = [NSString stringWithFormat:@".jameLuLu.stage-%@.app", [NSUUID UUID].UUIDString];
    _stagedURL = [parent URLByAppendingPathComponent:stageName isDirectory:YES];
    if (![fm copyItemAtURL:_sourceURL toURL:_stagedURL error:error]) {
        [self discardStaging];
        return NO;
    }
    if (![self isExpectedBundle:_stagedURL]) {
        [self discardStaging];
        return JameInstallFail(error, 6, @"Staged application failed its bundle identity check");
    }
    _prepared = YES;
    return YES;
}

- (BOOL)activateWithError:(NSError **)error
{
    if (!_prepared || !_stagedURL)
        return JameInstallFail(error, 7, @"Bundle was not prepared");
    if (![self checkDestinationUnchanged:error])
        return NO;

    NSFileManager *fm = [NSFileManager defaultManager];
    if (_hadDestination) {
        NSString *backupName = [NSString stringWithFormat:@".jameLuLu.previous-%@.app",
                                 [NSUUID UUID].UUIDString];
        NSURL *backup = [[_destinationURL URLByDeletingLastPathComponent]
                         URLByAppendingPathComponent:backupName isDirectory:YES];
        if ([fm fileExistsAtPath:backup.path])
            return JameInstallFail(error, 8, @"Backup path unexpectedly exists");

        BOOL replaced = [fm replaceItemAtURL:_destinationURL
                               withItemAtURL:_stagedURL
                              backupItemName:backupName
                                     options:(NSFileManagerItemReplacementUsingNewMetadataOnly |
                                              NSFileManagerItemReplacementWithoutDeletingBackupItem)
                            resultingItemURL:NULL
                                       error:error];
        if (!replaced) {
            // Foundation may have moved the old item during a failed replace;
            // never delete the backup or pretend the original is intact.
            if ([fm fileExistsAtPath:backup.path]) _backupURL = backup;
            return NO;
        }
        _backupURL = backup;
    } else if (![fm moveItemAtURL:_stagedURL toURL:_destinationURL error:error]) {
        return NO;
    }
    _stagedURL = nil;
    _prepared = NO;
    _activated = YES;
    return YES;
}

- (BOOL)rollbackWithError:(NSError **)error
{
    // A failed Foundation replacement can move the original item into its
    // backup location before reporting an error. Recover that partial state
    // as well as a fully activated replacement.
    if (!_activated && (!_backupURL ||
                        ![[NSFileManager defaultManager] fileExistsAtPath:_backupURL.path]))
        return JameInstallFail(error, 12, @"No backed-up installation to roll back");
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:_destinationURL.path] &&
        ![self isExpectedBundle:_destinationURL])
        return JameInstallFail(error, 13, @"Cannot overwrite a changed or foreign destination");

    if (_hadDestination) {
        if (!_backupURL || ![self isExpectedBundle:_backupURL])
            return JameInstallFail(error, 14, @"Prior version backup is missing or invalid");
        BOOL ok;
        if ([fm fileExistsAtPath:_destinationURL.path]) {
            ok = [fm replaceItemAtURL:_destinationURL withItemAtURL:_backupURL
                      backupItemName:nil
                             options:NSFileManagerItemReplacementUsingNewMetadataOnly
                    resultingItemURL:NULL error:error];
        } else {
            ok = [fm moveItemAtURL:_backupURL toURL:_destinationURL error:error];
        }
        if (!ok) return NO;
    } else if ([fm fileExistsAtPath:_destinationURL.path] &&
               ![fm removeItemAtURL:_destinationURL error:error]) {
        return NO;
    }
    _activated = NO;
    [self unlock];
    return YES;
}

- (BOOL)finalizeWithError:(NSError **)error
{
    if (!_activated)
        return JameInstallFail(error, 15, @"Cannot finalize an inactive replacement");
    if (_backupURL) {
        if (![self isExpectedBundle:_backupURL])
            return JameInstallFail(error, 16, @"Refusing to remove untrusted backup");
        if (![[NSFileManager defaultManager] removeItemAtURL:_backupURL error:error])
            return NO;
    }
    _activated = NO;
    [self unlock];
    return YES;
}

@end
