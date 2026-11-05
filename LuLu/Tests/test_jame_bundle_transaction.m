// Real filesystem acceptance tests for jameLuLu bundle staging/replacement.
// These tests do not activate a Network Extension or assert code signing.
#import <Foundation/Foundation.h>
#import "../App/JameBundleTransaction.h"

static int failures = 0;
#define CHECK(c, name) do { if (!(c)) { fprintf(stderr, "FAIL: %s\n", name); failures++; } } while (0)

static NSURL *MakeBundle(NSURL *parent, NSString *name, NSString *identifier, NSString *payload)
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSURL *bundle = [parent URLByAppendingPathComponent:name isDirectory:YES];
    NSURL *contents = [bundle URLByAppendingPathComponent:@"Contents" isDirectory:YES];
    if (![fm createDirectoryAtURL:contents withIntermediateDirectories:YES attributes:nil error:NULL])
        return nil;
    NSDictionary *info = @{@"CFBundleIdentifier": identifier,
                           @"CFBundleExecutable": @"fixture"};
    if (![info writeToURL:[contents URLByAppendingPathComponent:@"Info.plist"] atomically:YES])
        return nil;
    if (![payload writeToURL:[bundle URLByAppendingPathComponent:@"payload.txt"]
                   atomically:YES encoding:NSUTF8StringEncoding error:NULL])
        return nil;
    return bundle;
}

static NSString *Payload(NSURL *bundle)
{
    return [NSString stringWithContentsOfURL:[bundle URLByAppendingPathComponent:@"payload.txt"]
                                   encoding:NSUTF8StringEncoding error:NULL];
}

static NSURL *TestRoot(void)
{
    NSURL *root = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]
                   URLByAppendingPathComponent:[@"jamelulu-transaction-" stringByAppendingString:
                                                 [[NSUUID UUID] UUIDString]] isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:root
                            withIntermediateDirectories:YES attributes:nil error:NULL];
    return root;
}

