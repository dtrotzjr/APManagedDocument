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
    BOOL _orphanedLocalFileScanDone;
    BOOL _ubiquitousSubpathPathValidated;
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

- (BOOL)iCloudStoreAccessible {
    return _currentUbiquityIdentityToken != nil;
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

- (NSURL*)ubiquitousURL {
    NSURL* ubiquitousURL = [[NSFileManager defaultManager] URLForUbiquityContainerIdentifier:nil];
    if (self.documentsSubFolder.length > 0) {
        ubiquitousURL = [ubiquitousURL URLByAppendingPathComponent:self.documentsSubFolder];
    }
    return ubiquitousURL;
}

- (NSURL*)localURLForDocumentWithIdentifier:(NSString*)identifier {
    NSString* fileName = identifier;
    if (self.documentsExtention.length > 0)
        fileName = [NSString stringWithFormat:@"%@.%@", fileName, self.documentsExtention];
    return  [[self documentsURL] URLByAppendingPathComponent:fileName];
}

- (NSURL*)ubiquitousURLForDocumentWithIdentifier:(NSString*)identifier {
    NSString* fileName = identifier;
    if (self.documentsExtention.length > 0)
        fileName = [NSString stringWithFormat:@"%@.%@", fileName, self.documentsExtention];
    NSURL* ubiquitousURL = [self ubiquitousURL];
    if (ubiquitousURL == nil)
        @throw [NSException exceptionWithName:@"Invalid ubiquity URL" reason:@"iCloud not available. Cannot obtain the ubiquitous URL." userInfo:nil];
    
    // Ensure the subpath exists so we can put documents there.
    if (!_ubiquitousSubpathPathValidated && ![[NSFileManager defaultManager] fileExistsAtPath:[ubiquitousURL path] isDirectory:NULL]) {
        NSError* err = nil;
        if(![[NSFileManager defaultManager] createDirectoryAtURL:ubiquitousURL withIntermediateDirectories:YES attributes:nil error:&err]) {
            NSLog(@"Unable to create subpath in the ubiquitous store. %@", [err description]);
        }
    }
    _ubiquitousSubpathPathValidated = YES;
    
    return  [ubiquitousURL URLByAppendingPathComponent:fileName];
}

- (APManagedDocument*)createNewManagedDocumentWithName:(NSString*)documentName {
    NSString* identifier = [NSString stringWithFormat:@"%@_%@_%@", documentName, self.documentSetIdentifier, [self _generateUniqueIdentifier]];
    APManagedDocument* document = [[APManagedDocument alloc] initWithDocumentIdentifier:identifier];
    if (document)
        [self _processDocumentWithIdentifier:identifier];
    return document;
}

- (APManagedDocument*)openExistingManagedDocumentWithIdentifier:(NSString*)identifier {
    APManagedDocument* doc = nil;
    if ([_documentIdentifiers containsObject:identifier]) {
        doc = [[APManagedDocument alloc] initWithDocumentIdentifier:identifier];
    }
    return doc;
}

- (BOOL)deleteManagedDocumentWithIdentifier:(NSString*)identifier {
    BOOL success = NO;
    NSError* err = nil;
    __unsafe_unretained typeof(self) weakSelf = self;
    NSURL* documentURL = nil;
    if (_currentUbiquityIdentityToken) {
        // Deleting ubiquitous content is a bit trickier...
        // First we open the document so that we can obtain the document's
        // store URL. Once we have the store URL we close the document
        // and perform the removeUbiquitousContentAndPersistentStoreAtURL method
        // to remove the ubiquitous content.
        // Finally we remove the local document package.
        documentURL = [self ubiquitousURLForDocumentWithIdentifier:identifier];
        _documentOpenedOverride = ^(APManagedDocument* doc, BOOL success) {
            if (success) {
                NSDictionary* options = doc.persistentStoreOptions;
                NSPersistentStore* store = [doc.managedObjectContext.persistentStoreCoordinator.persistentStores firstObject];
                [doc closeWithCompletionHandler:^(BOOL success) {
                    if(success) {
                        NSError* err = nil;
                        if ([NSPersistentStoreCoordinator removeUbiquitousContentAndPersistentStoreAtURL:store.URL options:options error:&err])
                        {
                            if([[NSFileManager defaultManager] fileExistsAtPath:[documentURL path]]) {
                                success = [[NSFileManager defaultManager] removeItemAtURL:documentURL error:&err];
                                if (success) {
                                    [weakSelf startDocumentScan];
                                }else {
                                    NSLog(@"Failed to delete: %@", [err description]);
                                }
                            }
                        } else {
                            NSLog(@"FAILED: Remove Ubiquitous Content And Persistent Store: %@", [err description]);
                        }
                    }
                }];
            }
        };
        // Kicking off here an open will eventually land in the _documentOpenedOverride above
        [self openExistingManagedDocumentWithIdentifier:identifier];
    } else if([[NSFileManager defaultManager] fileExistsAtPath:[documentURL path]]) {
        // iCloud is not enabled right now so we simply remove the document.
        documentURL = [self localURLForDocumentWithIdentifier:identifier];
        success = [[NSFileManager defaultManager] removeItemAtURL:documentURL error:&err];
        if (success) {
            [self startDocumentScan];
        }else {
            NSLog(@"Failed to delete: %@", [err description]);
        }
    }

    return success;
}

- (void)prepareForMigrationToNewiCloudAccount {
    for (NSString* identifier in _documentIdentifiers) {
        APManagedDocument* doc = [self openExistingManagedDocumentWithIdentifier:identifier];
        doc.persistentStoreOptions = @{ NSPersistentStoreRemoveUbiquitousMetadataOption : [NSNumber numberWithBool:1] };
        [doc closeWithCompletionHandler:^(BOOL success) {}];
    }
}

- (NSDictionary*)optionsForDocumentWithIdentifier:(NSString*)identifier {
    NSDictionary* options = @{
                             NSMigratePersistentStoresAutomaticallyOption   :[NSNumber numberWithBool:YES],
                             NSInferMappingModelAutomaticallyOption         :[NSNumber numberWithBool:YES]
                             };
    
    if (_currentUbiquityIdentityToken != nil) {
        options = @{
                 NSMigratePersistentStoresAutomaticallyOption   :[NSNumber numberWithBool:YES],
                 NSInferMappingModelAutomaticallyOption         :[NSNumber numberWithBool:YES],
                 NSPersistentStoreUbiquitousContentNameKey      :identifier,
                 NSPersistentStoreUbiquitousContentURLKey       :self.transactionLogsSubFolder
                 };
    }
    return  options;
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
        if (!_orphanedLocalFileScanDone)
            [self _migrateOrphanedLocalFiles];
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
        // Determine if this is can be considered a local store
        NSString* identifier = [self _identifierIfURLIsForValidLocalStorePath:url];
        if (identifier)
            [self _processDocumentWithIdentifier:identifier];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:APDocumentScanFinished object:self];
}

