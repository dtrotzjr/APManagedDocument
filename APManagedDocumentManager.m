//
//  APManagedDocumentManager.m
//  MultiDocument
//
//  Created by David Trotz on 8/31/13.
//  Copyright (c) 2013 AppPoetry LLC. All rights reserved.
//

#import "APManagedDocumentManager.h"
#import "APManagedDocument.h"

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
            self.transactionLogsSubFolder = @"transactionLogs";
        }
        NSString* documentsSubFolder = [mainBundle objectForInfoDictionaryKey:@"APDocumentsSubFolder"];
        if (documentsSubFolder) {
            self.documentsSubFolder = documentsSubFolder;
        } else {
            self.documentsSubFolder = @"managedDocuments";
        }
        NSString* documentSetIdentifier = [mainBundle objectForInfoDictionaryKey:@"APDocumentSetIdentifier"];
        if (documentSetIdentifier) {
            self.documentSetIdentifier = documentsSubFolder;
        } else {
            self.documentSetIdentifier = @"APMD_DATA";
        }
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
        
    }
}

#pragma mark - Document Scan

- (void)startDocumentScan {
    _documentIdentifiers = [[NSMutableArray alloc] init];
    if (self.useiCloud)
        [self _scanForUbiquitousFiles];
    else
        [self _scanForLocalFiles];
}

- (void)stopDocumentScan {
    
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
    if (identifier)
        [_documentIdentifiers addObject:identifier];
}

- (NSString*)_findIdentifierInPath:(NSString*)path {
    NSString* identifier = nil;
    NSError* error = nil;
    NSString* searchPattern = [NSString stringWithFormat:@"([^/.]+_%@_[A-F0-9]{8}_[A-F0-9]{8})",self.documentSetIdentifier];
    if (self.documentsExtention.length > 0)
        searchPattern = [NSString stringWithFormat:@"%@\\.(%@)", searchPattern, self.documentsExtention];
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
}
@end
