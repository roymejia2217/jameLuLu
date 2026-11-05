// Test the *production* Rule.m implementation, including keyed archives and
// JSON import/export. The small utility stubs below replace dependencies that
// are unrelated to protocol persistence, not the Rule implementation itself.
#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <OSLog/OSLog.h>
#import <netinet/in.h>
#import "../Shared/Rule.h"
#import "../Shared/JameRulesSnapshot.h"
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

static Rule *makeRule(id protocol) {
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

static Rule *makeRuleWithAction(id action) {
    NSMutableDictionary *info = [@{
        KEY_PATH: @"/Applications/Scoped.app/*",
        KEY_PROCESS_NAME: @"Scoped",
        KEY_ENDPOINT_ADDR: VALUE_ANY,
        KEY_ENDPOINT_PORT: VALUE_ANY,
        KEY_TYPE: @(RULE_TYPE_USER)
    } mutableCopy];
    if(action != nil) info[KEY_ACTION] = action;
    return [[Rule alloc] init:info];
}

static Rule *reloadRule(Rule *rule) {
    NSError *error = nil;
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:rule
                                        requiringSecureCoding:YES error:&error];
    if(data == nil || error != nil) return nil;
    return [NSKeyedUnarchiver unarchivedObjectOfClass:[Rule class]
                                             fromData:data error:&error];
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

        // A saved rule must not reintroduce an invalid Block/Allow state.
        // Reload the actual production Rule through secure keyed archiving.
        Rule *missingActionArchive = makeRule(@(IPPROTO_TCP));
        missingActionArchive.action = nil;
        CHECK(reloadRule(missingActionArchive) == nil,
              "keyed archive missing action must be rejected");
        Rule *invalidActionArchive = makeRule(@(IPPROTO_TCP));
        invalidActionArchive.action = @2;
        CHECK(reloadRule(invalidActionArchive) == nil,
              "keyed archive with unknown action must be rejected");
        Rule *fractionalActionArchive = makeRule(@(IPPROTO_TCP));
        fractionalActionArchive.action = @0.5;
        CHECK(reloadRule(fractionalActionArchive) == nil,
              "keyed archive with fractional action must not become Block");
        Rule *invalidProtocolArchive = makeRule(@(IPPROTO_TCP));
        invalidProtocolArchive.protocol = @(-1);
        CHECK(reloadRule(invalidProtocolArchive) == nil,
              "keyed archive with negative protocol must be rejected");
        Rule *oversizedProtocolArchive = makeRule(@(IPPROTO_TCP));
        oversizedProtocolArchive.protocol = @256;
        CHECK(reloadRule(oversizedProtocolArchive) == nil,
              "keyed archive with out-of-range protocol must be rejected");

        // The production Rule.init: constructor receives dictionaries from
        // ordinary rule creation and XPC. Reject invalid protocol types/ranges
        // before malformed metadata can reach endpoint matching or persistence.
        CHECK(makeRule(@(IPPROTO_UDP)).protocol.intValue == IPPROTO_UDP,
              "direct constructor accepts valid UDP");
        CHECK(makeRule(@0).protocol.intValue == 0,
              "direct constructor keeps explicit any protocol");
        CHECK(makeRule(@(-1)) == nil,
              "direct constructor rejects negative protocols");
        CHECK(makeRule(@256) == nil,
              "direct constructor rejects protocols beyond uint8 range");
        CHECK(makeRule(@1.5) == nil,
              "direct constructor rejects fractional protocols");
        CHECK(makeRule(@"tcp") == nil,
              "direct constructor rejects protocol name strings");
        CHECK(makeRule(@"6") == nil,
              "direct constructor does not retain a string as NSNumber");
        CHECK(makeRule([NSNull null]) == nil,
              "direct constructor rejects NSNull before integerValue access");

        // The direct creation path must obey the same action contract as
        // imported JSON: invalid values must not masquerade as Block/Allow.
        CHECK(makeRuleWithAction(@"garbage") == nil,
              "direct constructor rejects malformed Block text");
        CHECK(makeRuleWithAction(@(-1)) == nil,
              "direct constructor rejects negative actions");
        CHECK(makeRuleWithAction(@2) == nil,
              "direct constructor rejects unknown numeric actions");
        CHECK(makeRuleWithAction(@0.5) == nil,
              "direct constructor rejects fractional Block values");
        CHECK(makeRuleWithAction(nil) == nil,
              "direct constructor requires an explicit action");
        CHECK(makeRuleWithAction(@(RULE_STATE_BLOCK)) != nil,
              "direct constructor accepts Block action");
        CHECK(makeRuleWithAction(@(RULE_STATE_ALLOW)) != nil,
              "direct constructor accepts Allow action");

        // Reproduces Rules.load's unguarded assignment before valid decoding.
        // The helper below is the exact loader preparation function called by
        // production Rules.load; it must never mutate the current snapshot.
        Rule *activeRule = makeRule(@(IPPROTO_TCP));
        Rule *incomingRule = makeRule(@(IPPROTO_UDP));
        NSMutableDictionary *activeSnapshot = [@{
            @"active": [@{
                KEY_RULES: [NSMutableArray arrayWithObject:activeRule],
                KEY_PATHS: [NSMutableSet setWithObject:activeRule.path]
            } mutableCopy]
        } mutableCopy];
        NSDictionary *incomingSnapshot = @{
            @"incoming": @{
                KEY_RULES: @[incomingRule],
                KEY_PATHS: [NSSet setWithObject:incomingRule.path]
            }
        };
        CHECK(JamePreparedRulesSnapshot(nil) == nil,
              "unarchive failure must never become an empty replacement");
        CHECK(JamePreparedRulesSnapshot(@"invalid-root") == nil,
              "non-dictionary archive cannot replace active rules");
        CHECK(JamePreparedRulesSnapshot(@{@"bad": @"invalid-entry"}) == nil,
              "malformed per-key container must be rejected");
        CHECK(JamePreparedRulesSnapshot(@{@"bad": @{KEY_RULES: @"not-an-array"}}) == nil,
              "malformed rules collection must be rejected");
        CHECK(JamePreparedRulesSnapshot(@{@"bad": @{KEY_RULES: @[@"not-a-rule"]}}) == nil,
              "malformed rule element must be rejected");
        CHECK(JamePreparedRulesSnapshot(@{@"bad": @{KEY_RULES: @[incomingRule],
                                                  KEY_PATHS: @"not-a-set"}}) == nil,
              "malformed paths cannot corrupt a loaded snapshot");
        CHECK(activeSnapshot[@"active"] != nil,
              "invalid candidate must leave original rules available");

        NSMutableDictionary *prepared = JamePreparedRulesSnapshot(incomingSnapshot);
        CHECK(prepared != nil && prepared[@"incoming"] != nil,
              "valid incoming rules are accepted");
        CHECK([prepared isKindOfClass:[NSMutableDictionary class]],
              "top-level loaded rules must be mutable for runtime updates");
        CHECK([prepared[@"incoming"] isKindOfClass:[NSMutableDictionary class]],
              "loaded per-key rule containers must be mutable");
        CHECK([prepared[@"incoming"][KEY_RULES] isKindOfClass:[NSMutableArray class]],
              "loaded rule list must be mutable for add/delete operations");
        CHECK([prepared[@"incoming"][KEY_PATHS] isKindOfClass:[NSMutableSet class]],
              "loaded path set must be mutable for additional executables");
        [prepared[@"incoming"][KEY_RULES] addObject:activeRule];
        CHECK([incomingSnapshot[@"incoming"][KEY_RULES] count] == 1,
              "preparing a candidate must not change decoded immutable archive data");
        CHECK([activeSnapshot[@"active"][KEY_RULES] count] == 1,
              "preparing a candidate must not change the live snapshot");

        Rule *legacyExecutable = makeRule(@(IPPROTO_TCP));
        legacyExecutable.path = @"/Applications/Scoped.app/Contents/MacOS/Scoped";
        NSDictionary *legacySnapshot = @{
            @"legacy": @{KEY_RULES: @[legacyExecutable]}
        };
        NSMutableDictionary *legacyPrepared = JamePreparedRulesSnapshot(legacySnapshot);
        CHECK([legacyPrepared[@"legacy"][KEY_PATHS] isKindOfClass:[NSMutableSet class]],
              "legacy executable rules without paths must gain mutable paths");
        NSDictionary *directorySnapshot = @{
            @"directory": @{KEY_RULES: @[activeRule]}
        };
        CHECK(JamePreparedRulesSnapshot(directorySnapshot)[@"directory"][KEY_PATHS] == nil,
              "directory rules must not receive unrelated executable path sets");

        NSError *snapshotError = nil;
        NSData *encodedSnapshot = [NSKeyedArchiver archivedDataWithRootObject:incomingSnapshot
                                                        requiringSecureCoding:YES
                                                                        error:&snapshotError];
        NSSet *archiveClasses = [NSSet setWithArray:@[
            [NSDictionary class], [NSArray class], [NSString class],
            [NSNumber class], [NSSet class], [Rule class]
        ]];
        id decodedSnapshot = encodedSnapshot == nil ? nil
            : [NSKeyedUnarchiver unarchivedObjectOfClasses:archiveClasses
                                                   fromData:encodedSnapshot error:&snapshotError];
        CHECK(encodedSnapshot != nil && decodedSnapshot != nil && snapshotError == nil,
              "valid production rule snapshot can round-trip through NSSecureCoding");
        CHECK(JamePreparedRulesSnapshot(decodedSnapshot)[@"incoming"] != nil,
              "valid real archive remains eligible for atomic replacement");

        if(exported != nil) {
            NSMutableDictionary *invalid = [exported mutableCopy];
            // Imported action is a security-sensitive policy decision:
            // NSString.integerValue maps garbage to 0 (RULE_STATE_BLOCK).
            // Reject malformed values rather than silently blocking an app.
            NSMutableDictionary *alteredAction = [exported mutableCopy];
            alteredAction[@"action"] = @"not-an-action";
            CHECK([[Rule alloc] initFromJSON:alteredAction] == nil,
                  "unrecognized action text must not become Block");
            alteredAction[@"action"] = @"1extra";
            CHECK([[Rule alloc] initFromJSON:alteredAction] == nil,
                  "numeric prefix plus garbage must not become Allow");
            alteredAction[@"action"] = @(-1);
            CHECK([[Rule alloc] initFromJSON:alteredAction] == nil,
                  "negative action is not a supported verdict");
            alteredAction[@"action"] = @2;
            CHECK([[Rule alloc] initFromJSON:alteredAction] == nil,
                  "unknown numeric action is not supported");
            alteredAction[@"action"] = @0.5;
            CHECK([[Rule alloc] initFromJSON:alteredAction] == nil,
                  "fractional action cannot become Block");
            alteredAction[@"action"] = @"0";
            CHECK([[[Rule alloc] initFromJSON:alteredAction].action isEqual:@(RULE_STATE_BLOCK)],
                  "legacy numeric string zero remains Block");
            alteredAction[@"action"] = @"1";
            CHECK([[[Rule alloc] initFromJSON:alteredAction].action isEqual:@(RULE_STATE_ALLOW)],
                  "legacy numeric string one remains Allow");

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
