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
        CHECK(JameFlowDirectionIsSupported(NETrafficDirectionInbound), "inbound connections are processed");
        CHECK(JameFlowDirectionIsSupported(NETrafficDirectionOutbound), "outbound connections are processed");
        CHECK(!JameFlowDirectionIsSupported((NETrafficDirection)999), "unknown direction stays unsupported");
        CHECK(JameNetworkRuleDirection() == NETrafficDirectionAny, "filter must register for both directions");
    }
    if (failures) fprintf(stderr, "%d firewall policy assertion(s) failed\n", failures);
    else puts("All jameLuLu policy tests passed");
    return failures ? 1 : 0;
}
