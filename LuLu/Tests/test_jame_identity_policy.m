#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import "../Shared/JameIdentityPolicy.h"

static int failures = 0;
#define CHECK(condition, name) do { if (!(condition)) { fprintf(stderr, "FAIL: %s\n", name); failures++; } } while (0)

int main(void) {
    @autoreleasepool {
        NSString *bundle = @"io.github.roymejia2217.jamelulu.app";
        NSString *team = @"ABC123XYZ9";
        NSString *req = JameXPCSigningRequirement(bundle, team, YES);
        CHECK([req containsString:@"anchor apple generic"], "Apple signing anchor required");
        CHECK([req containsString:@"identifier \"io.github.roymejia2217.jamelulu.app\""],
              "exact fork app identifier required");
        CHECK([req containsString:@"certificate leaf[subject.OU] = \"ABC123XYZ9\""],
              "XPC client must share the extension developer team");
        CHECK([req containsString:@"CFBundleShortVersionString"], "minimum version check retained");
        // Verify these are actual Apple code-signing requirements, not only
        // well-formed-looking strings. The listener passes them to Security.framework.
        SecRequirementRef parsed = NULL;
        OSStatus requirementStatus = SecRequirementCreateWithString(
            (__bridge CFStringRef)req, kSecCSDefaultFlags, &parsed);
        CHECK(requirementStatus == errSecSuccess && parsed != NULL,
              "strict XPC requirement must parse in Apple's Security framework");
        if (parsed) CFRelease(parsed);

        NSString *legacyRequirement = JameXPCSigningRequirement(bundle, team, NO);
        parsed = NULL;
        requirementStatus = SecRequirementCreateWithString(
            (__bridge CFStringRef)legacyRequirement, kSecCSDefaultFlags, &parsed);
        CHECK(requirementStatus == errSecSuccess && parsed != NULL,
              "legacy XPC requirement must parse in Apple's Security framework");
        if (parsed) CFRelease(parsed);
        CHECK(JameXPCSigningRequirement(bundle, team, NO) != nil, "legacy macOS validation supported");
        CHECK(![JameXPCSigningRequirement(bundle, team, NO) containsString:@"CFBundleShortVersionString"],
              "legacy requirement need not include version");
        CHECK(JameXPCSigningRequirement(bundle, nil, YES) == nil, "missing team fails closed");
        CHECK(JameXPCSigningRequirement(bundle, @"short", YES) == nil, "invalid team fails closed");
        CHECK(JameXPCSigningRequirement(bundle, @"ABC123xyz9", YES) == nil, "team uses uppercase ID");
        CHECK(JameXPCSigningRequirement(@"evil\" or true", team, YES) == nil,
              "bundle identifier cannot inject a signing expression");
        CHECK(JameXPCSigningRequirement(@"", team, YES) == nil, "missing bundle ID fails closed");
        // Installation paths must not be replaced just because their names match.
        CHECK(JameIsOwnedBundle(bundle, @"/Applications/jameLuLu.app",
                                bundle, @"jameLuLu.app"),
              "a valid existing fork bundle is eligible for replacement");
        CHECK(!JameIsOwnedBundle(@"com.objective-see.lulu.app",
                                 @"/Applications/jameLuLu.app", bundle, @"jameLuLu.app"),
              "do not overwrite the original LuLu under a misleading file name");
        CHECK(!JameIsOwnedBundle(bundle, @"/Applications/Other.app", bundle, @"jameLuLu.app"),
              "do not overwrite another application with a misleading bundle ID");
        CHECK(!JameIsOwnedBundle(nil, @"/Applications/jameLuLu.app", bundle, @"jameLuLu.app"),
              "an unreadable existing bundle must fail closed");
        CHECK(!JameIsOwnedBundle(bundle, @"/Applications/jameLuLu.app.backup",
                                 bundle, @"jameLuLu.app"),
              "app name match must respect full component boundary");
        // Uninstall cleanup has no authority over the shared Application Support
        // parent directory or the original Objective-See LuLu state.
        CHECK(JameMayDeleteOwnState(@"/Library/Application Support/jameLuLu"),
              "uninstall may delete only its own data directory");
        CHECK(!JameMayDeleteOwnState(@"/Library/Application Support"),
              "uninstall must preserve the shared Application Support directory");
        CHECK(!JameMayDeleteOwnState(@"/Library/Objective-See/LuLu"),
              "uninstall must preserve upstream LuLu state");
        CHECK(!JameMayDeleteOwnState(@"/Library/Application Support/jameLuLu/.."),
              "parent traversal cannot widen the authorized deletion path");
        CHECK(!JameMayDeleteOwnState(nil), "unknown uninstall path fails closed");
        // Re-running install/upgrade from the already installed app must
        // not deactivate the filter then attempt to copy the bundle over itself.
        CHECK(JameBundleLocationsEqual(@"/Applications/jameLuLu.app",
                                       @"/Applications/jameLuLu.app"),
              "same installation source and destination is a no-op");
        CHECK(JameBundleLocationsEqual(@"/Applications/../Applications/jameLuLu.app",
                                       @"/Applications/jameLuLu.app"),
              "normalized aliases to the same installed bundle are a no-op");
        CHECK(!JameBundleLocationsEqual(@"/Users/Shared/jameLuLu.app",
                                        @"/Applications/jameLuLu.app"),
              "different source bundle must proceed with ordinary installation");
        CHECK(!JameBundleLocationsEqual(nil, @"/Applications/jameLuLu.app"),
              "unknown source must not be treated as installed");
        // Process lifecycle must never terminate Objective-See's original LuLu
        // or another app with a matching process name or misleading path.
        CHECK(JameMayTerminateOwnedPeer(bundle, @"/Applications/jameLuLu.app", 420, 17,
                                        bundle, @"jameLuLu.app"),
              "another jameLuLu instance may be stopped");
        CHECK(!JameMayTerminateOwnedPeer(bundle, @"/Applications/jameLuLu.app", 17, 17,
                                         bundle, @"jameLuLu.app"),
              "never stop the current process");
        CHECK(!JameMayTerminateOwnedPeer(@"com.objective-see.lulu.app",
                                         @"/Applications/LuLu.app", 420, 17,
                                         bundle, @"jameLuLu.app"),
              "upstream LuLu may never be terminated");
        CHECK(!JameMayTerminateOwnedPeer(@"com.objective-see.lulu.app",
                                         @"/Applications/jameLuLu.app", 420, 17,
                                         bundle, @"jameLuLu.app"),
              "file name alone does not authorize termination");
        CHECK(!JameMayTerminateOwnedPeer(bundle, @"/Applications/LuLu.app", 420, 17,
                                         bundle, @"jameLuLu.app"),
              "fork app identifier alone does not authorize a different bundle");
        CHECK(!JameMayTerminateOwnedPeer(bundle, @"/Applications/jameLuLu.app", 0, 17,
                                         bundle, @"jameLuLu.app"),
              "reject PID zero");
        CHECK(!JameMayTerminateOwnedPeer(nil, @"/Applications/jameLuLu.app", 420, 17,
                                         bundle, @"jameLuLu.app"),
              "unknown identity must not be terminated");
        CHECK(!JameMayTerminateOwnedPeer(bundle, nil, 420, 17,
                                         bundle, @"jameLuLu.app"),
              "unknown bundle path must not be terminated");
    }
    if (failures) fprintf(stderr, "%d identity test(s) failed\n", failures);
    else puts("All jameLuLu identity tests passed");
    return failures ? 1 : 0;
}
