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
NSString * const APDocumentDeleted              = @"APDocumentDeleted";


static __strong APManagedDocumentManager* gInstance;

@interface APManagedDocumentManager () {
    BOOL _randomSeeded;
    NSMutableArray* _documentIdentifiers;
    NSMetadataQuery* _documentQuery;
    id<NSObject,NSCopying,NSCoding> _currentUbiquityIdentityToken;
    BOOL _orphanedLocalFileScanDone;
    BOOL _ubiquitousSubpathPathValidated;
    // The ubiquitous scan takes time to pick up newly migrated files
    // so we will note migrated files here and expect to see them on a
    // file scan.
    NSMutableArray* _documentIdentifiersRequiredForFinishedScan;
    BOOL _documentScanDelayed;
}

@end

@implementation APManagedDocumentManager

- (id)init {
    self = [super init];
    if (self != nil) {
        NSBundle* mainBundle = [NSBundle mainBundle];
        NSString* transactionLogsSubFolder = [mainBundle objectForInfoDictionaryKey:@"APTransactionLogsSubFolder"];
        if (transactionLogsSubFolder) {
            _transactionLogsSubFolder = transactionLogsSubFolder;
        } else {
            _transactionLogsSubFolder = @"CoreDataSupport";
        }
        NSString* documentsSubFolder = [mainBundle objectForInfoDictionaryKey:@"APDocumentsSubFolder"];
        if (documentsSubFolder) {
            _documentsSubFolder = documentsSubFolder;
        } else {
            _documentsSubFolder = @"managedDocuments";
        }
        NSString* documentSetIdentifier = [mainBundle objectForInfoDictionaryKey:@"APDocumentSetIdentifier"];
        if (documentSetIdentifier) {
            _documentSetIdentifier = documentSetIdentifier;
        } else {
            _documentSetIdentifier = @"APMD_DATA";
        }
        NSString* documentsExtention = [mainBundle objectForInfoDictionaryKey:@"APDocumentsExtention"];
        if (documentSetIdentifier) {
            _documentsExtention = documentsExtention;
        } else {
            _documentSetIdentifier = @"";
        }
        NSString* managedObjectModelName = [mainBundle objectForInfoDictionaryKey:@"APManagedObjectModelName"];
        if (managedObjectModelName) {
            _managedObjectModelName = managedObjectModelName;
        } else {
            _managedObjectModelName = @"Model";
        }
        _currentUbiquityIdentityToken = [[NSFileManager defaultManager] ubiquityIdentityToken];
        [[NSNotificationCenter defaultCenter] addObserver: self
                                                 selector: @selector (_iCloudAccountAvailabilityChanged:)
                                                     name: NSUbiquityIdentityDidChangeNotification
                                                   object: nil];
        _documentIdentifiersRequiredForFinishedScan = [NSMutableArray new];
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
    NSURL* documentsURL = self.localDocumentsURL;
    if (_currentUbiquityIdentityToken)
        documentsURL = self.ubiquitousDocumentsURL;
    if (documentsURL && self.documentsSubFolder.length > 0) {
        
        if (![[NSFileManager defaultManager] fileExistsAtPath:[documentsURL path] isDirectory:nil]) {
            NSError* error = nil;
            if (![[NSFileManager defaultManager] createDirectoryAtPath:[documentsURL path] withIntermediateDirectories:YES attributes:nil error:&error]) {
                NSLog(@"Failed to create Documents path: %@ - %@", [documentsURL path], [error description]);
            }
        }
    }
}

- (NSURL*)localDocumentsURL {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSURL* localDocumentsURL = [NSURL fileURLWithPath:[paths objectAtIndex:0]];
    if (self.documentsSubFolder.length > 0) {
        localDocumentsURL = [localDocumentsURL URLByAppendingPathComponent:self.documentsSubFolder];
    }
    return localDocumentsURL;
}

- (NSURL*)ubiquitousDocumentsURL {
    NSURL* ubiquitousDocumentsURL = [[NSFileManager defaultManager] URLForUbiquityContainerIdentifier:nil];
    if (self.documentsSubFolder.length > 0) {
        ubiquitousDocumentsURL = [[ubiquitousDocumentsURL URLByAppendingPathComponent:@"Documents"] URLByAppendingPathComponent:self.documentsSubFolder];
    }
    return ubiquitousDocumentsURL;
}

- (NSURL*)localURLForDocumentWithIdentifier:(NSString*)identifier {
    NSString* fileName = identifier;
    if (self.documentsExtention.length > 0)
        fileName = [NSString stringWithFormat:@"%@.%@", fileName, self.documentsExtention];
    return  [[self localDocumentsURL] URLByAppendingPathComponent:fileName];
}

- (NSURL*)ubiquitousURLForDocumentWithIdentifier:(NSString*)identifier {
    NSString* fileName = identifier;
    if (self.documentsExtention.length > 0)
        fileName = [NSString stringWithFormat:@"%@.%@", fileName, self.documentsExtention];
    NSURL* ubiquitousURL = [self ubiquitousDocumentsURL];
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

- (void)createNewDocumentWithName:(NSString*)documentName completionHandler:(void (^)(BOOL success, NSString* identifier))completionHandler {
    NSString* identifier = [NSString stringWithFormat:@"%@_%@_%@", documentName, self.documentSetIdentifier, [self _generateUniqueIdentifier]];
    NSURL* transientURL = [self localURLForDocumentWithIdentifier:identifier];
    NSURL* permanentURL = transientURL;
    if ([self iCloudStoreAccessible])
        permanentURL = [self ubiquitousURLForDocumentWithIdentifier:identifier];
    
    UIManagedDocument* newDoc = [[UIManagedDocument alloc] initWithFileURL:permanentURL];
    if (newDoc != nil) {
        // Since both open and save will use the same completion handlers we
        // create a named block to call on completion
        void (^midCompletionHandler)(BOOL) = ^(BOOL success) {
            if (success) {
                if ([self iCloudStoreAccessible]) {
                    // We now need to set the document as Ubiquitous so that the
                    // document's meta data syncs. This requires that we first
                    // close the document.
                    [newDoc closeWithCompletionHandler:^(BOOL success){
                        if (success) {
                            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
                                NSError* err = nil;
                                // We move it
                                if([[NSFileManager new] setUbiquitous:YES itemAtURL:transientURL destinationURL:permanentURL error:&err]) {
                                    if (completionHandler)
                                        completionHandler(YES, identifier);
                                    
                                } else {
                                    @throw [NSException exceptionWithName:@"APManagedDocumentFailedUbiquitous" reason:@"The document failed to move to the ubiquitous store!" userInfo:nil];
                                }
                            });
                        }
                    }];
                } else {
                    // This is a local file so we don't need to move it over
                    // we just need to call the completion handler
                    if (completionHandler) {
                        completionHandler(success, identifier);
                    }
                }
            } else {
                @throw [NSException exceptionWithName:@"APManagedDocumentFailedInitialize" reason:@"The document failed to initialize!" userInfo:nil];
            }
        };
        
        if (![[NSFileManager defaultManager] fileExistsAtPath:[permanentURL path]]) {
            if ([self iCloudStoreAccessible]) {
                // Clear out the options we will set them again in the completion
                // handler after we set the document ubiquitous otherwise the
                // .nosync folder will not migrate over.
                newDoc.persistentStoreOptions = nil;
                
            }else {
                newDoc.persistentStoreOptions = [self optionsForDocumentWithIdentifier:identifier];
            }
            [newDoc saveToURL:transientURL forSaveOperation:UIDocumentSaveForCreating completionHandler:midCompletionHandler];
        }else {
            @throw [NSException exceptionWithName:@"APManagedDocumentExistsAlready" reason:@"The document with this identifier already exists!" userInfo:nil];
        }
    }
}