int main(void)
{
    @autoreleasepool {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *bundleID = @"io.github.roymejia2217.jamelulu.app";

        // Staging must leave the installed old version untouched. Replacement
        // must retain a real backup; rollback must put that old version back.
        {
            NSURL *root = TestRoot();
            NSURL *source = MakeBundle(root, @"download.app", bundleID, @"new");
            NSURL *destination = MakeBundle(root, @"jameLuLu.app", bundleID, @"old");
            JameBundleTransaction *tx =
                [[JameBundleTransaction alloc] initWithSourceURL:source
                                                  destinationURL:destination
                                                expectedBundleID:bundleID];
            NSError *error = nil;
            CHECK([tx prepareWithError:&error], "prepare a valid upgrade");
            CHECK([Payload(destination) isEqualToString:@"old"],
                  "preparation does not remove or change installed version");
            CHECK([tx activateWithError:&error], "replace with a staged bundle");
            CHECK([Payload(destination) isEqualToString:@"new"],
                  "new bundle is present after activation");
            CHECK(tx.backupURL != nil && [Payload(tx.backupURL) isEqualToString:@"old"],
                  "previous installed version remains recoverable");
            CHECK([tx rollbackWithError:&error], "rollback restores old bundle");
            CHECK([Payload(destination) isEqualToString:@"old"], "rollback preserves previous payload");
            [fm removeItemAtURL:root error:NULL];
        }

        // Failure during preparation must never remove the installed version.
        {
            NSURL *root = TestRoot();
            NSURL *source = [root URLByAppendingPathComponent:@"missing.app"];
            NSURL *destination = MakeBundle(root, @"jameLuLu.app", bundleID, @"old");
            JameBundleTransaction *tx =
                [[JameBundleTransaction alloc] initWithSourceURL:source
                                                  destinationURL:destination
                                                expectedBundleID:bundleID];
            CHECK(![tx prepareWithError:NULL], "missing source fails preflight");
            CHECK([Payload(destination) isEqualToString:@"old"],
                  "preflight failure preserves original bundle");
            [fm removeItemAtURL:root error:NULL];
        }

        // A foreign app is never overwritten even if placed at our destination.
        {
            NSURL *root = TestRoot();
            NSURL *source = MakeBundle(root, @"download.app", bundleID, @"new");
            NSURL *destination = MakeBundle(root, @"jameLuLu.app", @"com.vendor.other", @"other");
            JameBundleTransaction *tx =
                [[JameBundleTransaction alloc] initWithSourceURL:source
                                                  destinationURL:destination
                                                expectedBundleID:bundleID];
            CHECK(![tx prepareWithError:NULL], "foreign destination rejects upgrade");
            CHECK([Payload(destination) isEqualToString:@"other"],
                  "foreign bundle remains untouched");
            [fm removeItemAtURL:root error:NULL];
        }

        // A destination swapped after preparation must not be overwritten.
        {
            NSURL *root = TestRoot();
            NSURL *source = MakeBundle(root, @"download.app", bundleID, @"new");
            NSURL *destination = MakeBundle(root, @"jameLuLu.app", bundleID, @"old");
            JameBundleTransaction *tx =
                [[JameBundleTransaction alloc] initWithSourceURL:source
                                                  destinationURL:destination
                                                expectedBundleID:bundleID];
            CHECK([tx prepareWithError:NULL], "prepare before destination swap");
            CHECK([fm removeItemAtURL:destination error:NULL], "remove old test fixture");
            CHECK(MakeBundle(root, @"jameLuLu.app", @"com.vendor.other", @"other") != nil,
                  "install foreign test fixture in its place");
            CHECK(![tx activateWithError:NULL], "refuse foreign destination after preparation");
            CHECK([Payload(destination) isEqualToString:@"other"],
                  "do not overwrite changed ownership");
            [tx discardStaging];
            [fm removeItemAtURL:root error:NULL];
        }

        // First-time install must be reversible if launch later fails.
        {
            NSURL *root = TestRoot();
            NSURL *source = MakeBundle(root, @"download.app", bundleID, @"new");
            NSURL *destination = [root URLByAppendingPathComponent:@"jameLuLu.app"];
            JameBundleTransaction *tx =
                [[JameBundleTransaction alloc] initWithSourceURL:source
                                                  destinationURL:destination
                                                expectedBundleID:bundleID];
            CHECK([tx prepareWithError:NULL], "prepare fresh install");
            CHECK(![fm fileExistsAtPath:destination.path], "prepare is non-destructive");
            CHECK([tx activateWithError:NULL], "commit fresh install");
            CHECK([Payload(destination) isEqualToString:@"new"], "fresh install payload");
            CHECK(tx.backupURL == nil, "no phantom backup on fresh install");
            CHECK([tx rollbackWithError:NULL], "rollback removes failed fresh install");
            CHECK(![fm fileExistsAtPath:destination.path], "failed fresh install rolled back");
            [fm removeItemAtURL:root error:NULL];
        }

        // Successful launch may leave a backup until the caller explicitly
        // confirms application health; cleanup must be deliberate.
        {
            NSURL *root = TestRoot();
            NSURL *source = MakeBundle(root, @"download.app", bundleID, @"new");
            NSURL *destination = MakeBundle(root, @"jameLuLu.app", bundleID, @"old");
            JameBundleTransaction *tx =
                [[JameBundleTransaction alloc] initWithSourceURL:source
                                                  destinationURL:destination
                                                expectedBundleID:bundleID];
            CHECK([tx prepareWithError:NULL], "prepare backup-retaining upgrade");
            CHECK([tx activateWithError:NULL], "activate backup-retaining upgrade");
            CHECK([tx finalizeWithError:NULL], "explicitly finalize after verification");
            CHECK([Payload(destination) isEqualToString:@"new"], "finalization preserves new app");
            CHECK(![fm fileExistsAtPath:tx.backupURL.path], "finalization removes owned backup");
            [fm removeItemAtURL:root error:NULL];
        }
    }
    if (failures) fprintf(stderr, "%d bundle transaction assertions failed\n", failures);
    else puts("All jameLuLu bundle transaction tests passed");
    return failures ? 1 : 0;
}
