//
//  APManagedDocumentManager.m
//  MultiDocument
//
//  Created by David Trotz on 8/31/13.
//  Copyright (c) 2013 AppPoetry LLC. All rights reserved.
//
#import <UIKit/UIKit.h>
#import <CoreData/CoreData.h>
#import "APManagedDocumentManager.h"
#import "APManagedDocument.h"

NSString * const APDocumentScanStarted          = @"APDocumentScanStarted";
NSString * const APDocumentScanFinished         = @"APDocumentScanFinished";
NSString * const APDocumentScanCancelled        = @"APDocumentScanCancelled";
NSString * const APNewDocumentFound             = @"APNewDocumentFound";


static __strong APManagedDocumentManager* gInstance;

@interface APManagedDocumentManager () {
    BOOL _randomSeeded;
    NSMutableArray* _documentIdentifiers;
    NSMetadataQuery* _documentQuery;
    id<NSObject,NSCopying,NSCoding> _currentUbiquityIdentityToken;
    void (^_documentOpenedOverride)(APManagedDocument*,BOOL);
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
        _currentUbiquityIdentityToken = [[NSFileManager defaultManager] ubiquityIdentityToken];
        [[NSNotificationCenter defaultCenter] addObserver: self
                                                 selector: @selector (_iCloudAccountAvailabilityChanged:)
                                                     name: NSUbiquityIdentityDidChangeNotification
                                                   object: nil];
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
    if (_documentOpenedOverride) {
        _documentOpenedOverride(document, success);
        _documentOpenedOverride = nil;
    } else {
        if ([self.documentDelegate respondsToSelector:@selector(documentInitialized:success:)]) {
            [self.documentDelegate documentInitialized:document success:success];
        }
    }
}