- (APManagedDocument*)openExistingManagedDocumentWithIdentifier:(NSString*)identifier {
    APManagedDocument* doc = [[APManagedDocument alloc] initExistingDocumentHavingIdentifier:identifier
                                                                           completionHandler:
                              ^(BOOL success, APManagedDocument* document){
                                  [self _contextInitializedForDocument:document success:success];
                              }];
    return doc;
}

- (void)deleteManagedDocumentWithIdentifier:(NSString*)identifier {
    BOOL success = NO;
    NSError* err = nil;
    __unsafe_unretained typeof(self) weakSelf = self;
    NSURL* documentURL = nil;
    if (_currentUbiquityIdentityToken) {
        // Deleting ubiquitous content is a bit trickier...
        // First we open the document so that we can obtain the document's
        // store URL. Once we have the store URL we close the document
        // and perform the removeUbiquitousContentAndPersistentStoreAtURL method
        // to remove the ubiquitous content. Next we move the document package
        // from the iCloud store. Finally we remove the local document package.
        documentURL = [self ubiquitousURLForDocumentWithIdentifier:identifier];
        if ([_documentIdentifiers containsObject:identifier]) {
            (void)[[APManagedDocument alloc] initExistingDocumentHavingIdentifier:identifier completionHandler:^(BOOL success, APManagedDocument* document){
                if (success) {
                    NSDictionary* options = document.persistentStoreOptions;
                    NSPersistentStore* store = [document.managedObjectContext.persistentStoreCoordinator.persistentStores firstObject];
                    [document closeWithCompletionHandler:^(BOOL success) {
                        if(success) {
                            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
                                NSError* err = nil;
                                if ([NSPersistentStoreCoordinator removeUbiquitousContentAndPersistentStoreAtURL:store.URL options:options error:&err])
                                {
                                    if([[NSFileManager defaultManager] fileExistsAtPath:[documentURL path]]) {
                                        // We need to move it from the Ubiquitous
                                        // location so that iCloud does not restore
                                        // the file for us.
                                        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
                                        NSURL* destinationURL = [[NSURL fileURLWithPath:[paths objectAtIndex:0]] URLByAppendingPathComponent:identifier];
                                        if([[NSFileManager defaultManager] setUbiquitous:NO itemAtURL:documentURL  destinationURL:destinationURL error:&err])
                                        {
                                            // Now we can remove the item safely
                                            BOOL success = [[NSFileManager defaultManager] removeItemAtURL:destinationURL error:&err];
                                            [weakSelf _handleDeleteResultForIdentifier:identifier success:success error:err];
                                        } else {
                                            NSLog(@"Failed to delete: %@", [err description]);
                                        }
                                    }
                                } else {
                                    NSLog(@"FAILED: Remove Ubiquitous Content And Persistent Store: %@", [err description]);
                                }
                            });
                        }
                    }];
                }
            }];
        }
    } else {
        documentURL = [self localURLForDocumentWithIdentifier:identifier];
        if([[NSFileManager defaultManager] fileExistsAtPath:[documentURL path]]) {
            // iCloud is not enabled right now so we simply remove the document.
            documentURL = [self localURLForDocumentWithIdentifier:identifier];
            success = [[NSFileManager defaultManager] removeItemAtURL:documentURL error:&err];
            [weakSelf _handleDeleteResultForIdentifier:identifier success:success error:err];
        }
    }
}

