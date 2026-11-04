#import <Foundation/Foundation.h>
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
        CHECK(JameXPCSigningRequirement(bundle, team, NO) != nil, "legacy macOS validation supported");
        CHECK(![JameXPCSigningRequirement(bundle, team, NO) containsString:@"CFBundleShortVersionString"],
              "legacy requirement need not include version");
        CHECK(JameXPCSigningRequirement(bundle, nil, YES) == nil, "missing team fails closed");
        CHECK(JameXPCSigningRequirement(bundle, @"short", YES) == nil, "invalid team fails closed");
        CHECK(JameXPCSigningRequirement(bundle, @"ABC123xyz9", YES) == nil, "team uses uppercase ID");
        CHECK(JameXPCSigningRequirement(@"evil\" or true", team, YES) == nil,
              "bundle identifier cannot inject a signing expression");
        CHECK(JameXPCSigningRequirement(@"", team, YES) == nil, "missing bundle ID fails closed");
    }
    if (failures) fprintf(stderr, "%d identity test(s) failed\n", failures);
    else puts("All jameLuLu identity tests passed");
    return failures ? 1 : 0;
}
