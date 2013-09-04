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

- (id)initWithDocumentIdentifier:(NSString*)identifier {
    APManagedDocumentManager* manager = [APManagedDocumentManager sharedDocumentManager];
    NSURL* documentURL = [manager urlForDocumentWithIdentifier:identifier];
    self = [super initWithFileURL:documentURL];
    if (self != nil) {
        // Since both open and save will use the same completion handlers we
        // create a named block to call on completion
        void (^completionHandler)(BOOL) = ^(BOOL success) {
            if (success) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [manager _contextInitializedForDocument:self success:success];
                });
            } else {
                NSLog(@"APManagedDocument failed to initialize.");
            }
        };
        
        NSMutableDictionary *options = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                        [NSNumber numberWithBool:YES], NSMigratePersistentStoresAutomaticallyOption,
                                        [NSNumber numberWithBool:YES], NSInferMappingModelAutomaticallyOption,
                                        nil];
        if ([manager useiCloud]) {
            [options setObject:identifier forKey:NSPersistentStoreUbiquitousContentNameKey];
            [options setObject:manager.transactionLogsURL forKey:NSPersistentStoreUbiquitousContentURLKey];
        }
        
        self.persistentStoreOptions = options;
        
        if ([[NSFileManager defaultManager] fileExistsAtPath:[documentURL path]]) {
            [self openWithCompletionHandler:completionHandler];
        }else {
            [self saveToURL:documentURL forSaveOperation:UIDocumentSaveForCreating completionHandler:completionHandler];
        }
        _documentIdentifier = identifier;
    }
    return self;
}

- (void)save {
    [self updateChangeCount:UIDocumentChangeDone];
}

@end
