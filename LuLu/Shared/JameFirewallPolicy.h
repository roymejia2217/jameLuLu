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
    // Standardize before prefix matching: a path with /../ must not escape the selected directory.
    NSString *normalizedPath = [processPath stringByStandardizingPath];
    NSString *directory = [[rulePath substringToIndex:rulePath.length - 1] stringByStandardizingPath];
    NSString *prefix = [directory isEqualToString:@"/"] ? @"/" : [directory stringByAppendingString:@"/"];
    if ([normalizedPath hasPrefix:prefix]) return YES;
    NSString *resolvedPath = [[normalizedPath stringByResolvingSymlinksInPath] stringByStandardizingPath];
    return [resolvedPath hasPrefix:prefix];
}

NS_INLINE NETrafficDirection JameNetworkRuleDirection(void)
{
    return NETrafficDirectionAny;
}

NS_INLINE BOOL JameFlowDirectionIsSupported(NETrafficDirection direction)
{
    return direction == NETrafficDirectionOutbound || direction == NETrafficDirectionInbound;
}

#endif
