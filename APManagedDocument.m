//
//  APManagedDocument.m
//  MultiDocument
//
//  Created by David Trotz on 8/30/13.
//  Copyright (c) 2013 AppPoetry LLC. All rights reserved.
//

#import "APManagedDocument.h"
#import "APManagedDocumentManager.h"
#import "APManagedDocumentDelegate.h"
#import <CoreData/CoreData.h>

NSString * const APPersistentStoreCoordinatorStoresWillChangeNotification = @"APPersistentStoreCoordinatorStoresWillChangeNotification";
NSString * const APPersistentStoreCoordinatorStoresDidChangeNotification = @"APPersistentStoreCoordinatorStoresDidChangeNotification";

// The name of the file that contains the store identifier.
static NSString *DocumentMetadataFileName = @"DocumentMetadata.plist";

// The name of the file package subdirectory that contains the Core Data store when local.
static __strong NSString *StoreDirectoryComponentLocal = @"StoreContent";

// The name of the file package subdirectory that contains the Core Data store when in the cloud. The Core Data store itself should not be synced directly, so it is placed in a .nosync directory.
static __strong NSString *StoreDirectoryComponentCloud = @"StoreContent.nosync";

static __strong NSString* gPersistentStoreName = @"persistentStore";

@interface APManagedDocument () {
    
}
@end

@interface APManagedDocumentManager (hidden)
- (void)_contextInitializedForDocument:(APManagedDocument*)document success:(BOOL)success;
@end

@implementation APManagedDocument
// Don't use this initializer with this class as it will result in a thrown
//          exception.
- (id)initWithFileURL:(NSURL *)url {
    @throw [NSException exceptionWithName:@"Invalid initializer called." reason:@"Use APManagedDocument's initWithDocumentName: instead." userInfo:nil];
}

+ (void)initialize {
    NSBundle* mainBundle = [NSBundle mainBundle];
    NSString* tmp = [mainBundle objectForInfoDictionaryKey:@"APManagedDocumentPersistentStoreName"];
    if ([tmp length] > 0) {
        gPersistentStoreName = tmp;
    }
}

- (id)initExistingDocumentHavingIdentifier:(NSString*)identifier completionHandler:(void (^)(BOOL success, APManagedDocument* document))completionHandler {
    APManagedDocumentManager* manager = [APManagedDocumentManager sharedDocumentManager];
    NSURL* permanentURL = [manager localURLForDocumentWithIdentifier:identifier];
    if ([manager iCloudStoreAccessible])
        permanentURL = [manager ubiquitousURLForDocumentWithIdentifier:identifier];
    
    self = [super initWithFileURL:permanentURL];
    if (self != nil) {
        self.persistentStoreOptions = [manager optionsForDocumentWithIdentifier:identifier];
        
        if ([[NSFileManager defaultManager] fileExistsAtPath:[permanentURL path]]) {
            // The document exists already and we just need to open it.
            __unsafe_unretained typeof(self) weakSelf = self;
            [self openWithCompletionHandler:^(BOOL success) {
                if (completionHandler)
                    completionHandler(success, weakSelf);
            }];
        }else {
            @throw [NSException exceptionWithName:@"APManagedDocumentMissing" reason:@"The document with this identifier does not exist!" userInfo:nil];
        }
        _documentIdentifier = identifier;
    }
    return self;
}



- (void)save {
    [self updateChangeCount:UIDocumentChangeDone];
}

+ (NSString*)persistentStoreName {
    return gPersistentStoreName;
}

+ (NSManagedObjectModel*) managedObjectModel {
    NSManagedObjectModel *mom = nil;
    APManagedDocumentManager* manager = [APManagedDocumentManager sharedDocumentManager];
    NSURL *modelURL = [[NSBundle mainBundle] URLForResource:[manager managedObjectModelName] withExtension:@"momd"];
    if (modelURL) {
        mom = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
    }
    return mom;
}

+ (void)moveDocumentAtURL:(NSURL*)sourceDocumentURL withIdentifier:(NSString*)identifier toUbiquityContainer:(NSURL*)ubiquityContainerURL {
    APManagedDocumentManager* manager = [APManagedDocumentManager sharedDocumentManager];
    if (ubiquityContainerURL == nil) {
        
        // iCloud isn't configured.
        NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:
                              NSLocalizedString(@"iCloud does not appear to be configured.", @""), NSLocalizedFailureReasonErrorKey, nil];
        NSError *error = [NSError errorWithDomain:@"Application" code:404 userInfo:dict];
        NSLog(@"%@", [error localizedFailureReason]);
        return;
    }
    
    // Move the document to the cloud using its existing filename
    NSManagedObjectModel *model = [self managedObjectModel];
    NSDictionary *ubiquitousOptions = [manager optionsForDocumentWithIdentifier:identifier];
    
    NSString *documentName = [sourceDocumentURL lastPathComponent];
    NSURL *destinationURL = [ubiquityContainerURL URLByAppendingPathComponent:documentName];
    
    NSError *error = nil;
    
    NSFileManager *fileManager = [[NSFileManager alloc] init];
    [fileManager removeItemAtURL:destinationURL error:nil];
    
    NSURL *destinationStoreDirectoryURL = [destinationURL URLByAppendingPathComponent:StoreDirectoryComponentCloud isDirectory:YES];
    NSURL *destinationStoreURL = [destinationStoreDirectoryURL URLByAppendingPathComponent:[self persistentStoreName] isDirectory:NO];
    
    NSURL *sourceStoreURL = [[sourceDocumentURL URLByAppendingPathComponent:StoreDirectoryComponentLocal isDirectory:YES] URLByAppendingPathComponent:[self persistentStoreName] isDirectory:NO];
    NSURL *metaDataURL = [destinationURL URLByAppendingPathComponent:DocumentMetadataFileName isDirectory:NO];
    
    if([fileManager createDirectoryAtURL:destinationStoreDirectoryURL withIntermediateDirectories:YES attributes:nil error:&error]) {
        NSPersistentStoreCoordinator *pscForSave = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
        id store = [pscForSave addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:sourceStoreURL options:nil error:nil];
        
        id success = [pscForSave migratePersistentStore:store toURL:destinationStoreURL options:ubiquitousOptions withType:NSSQLiteStoreType error:&error];
        
        if (success) {
            NSDictionary* metaData = [NSDictionary dictionaryWithObject:identifier forKey:NSPersistentStoreUbiquitousContentNameKey];
            if([metaData writeToURL:metaDataURL atomically:YES]) {
                [fileManager removeItemAtURL:sourceDocumentURL error:NULL];
            } else {
                NSLog(@"Failed to write store DocumentMetadata.plist.");
            }
        }
        else {
            NSLog(@"Failed to migrate store: %@", error);
        }
    } else {
        NSLog(@"Failed to create path: %@", [error description]);
    }
}
@end