- (NSString*)_identifierIfURLIsForValidLocalStorePath:(NSURL*)url {
    NSString* identifier = nil;
    NSFileManager* fileManager = [NSFileManager defaultManager];
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
                NSString* searchPattern = [NSString stringWithFormat:@"([^/.]+_%@_[A-F0-9]{8}_[A-F0-9]{8})%@/StoreContent/%@",
                                           self.documentSetIdentifier,
                                           self.documentsExtention ?
                                                [NSString stringWithFormat:@"\\.%@", self.documentsExtention] :
                                                @"",
                                           [APManagedDocument persistentStoreName]];
                
                NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:searchPattern
                                                                                       options:NSRegularExpressionCaseInsensitive
                                                                                         error:&error];
                NSTextCheckingResult* match = [regex firstMatchInString:urlPathKey options:0 range:NSMakeRange(0, [urlPathKey length])];
                if (match && !NSEqualRanges([match rangeAtIndex:1], NSMakeRange(NSNotFound, 0))) {
                    identifier = [urlPathKey substringWithRange:[match rangeAtIndex:1]];
                    break;
                }
            }
        }
    }
    return identifier;
}

- (void) _migrateOrphanedLocalFiles {
    if ([[NSFileManager defaultManager] ubiquityIdentityToken]) {
        NSFileManager* fileManager = [NSFileManager defaultManager];
        NSArray* contents =
        [fileManager contentsOfDirectoryAtURL:self.documentsURL
                   includingPropertiesForKeys:nil
                                      options:0
                                        error:nil];
        
        __block int orphanedFilesOpened = 0;
        __unsafe_unretained typeof(self) weakSelf = self;
        for (NSURL* url in contents) {
            // Determine if this is can be considered a local store
            NSString* identifier = [self _identifierIfURLIsForValidLocalStorePath:url];
            if (identifier){
                // Opening and then closing the document is enough to get it moved over to the
                // iCloud space.
                _documentOpenedOverride = ^(APManagedDocument* doc, BOOL success) {
                    [doc closeWithCompletionHandler:^(BOOL success){
                        if (!success)
                            NSLog(@"Something went wrong. The document failed to close");
                        orphanedFilesOpened--;
                        if (orphanedFilesOpened == 0) {
                            weakSelf->_orphanedLocalFileScanDone = YES;
                            // Now that all the orphaned files have been
                            // migrated to use iCloud sync we can kick off a
                            // fresh document scan and find these files using a
                            // meta data scan
                            [weakSelf startDocumentScan];
                        }
                    }];
                };
                orphanedFilesOpened++;
                NSLog(@"Migrating document: %@", identifier);
                [self openExistingManagedDocumentWithIdentifier:identifier];
            }
        }
    }
}

- (void)_scanForUbiquitousFiles {
        _documentQuery = [[NSMetadataQuery alloc] init];
        [_documentQuery setSearchScopes:[NSArray arrayWithObject:NSMetadataQueryUbiquitousDocumentsScope]];
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
        NSLog(@"Processing Document: %@", identifier);
        [_documentIdentifiers addObject:identifier];
        NSDictionary* userInfo = [NSDictionary dictionaryWithObject:identifier forKey:@"documentIdentifier"];
        [[NSNotificationCenter defaultCenter] postNotificationName:APNewDocumentFound object:self userInfo:userInfo];
    }
}

- (NSString*)_findIdentifierInPath:(NSString*)path {
    NSString* identifier = nil;
    NSError* error = nil;
    NSString* searchPattern = [NSString stringWithFormat:@"%@/(.+_%@_[A-F0-9]{8}_[A-F0-9]{8})",self.documentsSubFolder, self.documentSetIdentifier];

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
