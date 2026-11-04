#import <Foundation/Foundation.h>
#import "../Shared/JameFirewallPolicy.h"

static int failures = 0;

#define CHECK(condition, message) do { \
    if (!(condition)) { fprintf(stderr, "FAIL: %s\n", message); failures++; } \
} while (0)

int main(void) {
    @autoreleasepool {
        NSString *app = @"/Applications/Adobe Photoshop.app";
        NSString *folder = @"/opt/Adobe/Tools";
        CHECK([JameRulePathForSelection(app, YES) isEqualToString:@"/Applications/Adobe Photoshop.app/*"],
              "selecting a .app recursively covers all bundled executables");
        CHECK([JameRulePathForSelection(folder, YES) isEqualToString:@"/opt/Adobe/Tools/*"],
              "selecting a folder recursively covers its contents");
        CHECK([JameRulePathForSelection(@"/opt/Adobe/Tools/", YES) isEqualToString:@"/opt/Adobe/Tools/*"],
              "a trailing slash does not create an invalid rule");
        CHECK([JameRulePathForSelection(@"/usr/bin/curl", NO) isEqualToString:@"/usr/bin/curl"],
              "selecting a binary leaves the exact executable path unchanged");

        NSString *rule = @"/Applications/Adobe Photoshop.app/*";
        CHECK(JamePathMatchesDirectoryRule(@"/Applications/Adobe Photoshop.app/Contents/MacOS/Photoshop", rule),
              "directory rule covers the main executable");
        CHECK(JamePathMatchesDirectoryRule(@"/Applications/Adobe Photoshop.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper", rule),
              "directory rule covers nested helpers");
        CHECK(!JamePathMatchesDirectoryRule(@"/Applications/Adobe Photoshop.app.bak/Contents/MacOS/Photoshop", rule),
              "directory boundary prevents neighboring bundle matches");
        CHECK(!JamePathMatchesDirectoryRule(@"/Applications/Adobe Photoshop.app", rule),
              "directory rules target contents, not the directory path itself");
        CHECK(!JamePathMatchesDirectoryRule(
                  @"/Applications/Adobe Photoshop.app/../Unrelated.app/Contents/MacOS/Unrelated", rule),
              "parent-directory traversal must not block an unrelated executable");
        CHECK(!JamePathMatchesDirectoryRule(
                  @"/Applications/Adobe Photoshop.app/Contents/../../Other.app/Contents/MacOS/Other", rule),
              "nested traversal must not escape the selected app bundle");
        CHECK(JamePathMatchesDirectoryRule(@"/usr/bin/curl", @"/*"),
              "intentional root-directory rule covers nested executables");
        // Test with actual filesystem symlinks, not only synthetic string paths.
        NSFileManager *fs = [NSFileManager defaultManager];
        NSString *sandbox = [NSTemporaryDirectory() stringByAppendingPathComponent:
                             [@"jamelulu-path-policy-" stringByAppendingString:[[NSUUID UUID] UUIDString]]];
        NSString *bundle = [sandbox stringByAppendingPathComponent:@"Protected.app"];
        NSString *external = [sandbox stringByAppendingPathComponent:@"External"];
        NSString *bundleContents = [bundle stringByAppendingPathComponent:@"Contents"];
        NSString *unrelatedBinary = [external stringByAppendingPathComponent:@"Unrelated"];
        NSString *bundleRule = [bundle stringByAppendingPathComponent:@"*"];
        CHECK([fs createDirectoryAtPath:bundle withIntermediateDirectories:YES attributes:nil error:NULL],
              "create protected test bundle");
        CHECK([fs createDirectoryAtPath:external withIntermediateDirectories:YES attributes:nil error:NULL],
              "create unrelated test directory");
        CHECK([fs createFileAtPath:unrelatedBinary contents:[NSData data] attributes:nil],
              "create unrelated executable path");
        CHECK([fs createSymbolicLinkAtPath:bundleContents withDestinationPath:external error:NULL],
              "create symlink inside bundle pointing outside");
        CHECK(!JamePathMatchesDirectoryRule(
                  [bundleContents stringByAppendingPathComponent:@"Unrelated"], bundleRule),
              "a symlink escaping a selected bundle must not block unrelated executables");

        NSString *nested = [sandbox stringByAppendingPathComponent:@"Contained.app/Contents/MacOS"];
        NSString *containedBinary = [nested stringByAppendingPathComponent:@"Contained"];
        NSString *alias = [sandbox stringByAppendingPathComponent:@"Alias.app"];
        CHECK([fs createDirectoryAtPath:nested withIntermediateDirectories:YES attributes:nil error:NULL],
              "create contained executable directory");
        CHECK([fs createFileAtPath:containedBinary contents:[NSData data] attributes:nil],
              "create contained executable path");
        CHECK([fs createSymbolicLinkAtPath:alias
                      withDestinationPath:[sandbox stringByAppendingPathComponent:@"Contained.app"] error:NULL],
              "create alternate path to selected bundle");
        CHECK(JamePathMatchesDirectoryRule(
                  [alias stringByAppendingPathComponent:@"Contents/MacOS/Contained"],
                  [[sandbox stringByAppendingPathComponent:@"Contained.app"] stringByAppendingPathComponent:@"*"]),
              "an alias resolving inside the selected bundle must be blocked");
        CHECK([fs removeItemAtPath:sandbox error:NULL], "clean temporary symlink test files");
        CHECK(JameFlowDirectionIsSupported(NETrafficDirectionInbound), "inbound connections are processed");
        CHECK(JameFlowDirectionIsSupported(NETrafficDirectionOutbound), "outbound connections are processed");
        CHECK(!JameFlowDirectionIsSupported((NETrafficDirection)999), "unknown direction stays unsupported");
        CHECK(JameNetworkRuleDirection() == NETrafficDirectionAny, "filter must register for both directions");
    }
    if (failures) fprintf(stderr, "%d firewall policy assertion(s) failed\n", failures);
    else puts("All jameLuLu policy tests passed");
    return failures ? 1 : 0;
}
