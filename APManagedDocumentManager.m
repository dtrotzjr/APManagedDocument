//
//  APManagedDocumentManager.m
//  MultiDocument
//
//  Created by David Trotz on 8/31/13.
//  Copyright (c) 2013 AppPoetry LLC. All rights reserved.
//

#import "APManagedDocumentManager.h"
#import "APManagedDocument.h"

NSString * const APDocumentScanStarted          = @"APDocumentScanStarted";
NSString * const APDocumentScanFinished         = @"APDocumentScanFinished";
NSString * const APDocumentScanCancelled        = @"APDocumentScanCancelled";
NSString * const APNewDocumentFound             = @"APNewDocumentFound";


static APManagedDocumentManager* gInstance;

@interface APManagedDocumentManager () {
    BOOL _randomSeeded;
    NSMutableArray* _documentIdentifiers;
    NSMetadataQuery* _documentQuery;
}

@end

@implementation APManagedDocumentManager

- (id)init {
    self = [super init];
    if (self != nil) {
        NSBundle* mainBundle = [NSBundle mainBundle];
        NSString* transactionLogsSubFolder = [mainBundle objectForInfoDictionaryKey:@"APTransactionLogsSubFolder"];
        if (transactionLogsSubFolder) {
            self.transactionLogsSubFolder = transactionLogsSubFolder;
        } else {
            self.transactionLogsSubFolder = @"CoreDataSupport";
        }
        NSString* documentsSubFolder = [mainBundle objectForInfoDictionaryKey:@"APDocumentsSubFolder"];
        if (documentsSubFolder) {
            self.documentsSubFolder = documentsSubFolder;
        } else {
            self.documentsSubFolder = @"managedDocuments";
        }
        NSString* documentSetIdentifier = [mainBundle objectForInfoDictionaryKey:@"APDocumentSetIdentifier"];
        if (documentSetIdentifier) {
            self.documentSetIdentifier = documentSetIdentifier;
        } else {
            self.documentSetIdentifier = @"APMD_DATA";
        }
        NSString* documentsExtention = [mainBundle objectForInfoDictionaryKey:@"APDocumentsExtention"];
        if (documentSetIdentifier) {
            self.documentsExtention = documentsExtention;
        } else {
            self.documentSetIdentifier = @"";
        }
        [self _prepDocumentsFolder];
    }
    return self;
}

+ (void)initialize {
    if (self == [APManagedDocumentManager class]) {
        gInstance = [[self alloc] init];
    }
}

+ (APManagedDocumentManager*)sharedDocumentManager {
    return gInstance;
}

- (void)_contextInitializedForDocument:(APManagedDocument*)document success:(BOOL)success {
    if ([self.documentDelegate respondsToSelector:@selector(documentInitialized:success:)]) {
        [self.documentDelegate documentInitialized:document success:success];
    }
}

- (void)_prepDocumentsFolder {
    NSURL* documentsURL = self.documentsURL;
    if (documentsURL && self.documentsSubFolder.length > 0) {
        
        if (![[NSFileManager defaultManager] fileExistsAtPath:[documentsURL path] isDirectory:nil]) {
            NSError* error = nil;
            if (![[NSFileManager defaultManager] createDirectoryAtPath:[documentsURL path] withIntermediateDirectories:YES attributes:nil error:&error]) {
                NSLog(@"Failed to create Documents path: %@ - %@", [documentsURL path], [error description]);
            }
        }
    }
}

- (NSURL*)documentsURL {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSURL* documentsURL = [NSURL fileURLWithPath:[paths objectAtIndex:0]];
    if (self.documentsSubFolder.length > 0) {
        documentsURL = [documentsURL URLByAppendingPathComponent:self.documentsSubFolder];
    }
    return documentsURL;
}

- (NSURL*)transactionLogsURL {
    NSURL* transactionLogsURL = [[NSFileManager defaultManager] URLForUbiquityContainerIdentifier:nil];
    if (self.transactionLogsSubFolder.length > 0) {
        transactionLogsURL = [transactionLogsURL URLByAppendingPathComponent:self.transactionLogsSubFolder];
    }
    return transactionLogsURL;
}

- (NSURL*)urlForDocumentWithIdentifier:(NSString*)identifier {
    NSString* fileName = identifier;
    if (self.documentsExtention.length > 0)
        fileName = [NSString stringWithFormat:@"%@.%@", fileName, self.documentsExtention];
    return  [[self documentsURL] URLByAppendingPathComponent:fileName];
}

