// Test the *production* Rule.m implementation, including keyed archives and
// JSON import/export. The small utility stubs below replace dependencies that
// are unrelated to protocol persistence, not the Rule implementation itself.
#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <OSLog/OSLog.h>
#import <netinet/in.h>
#import "../Shared/Rule.h"
#import "../Shared/utilities.h"

os_log_t logHandle = OS_LOG_DEFAULT;

NSString *getProcessName(pid_t pid, NSString *path) {
    (void)pid;
    return path.lastPathComponent;
}
BOOL isAddressRange(NSString *spec) {
    (void)spec;
    return NO;
}
BOOL parseAddressRange(NSString *spec, int *family, uint8_t *lo,
                       uint8_t *hi, int *length) {
    (void)spec; (void)family; (void)lo; (void)hi; (void)length;
    return NO;
}
BOOL addressInRange(NSString *address, int family, const uint8_t *lo,
                    const uint8_t *hi, int length) {
    (void)address; (void)family; (void)lo; (void)hi; (void)length;
    return NO;
}
NSString *regexFromGlob(NSString *glob) {
    return glob;
}
NSString *toEscapedJSON(NSString *input) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:input
                                                   options:NSJSONWritingFragmentsAllowed
                                                     error:NULL];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

static int failures = 0;
#define CHECK(condition, message) do { \
    if (!(condition)) { fprintf(stderr, "FAIL: %s\n", message); failures++; } \
} while (0)

static Rule *makeRule(NSNumber *protocol) {
    NSMutableDictionary *info = [@{
        KEY_PATH: @"/Applications/Scoped.app/*",
        KEY_PROCESS_NAME: @"Scoped",
        KEY_ENDPOINT_ADDR: VALUE_ANY,
        KEY_ENDPOINT_PORT: VALUE_ANY,
        KEY_TYPE: @(RULE_TYPE_USER),
        KEY_ACTION: @(RULE_STATE_BLOCK)
    } mutableCopy];
    if (protocol != nil) info[KEY_PROTOCOL] = protocol;
    return [[Rule alloc] init:info];
}

static NSDictionary *exportRule(Rule *rule) {
    NSString *json = [NSString stringWithFormat:@"{%@}", [rule toJSON]];
    NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
    id result = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    return [result isKindOfClass:[NSDictionary class]] ? result : nil;
}

int main(void) {
    @autoreleasepool {
        NSError *error = nil;
        Rule *tcp = makeRule(@(IPPROTO_TCP));
        CHECK(tcp.protocol.intValue == IPPROTO_TCP,
              "a freshly created rule retains TCP");
        NSData *archive = [NSKeyedArchiver archivedDataWithRootObject:tcp
                                               requiringSecureCoding:YES
                                                               error:&error];
        CHECK(archive != nil && error == nil,
              "production rule archive must be secure and writable");
        Rule *reloaded = archive == nil ? nil
            : [NSKeyedUnarchiver unarchivedObjectOfClass:[Rule class]
                                                 fromData:archive error:&error];
        CHECK(reloaded != nil && reloaded.protocol.intValue == IPPROTO_TCP,
              "TCP restriction survives NSSecureCoding reload");

        NSDictionary *exported = exportRule(tcp);
        CHECK(exported != nil && [exported[@"protocol"] isEqual:@(IPPROTO_TCP)],
              "JSON export includes an explicit TCP restriction");
        Rule *imported = [[Rule alloc] initFromJSON:exported];
        CHECK(imported != nil && imported.protocol.intValue == IPPROTO_TCP,
              "JSON import preserves an explicit TCP restriction");

        Rule *legacy = makeRule(nil);
        CHECK(legacy.protocol == nil, "legacy protocol remains unspecified");
        NSDictionary *legacyJSON = exportRule(legacy);
        Rule *legacyImported = [[Rule alloc] initFromJSON:legacyJSON];
        CHECK(legacyImported != nil && legacyImported.protocol == nil,
              "legacy JSON without protocol stays unrestricted");
        error = nil;
        NSData *legacyArchive = [NSKeyedArchiver archivedDataWithRootObject:legacy
                                                    requiringSecureCoding:YES
                                                                    error:&error];
        Rule *legacyReloaded = legacyArchive == nil ? nil
            : [NSKeyedUnarchiver unarchivedObjectOfClass:[Rule class]
                                                 fromData:legacyArchive error:&error];
        CHECK(legacyReloaded != nil && legacyReloaded.protocol == nil,
              "legacy keyed rules without protocol remain compatible");

        if(exported != nil) {
            NSMutableDictionary *invalid = [exported mutableCopy];
            invalid[@"protocol"] = @[@"invalid"];
            Rule *invalidImported = [[Rule alloc] initFromJSON:invalid];
            CHECK(invalidImported == nil,
                  "malformed JSON protocol must be rejected");
            invalid[@"protocol"] = @"tcp";
            CHECK([[Rule alloc] initFromJSON:invalid] == nil,
                  "nonnumeric JSON protocol must not become wildcard");
        }
    }
    if(failures) fprintf(stderr, "%d production Rule test(s) failed\n", failures);
    else puts("All production Rule serialization tests passed");
    return failures ? 1 : 0;
}
