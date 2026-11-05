// jameLuLu: shared, testable policy helpers. GPL-3.0-or-later.
#ifndef JameFirewallPolicy_h
#define JameFirewallPolicy_h

#import <Foundation/Foundation.h>
#import <NetworkExtension/NetworkExtension.h>
#import <Network/Network.h>
#import <mach/mach.h>
#import <netinet/in.h>
#import <sys/socket.h>
#import "consts.h"

// Apple's sourceApp/sourceProcess audit tokens are nullable NSData values.
// Never cast bytes to audit_token_t unless the kernel token is complete.
NS_INLINE BOOL JameHasValidAuditToken(NSData *token)
{
    return token.length == sizeof(audit_token_t);
}

// Bundle folders (.app) are directories too: a single rule covers all helpers.
NS_INLINE NSString *JameRulePathForSelection(NSString *path, BOOL isDirectory)
{
    if (!isDirectory || path.length == 0) return path;
    NSString *resolved = [[path stringByStandardizingPath] stringByResolvingSymlinksInPath];
    return [resolved stringByAppendingPathComponent:@"*"];
}

// The trailing slash is intentional: /Adobe/* must not match /Adobe.old/foo.
NS_INLINE BOOL JamePathMatchesDirectoryRule(NSString *processPath, NSString *rulePath)
{
    if (!processPath.length || ![rulePath hasPrefix:@"/"] || ![rulePath hasSuffix:@"/*"]) return NO;
    // Match filesystem identity, not a lexical alias. A link inside a
    // protected .app may point outside it; a link outside may point into it.
    // Canonicalize both sides to preserve the directory boundary in either case.
    NSString *resolvedPath = [[[processPath stringByStandardizingPath]
                                stringByResolvingSymlinksInPath] stringByStandardizingPath];
    NSString *directory = [[[[rulePath substringToIndex:rulePath.length - 1]
                              stringByStandardizingPath] stringByResolvingSymlinksInPath]
                            stringByStandardizingPath];
    NSString *prefix = [directory isEqualToString:@"/"] ? @"/" : [directory stringByAppendingString:@"/"];
    return [resolvedPath hasPrefix:prefix];
}

// Only an explicit, enabled, all-endpoint, all-port, all-protocol
// directory Block rule is allowed to preempt regular LuLu rule precedence.
// Protocol-specific rules must continue through ordinary flow matching.
NS_INLINE BOOL JameIsUnconditionalDirectoryBlockForPath(
    NSString *processPath,
    NSString *rulePath,
    NSNumber *action,
    BOOL disabled,
    NSString *endpointAddr,
    NSString *endpointPort,
    NSNumber *protocol)
{
    if(nil == action || action.integerValue != RULE_STATE_BLOCK || disabled)
        return NO;
    if(YES != [endpointAddr isEqualToString:VALUE_ANY] ||
       YES != [endpointPort isEqualToString:VALUE_ANY])
        return NO;
    // nil means unspecified (all protocols). Zero is IPPROTO_IP/any.
    if(nil != protocol && 0 != protocol.integerValue)
        return NO;
    return JamePathMatchesDirectoryRule(processPath, rulePath);
}

// A rule without an explicit protocol is compatible with all legacy flows.
// For SOCK_STREAM/SOCK_DGRAM sockets created using protocol 0, the kernel
// supplies the default transport; do not lose TCP/UDP matches in this case.
NS_INLINE BOOL JameRuleProtocolMatchesSocket(NSNumber *ruleProtocol,
                                             int socketProtocol,
                                             int socketType)
{
    if(nil == ruleProtocol || IPPROTO_IP == ruleProtocol.integerValue) return YES;

    // Invalid protocol metadata cannot be interpreted as a wildcard.
    if(ruleProtocol.integerValue < 0 || ruleProtocol.integerValue > UINT8_MAX)
        return NO;

    int actual = socketProtocol;
    if(IPPROTO_IP == actual)
    {
        if(SOCK_STREAM == socketType) actual = IPPROTO_TCP;
        else if(SOCK_DGRAM == socketType) actual = IPPROTO_UDP;
    }

    return ruleProtocol.intValue == actual;
}

NS_INLINE NETrafficDirection JameNetworkRuleDirection(void)
{
    return NETrafficDirectionAny;
}

// Construct the actual catch-all rule used by the macOS content filter.
// Native tests inspect matchDirection and matchProtocol on this exact object.
NS_INLINE NENetworkRule *JameBidirectionalCatchAllRule(void)
{
    if (@available(macOS 15.0, *))
    {
        return [[NENetworkRule alloc] initWithRemoteNetworkEndpoint:nil
                                                       remotePrefix:0
                                               localNetworkEndpoint:nil
                                                        localPrefix:0
                                                           protocol:NENetworkRuleProtocolAny
                                                          direction:JameNetworkRuleDirection()];
    }

    // The modern endpoint initializer is unavailable before macOS 15.
    // The legacy initializer remains necessary on supported older macOS.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NENetworkRule *rule = [[NENetworkRule alloc] initWithRemoteNetwork:nil
                                                         remotePrefix:0
                                                          localNetwork:nil
                                                           localPrefix:0
                                                              protocol:NENetworkRuleProtocolAny
                                                             direction:JameNetworkRuleDirection()];
#pragma clang diagnostic pop
    return rule;
}

// A nil-remote/nil-local catch-all excludes loopback per NetworkExtension.
// Register IPv4 and IPv6 loopback explicitly in BOTH directions.
NS_INLINE NENetworkRule *JameBidirectionalLoopbackRule(BOOL ipv6)
{
    NSUInteger prefix = ipv6 ? 128 : 8;

    if (@available(macOS 15.0, *))
    {
        nw_endpoint_t remote = nw_endpoint_create_host(ipv6 ? "::1" : "127.0.0.0", "0");
        return [[NENetworkRule alloc] initWithRemoteNetworkEndpoint:remote
                                                       remotePrefix:prefix
                                               localNetworkEndpoint:nil
                                                        localPrefix:0
                                                           protocol:NENetworkRuleProtocolAny
                                                          direction:JameNetworkRuleDirection()];
    }

    // Preserve support for macOS before 15 without silencing warnings globally.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NWHostEndpoint *remote = [NWHostEndpoint endpointWithHostname:(ipv6 ? @"::1" : @"127.0.0.0")
                                                               port:@"0"];
    NENetworkRule *rule = [[NENetworkRule alloc] initWithRemoteNetwork:remote
                                                         remotePrefix:prefix
                                                          localNetwork:nil
                                                           localPrefix:0
                                                              protocol:NENetworkRuleProtocolAny
                                                             direction:JameNetworkRuleDirection()];
#pragma clang diagnostic pop
    return rule;
}

NS_INLINE BOOL JameFlowDirectionIsSupported(NETrafficDirection direction)
{
    return direction == NETrafficDirectionOutbound || direction == NETrafficDirectionInbound;
}

#endif