- (void)_iCloudAccountAvailabilityChanged:(NSNotification*)notif {
    if (![_currentUbiquityIdentityToken isEqual:[[NSFileManager defaultManager] ubiquityIdentityToken]]) {
        // Update the current token and rescan for documents.
        _currentUbiquityIdentityToken = [[NSFileManager defaultManager] ubiquityIdentityToken];
        [self startDocumentScan];
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

- (BOOL)deleteManagedDocumentWithIdentifier:(NSString*)identifier {
    NSError* err = nil;
    NSURL* documentURL = [self urlForDocumentWithIdentifier:identifier];
    NSDictionary* options = [self optionsForDocumentWithIdentifier:identifier];
    BOOL success = [NSPersistentStoreCoordinator removeUbiquitousContentAndPersistentStoreAtURL:documentURL options:options error:&err];
    if (success) {
        [self startDocumentScan];
    }else {
        NSLog(@"Failed to delete: %@", [err description]);
    }
    return success;
}

- (NSDictionary*)optionsForDocumentWithIdentifier:(NSString*)identifier {
    return [NSDictionary dictionaryWithObjectsAndKeys:
            [NSNumber numberWithBool:YES], NSMigratePersistentStoresAutomaticallyOption,
            [NSNumber numberWithBool:YES], NSInferMappingModelAutomaticallyOption,
            identifier, NSPersistentStoreUbiquitousContentNameKey,
            self.transactionLogsURL, NSPersistentStoreUbiquitousContentURLKey,
            nil];
}

- (NSString *)_generateUniqueIdentifier {
    if(!_randomSeeded)
    {
        srandomdev();
        _randomSeeded = YES;
    }
    return [NSString stringWithFormat:@"%08X_%08X", (int32_t)[[NSDate date] timeIntervalSince1970] * 1000, (int32_t)random()];
}

#pragma mark - Document Scan

- (void)startDocumentScan {
    [[NSNotificationCenter defaultCenter] postNotificationName:APDocumentScanStarted object:self];
    _documentIdentifiers = [[NSMutableArray alloc] init];
    
    if (_currentUbiquityIdentityToken != nil) {
        // We have iCloud access so we will do a metadata query
        [self stopDocumentScan];
        [self _scanForUbiquitousFiles];
    } else {
        // iCloud is currently unavailable (user is signed out or has disabled
        //   iCloud for our app). We need to do an intelligent local file scan.
        [self _scanForLocalFiles];
    }
}

- (void)stopDocumentScan {
    [_documentQuery stopQuery];
    _documentQuery = nil;
    [[NSNotificationCenter defaultCenter] postNotificationName:APDocumentScanCancelled object:self];
}

- (void)_scanForLocalFiles {
    NSFileManager* fileManager = [NSFileManager defaultManager];
    NSArray* contents =
    [fileManager contentsOfDirectoryAtURL:self.documentsURL
                                  includingPropertiesForKeys:nil
                                                     options:0
                                                       error:nil];
    
    for (NSURL* url in contents) {
        NSString* identifier = [self _findIdentifierInPath:[url path]];
        // Determine if this is can be considered a local store
        NSArray *keys = @[NSURLPathKey, NSURLNameKey, NSURLParentDirectoryURLKey];
        NSDirectoryEnumerator *enumerator = [fileManager
                                             enumeratorAtURL:url
                                             includingPropertiesForKeys:keys
                                             options:0
                                             errorHandler:^(NSURL *url, NSError *error) {
                                                 NSLog(@"Local file scan error: %@", [error description]);
                                                 return YES;
                                             }];
        for (NSURL *subURL in enumerator) {
            NSError *error;
            NSString* fileName = nil;
            NSString* urlPathKey = nil;
            if (![subURL getResourceValue:&fileName forKey:NSURLNameKey error:&error]) {
                NSLog(@"Something went wrong. NSURLNameKey seems to be missing. %@", [error description]);
            }
            else if ([fileName isEqualToString:[APManagedDocument persistentStoreName]]) {
                if (![subURL getResourceValue:&urlPathKey forKey:NSURLPathKey error:&error]) {
                    NSLog(@"Something went wrong. NSURLPathKey seems to be missing. %@", [error description]);
                }
                else
                {
                    NSString* searchPattern = [NSString stringWithFormat:@"([^/.]+_%@_[A-F0-9]{8}_[A-F0-9]{8}).*CoreDataUbiquitySupport.*/local/store/%@",self.documentSetIdentifier, [APManagedDocument persistentStoreName]];
                    
                    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:searchPattern
                                                                                           options:NSRegularExpressionCaseInsensitive
                                                                                             error:&error];
                    NSTextCheckingResult* match = [regex firstMatchInString:urlPathKey options:0 range:NSMakeRange(0, [urlPathKey length])];
                    if (match && !NSEqualRanges([match rangeAtIndex:1], NSMakeRange(NSNotFound, 0))) {
                        identifier = [urlPathKey substringWithRange:[match rangeAtIndex:1]];
                        [self _processDocumentWithIdentifier:identifier];
                    }
                }
            }
        }
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:APDocumentScanFinished object:self];
}

- (void)_scanForUbiquitousFiles {
        _documentQuery = [[NSMetadataQuery alloc] init];
        [_documentQuery setSearchScopes:[NSArray arrayWithObject:NSMetadataQueryUbiquitousDataScope]];
        [_documentQuery setPredicate:[NSPredicate predicateWithFormat:@"%K like %@",
                                        NSMetadataItemFSNameKey,
                                        @"*"]];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_queryStarted:) name:NSMetadataQueryDidStartGatheringNotification object:_documentQuery];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_queryUpdated:) name:NSMetadataQueryDidUpdateNotification object:_documentQuery];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_queryGatheringProgress:) name:NSMetadataQueryGatheringProgressNotification object:_documentQuery];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_queryFinished:) name:NSMetadataQueryDidFinishGatheringNotification object:_documentQuery];
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

- (void)_queryStarted:(NSNotification*)notif {
    NSLog(@"Scan started gathering...");
}

- (void)_queryUpdated:(NSNotification*)notif {
    NSLog(@"Scan did update...");
}

- (void)_queryGatheringProgress:(NSNotification*)notif {
    NSLog(@"Scan gathering progress...");
}

- (void)_queryFinished:(NSNotification*)notif {
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
