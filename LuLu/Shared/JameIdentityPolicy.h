// jameLuLu: strictly scoped XPC code-signing requirements. GPL-3.0-or-later.
#ifndef JameIdentityPolicy_h
#define JameIdentityPolicy_h

#import <Foundation/Foundation.h>

// A developer Team ID is exactly 10 uppercase ASCII letters/digits.
NS_INLINE BOOL JameValidTeamIdentifier(NSString *teamID)
{
    if (teamID.length != 10) return NO;
    NSCharacterSet *invalid = [[NSCharacterSet characterSetWithCharactersInString:
                                @"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"] invertedSet];
    return [teamID rangeOfCharacterFromSet:invalid].location == NSNotFound;
}

// No unsigned/unknown Team ID fallback: a missing identity rejects XPC clients.
NS_INLINE NSString *JameXPCSigningRequirement(NSString *bundleID, NSString *teamID, BOOL minimumVersion)
{
    if (!JameValidTeamIdentifier(teamID) || bundleID.length == 0) return nil;
    NSCharacterSet *invalid = [[NSCharacterSet characterSetWithCharactersInString:
                                @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-"] invertedSet];
    if ([bundleID rangeOfCharacterFromSet:invalid].location != NSNotFound) return nil;
    NSString *requirement = [NSString stringWithFormat:
        @"anchor apple generic and identifier \"%@\" and certificate leaf[subject.OU] = \"%@\"",
        bundleID, teamID];
    if (minimumVersion)
        requirement = [requirement stringByAppendingString:
            @" and info [CFBundleShortVersionString] >= \"0.1.0\""];
    return requirement;
}

#endif
