#import "SSELibraryEntry.h"

#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <SnoizeMIDI/SnoizeMIDI.h>

#import "SSELibrary.h"


@interface SSELibraryEntry (Private)

- (NSString *)_realPath;

@end


@implementation SSELibraryEntry

+ (SSELibraryEntry *)libraryEntryFromDictionary:(NSDictionary *)dict;
{
    SSELibraryEntry *entry;

    entry = [[[self alloc] init] autorelease];
    [entry takeValuesFromDictionary:dict];

    return entry;
}

- (id)init;
{
    if (![super init])
        return nil;

    return self;
}

- (void)dealloc
{
    [path release];
    
    [super dealloc];
}

- (NSDictionary *)dictionaryValues;
{
    if (path)
        return [NSDictionary dictionaryWithObject:path forKey:@"path"];
    else
        return nil;
}

- (void)takeValuesFromDictionary:(NSDictionary *)dict;
{
    NSString *string;

    string = [dict objectForKey:@"path"];
    if (string)
        [self setPath:string];
}

- (NSString *)path;
{
    return path;
}

- (void)setPath:(NSString *)value;
{
    if (value != path && ![path isEqualToString:value]) {
        [path release];
        path = [value retain];
    }
}

- (NSString *)name;
{
    return [[NSFileManager defaultManager] displayNameAtPath:[self _realPath]];
}

- (NSArray *)messages;
{
    NSString *realPath;
    NSString *extension;
    NSData *data;
    NSArray *messages;

    realPath = [self _realPath];
    extension = [[realPath pathExtension] uppercaseString];
        // TODO we should also be checking file type, probably
    if ([extension isEqualToString:@"MID"] || [extension isEqualToString:@"MIDI"]) {
        messages = [SMSystemExclusiveMessage systemExclusiveMessagesInStandardMIDIFile:realPath];
    } else {
        data = [NSData dataWithContentsOfFile:realPath];
        messages = [SMSystemExclusiveMessage systemExclusiveMessagesInData:data];
    }

    return messages;
}

@end


@implementation SSELibraryEntry (Private)

- (NSString *)_realPath;
{
    // TODO this might be a partial path, or alias, or something
    // return the real path on the real filesystem
    // This is completely wrong as it stands... need to get the file directory for real, not the default

    if ([path isAbsolutePath])
        return path;
    else
        return [[SSELibrary defaultFileDirectory] stringByAppendingPathComponent:path];
}

@end