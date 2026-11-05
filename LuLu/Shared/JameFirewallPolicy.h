// jameLuLu: shared, testable policy helpers. GPL-3.0-or-later.
#ifndef JameFirewallPolicy_h
#define JameFirewallPolicy_h

#import <Foundation/Foundation.h>
#import <NetworkExtension/NetworkExtension.h>

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

NS_INLINE NETrafficDirection JameNetworkRuleDirection(void)
{
    return NETrafficDirectionAny;
}

// Construct the actual catch-all rule used by the macOS content filter.
// Native tests inspect matchDirection and matchProtocol on this exact object.
NS_INLINE NENetworkRule *JameBidirectionalCatchAllRule(void)
{
    return [[NENetworkRule alloc] initWithRemoteNetwork:nil
                                          remotePrefix:0
                                           localNetwork:nil
                                            localPrefix:0
                                               protocol:NENetworkRuleProtocolAny
                                              direction:JameNetworkRuleDirection()];
}

NS_INLINE BOOL JameFlowDirectionIsSupported(NETrafficDirection direction)
{
    return direction == NETrafficDirectionOutbound || direction == NETrafficDirectionInbound;
}

#endif
