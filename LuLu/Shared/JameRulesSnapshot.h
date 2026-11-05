// jameLuLu: prepare an archived rules snapshot before installing it.
// GPL-3.0-or-later. The loader must leave active rules untouched on failure.
#ifndef JameRulesSnapshot_h
#define JameRulesSnapshot_h

#import <Foundation/Foundation.h>
#import "Rule.h"

// Decode/validate into independent mutable collections. Only Rule objects
// are shared, since this function does not mutate them. A failed decode or
// malformed archive yields nil, never an empty replacement for active rules.
NS_INLINE NSMutableDictionary *JamePreparedRulesSnapshot(id decoded)
{
    if(YES != [decoded isKindOfClass:[NSDictionary class]]) return nil;

    NSDictionary *archive = (NSDictionary *)decoded;
    NSMutableDictionary *prepared = [NSMutableDictionary dictionaryWithCapacity:archive.count];

    for(id key in archive)
    {
        if(YES != [key isKindOfClass:[NSString class]]) return nil;

        id value = archive[key];
        if(YES != [value isKindOfClass:[NSDictionary class]]) return nil;

        NSDictionary *entry = (NSDictionary *)value;
        id rules = entry[KEY_RULES];
        if(YES != [rules isKindOfClass:[NSArray class]]) return nil;
        for(id rule in (NSArray *)rules)
        {
            if(YES != [rule isKindOfClass:[Rule class]]) return nil;
        }

        id paths = entry[KEY_PATHS];
        if(nil != paths && YES != [paths isKindOfClass:[NSSet class]])
            return nil;

        id signingInfo = entry[KEY_CS_INFO];
        if(nil != signingInfo &&
           YES != [signingInfo isKindOfClass:[NSDictionary class]])
            return nil;

        NSMutableDictionary *mutableEntry = [entry mutableCopy];
        mutableEntry[KEY_RULES] = [rules mutableCopy];

        if(nil != paths)
            mutableEntry[KEY_PATHS] = [paths mutableCopy];
        else if(YES != [(NSString *)key isEqualToString:VALUE_ANY] &&
                YES != ((Rule *)[(NSArray *)rules firstObject]).isDirectory.boolValue)
            // Older non-directory archives did not store external paths.
            mutableEntry[KEY_PATHS] = [NSMutableSet set];

        prepared[key] = mutableEntry;
    }

    return prepared;
}

#endif /* JameRulesSnapshot_h */