- (APManagedDocument*)createNewManagedDocumentWithName:(NSString*)documentName {
    NSString* identifier = [NSString stringWithFormat:@"%@_%@_%@", documentName, self.documentSetIdentifier, [self _generateUniqueIdentifier]];
    APManagedDocument* document = [[APManagedDocument alloc] initWithDocumentIdentifier:identifier];
    if (document)
        [self _processDocumentWithIdentifier:identifier];
    return document;
}

- (APManagedDocument*)openExistingManagedDocumentWithIdentifier:(NSString*)identifier {
    return [[APManagedDocument alloc] initWithDocumentIdentifier:identifier];
}

- (NSString *)_generateUniqueIdentifier {
    if(!_randomSeeded)
    {
        srandomdev();
        _randomSeeded = YES;
    }
    return [NSString stringWithFormat:@"%08X_%08X", (int32_t)[[NSDate date] timeIntervalSince1970] * 1000, (int32_t)random()];
}

- (void)setUseiCloud:(BOOL)useiCloud {
    if (_useiCloud != useiCloud) {
        _useiCloud = useiCloud;
        // TODO: Handle moving documents in and out of the cloud...
    }
}

#pragma mark - Document Scan

- (void)startDocumentScan {
    [self stopDocumentScan];
    [[NSNotificationCenter defaultCenter] postNotificationName:APDocumentScanStarted object:self];
    _documentIdentifiers = [[NSMutableArray alloc] init];
    if (self.useiCloud)
        [self _scanForUbiquitousFiles];
    else
        [self _scanForLocalFiles];
}

- (void)stopDocumentScan {
    [_documentQuery stopQuery];
    _documentQuery = nil;
    [[NSNotificationCenter defaultCenter] postNotificationName:APDocumentScanCancelled object:self];
}

- (void)_scanForLocalFiles {
    
    NSArray* contents =
    [[NSFileManager defaultManager] contentsOfDirectoryAtURL:self.documentsURL
                                  includingPropertiesForKeys:nil
                                                     options:0
                                                       error:nil];
    
    for (NSURL* url in contents) {
        NSString* identifier = [self _findIdentifierInPath:[url path]];
        [self _processDocumentWithIdentifier:identifier];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:APDocumentScanFinished object:self];
}

- (void)_scanForUbiquitousFiles {
        _documentQuery = [[NSMetadataQuery alloc] init];
        [_documentQuery setSearchScopes:[NSArray arrayWithObject:NSMetadataQueryUbiquitousDataScope]];
        [_documentQuery setPredicate:[NSPredicate predicateWithFormat:@"%K like %@",
                                        NSMetadataItemFSNameKey,
                                        @"*"]];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_processQuery:) name:NSMetadataQueryDidFinishGatheringNotification object:_documentQuery];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![_documentQuery startQuery]) {
                NSLog(@"NSMetadataQuery failed to start!");
            }
        });
}

- (void)_processDocumentWithIdentifier:(NSString*)identifier {
    if (identifier && ![_documentIdentifiers containsObject:identifier])
    {
        [_documentIdentifiers addObject:identifier];
        NSDictionary* userInfo = [NSDictionary dictionaryWithObject:identifier forKey:@"documentIdentifier"];
        [[NSNotificationCenter defaultCenter] postNotificationName:APNewDocumentFound object:self userInfo:userInfo];
    }
}

- (NSString*)_findIdentifierInPath:(NSString*)path {
    NSString* identifier = nil;
    NSError* error = nil;
    NSString* searchPattern = [NSString stringWithFormat:@"([^/.]+_%@_[A-F0-9]{8}_[A-F0-9]{8})",self.documentSetIdentifier];

    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:searchPattern
                                                                           options:NSRegularExpressionCaseInsensitive
                                                                             error:&error];
    NSRange rangeOfFirstMatch = [regex rangeOfFirstMatchInString:path options:0 range:NSMakeRange(0, [path length])];
    if (!NSEqualRanges(rangeOfFirstMatch, NSMakeRange(NSNotFound, 0))) {
        identifier = [path substringWithRange:rangeOfFirstMatch];
    }
    return identifier;
}

- (void)_processQuery:(NSNotification*)notif {
    [_documentQuery disableUpdates];
    NSArray *results = [_documentQuery results];

    for (NSMetadataItem *item in results) {
        NSURL *itemurl = [item valueForAttribute:NSMetadataItemURLKey];
        NSString* identifier = [self _findIdentifierInPath:[itemurl path]];
        [self _processDocumentWithIdentifier:identifier];
    }

    [_documentQuery enableUpdates];
    [[NSNotificationCenter defaultCenter] postNotificationName:APDocumentScanFinished object:self];
}

- (NSArray*)documentIdentifiers {
    return [NSArray arrayWithArray:_documentIdentifiers];
}
@end