- (void)_handleDeleteResultForIdentifier:(NSString*)identifier success:(BOOL)success error:err {
    if (success) {
        [[NSNotificationCenter defaultCenter] postNotificationName:APDocumentDeleted object:self userInfo:@{@"APDocumentIdentifier":identifier}];
        [self startDocumentScan];
    } else {
        NSLog(@"Failed to delete: %@", [err description]);
    }
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
    [fileManager contentsOfDirectoryAtURL:self.localDocumentsURL
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
        [fileManager contentsOfDirectoryAtURL:self.localDocumentsURL
                   includingPropertiesForKeys:nil
                                      options:0
                                        error:nil];
        
        for (NSURL* url in contents) {
            // Determine if this is can be considered a local store
            NSString* identifier = [self _identifierIfURLIsForValidLocalStorePath:url];
            if (identifier){
                NSLog(@"Migrating document: %@", identifier);
                [_documentIdentifiersRequiredForFinishedScan addObject:identifier];
                [APManagedDocument moveDocumentAtURL:url withIdentifier:identifier toUbiquityContainer:[self ubiquitousDocumentsURL]];
            }
        }
    }
}

- (void)_scanForUbiquitousFiles {
        NSLog(@"Requesting scan for ubiquitous items...");
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
     NSTextCheckingResult* match = [regex firstMatchInString:path options:0 range:NSMakeRange(0, [path length])];
     if (match && !NSEqualRanges([match rangeAtIndex:1], NSMakeRange(NSNotFound, 0))) {
         identifier = [path substringWithRange:[match rangeAtIndex:1]];
     }
    return identifier;
}

- (void)_queryStarted:(NSNotification*)notif {
    NSLog(@"Scan started gathering...");
}

- (void)_queryUpdated:(NSNotification*)notif {
    NSLog(@"Scan did update...");
    [self _processCurrentQueryResults];
    if (_documentScanDelayed && _documentIdentifiersRequiredForFinishedScan.count == 0) {
        [[NSNotificationCenter defaultCenter] postNotificationName:APDocumentScanFinished object:self];
        _documentScanDelayed = NO;
    }
}

- (void)_queryGatheringProgress:(NSNotification*)notif {
    NSLog(@"Scan gathering progress...");
}

- (void)_queryFinished:(NSNotification*)notif {
    NSLog(@"Scan did finish...");
    [self _processCurrentQueryResults];
    // If we are not waiting on any
    if (_documentIdentifiersRequiredForFinishedScan.count == 0) {
        [[NSNotificationCenter defaultCenter] postNotificationName:APDocumentScanFinished object:self];
    } else {
        // We are expecting more updates from the meta data query so we will
        // flag that here and post the APDocumentScanFinished after we have
        // actually seen all the documents we are expecting to be posted.
        _documentScanDelayed = YES;
    }
}

- (void)_processCurrentQueryResults {
    [_documentQuery disableUpdates];
    NSArray *results = [_documentQuery results];
    NSLog(@"Found %d Items", results.count);
    for (NSMetadataItem *item in results) {
        NSLog(@"Processing item %@", [item description]);
        NSURL *itemurl = [item valueForAttribute:NSMetadataItemURLKey];
        NSString* identifier = [self _findIdentifierInPath:[itemurl path]];
        [self _processDocumentWithIdentifier:identifier];
        [_documentIdentifiersRequiredForFinishedScan removeObject:identifier];
    }
    
    [_documentQuery enableUpdates];
    
}

- (NSArray*)documentIdentifiers {
    return [NSArray arrayWithArray:_documentIdentifiers];
}
@end
