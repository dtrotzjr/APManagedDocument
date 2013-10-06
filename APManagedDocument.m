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

- (id)initWithDocumentIdentifier:(NSString*)identifier {
    APManagedDocumentManager* manager = [APManagedDocumentManager sharedDocumentManager];
    NSURL* transientLocalURL = [manager localURLForDocumentWithIdentifier:identifier];
    NSURL* permanentURL = transientLocalURL;
    if ([manager iCloudStoreAccessible])
        permanentURL = [manager ubiquitousURLForDocumentWithIdentifier:identifier];
    
    self = [super initWithFileURL:permanentURL];
    if (self != nil) {
        // Since both open and save will use the same completion handlers we
        // create a named block to call on completion
        __unsafe_unretained typeof(self) weakSelf = self;
        void (^completionHandler)(BOOL) = ^(BOOL success) {
            if (success) {
                if ([manager iCloudStoreAccessible]) {
                    // We now need to set the document as Ubiquitous so that the
                    // document's meta data syncs. This requires that we first
                    // close the document.
                    [weakSelf closeWithCompletionHandler:^(BOOL success){
                        if (success) {
                            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
                                NSError* err = nil;
                                // We move it
                                if([[NSFileManager defaultManager] setUbiquitous:YES itemAtURL:transientLocalURL destinationURL:permanentURL error:&err]) {
                                    // And now we can reopen it.
                                    [weakSelf openWithCompletionHandler:^(BOOL success){
                                        if (success)
                                            [manager _contextInitializedForDocument:self success:success];
                                    }];
                                } else {
                                    NSLog(@"Failed to set the document as ubiquitous. %@", [err description]);
                                }
                            });
                        }
                    }];

                } else {
                    // In this case the ubiquitous store is not accessible so we
                    // are done.
                    [manager _contextInitializedForDocument:self success:success];
                }
                

            } else {
                NSLog(@"APManagedDocument failed to initialize.");
            }
        };
        
        self.persistentStoreOptions = [manager optionsForDocumentWithIdentifier:identifier];
        
        if ([[NSFileManager defaultManager] fileExistsAtPath:[permanentURL path]]) {
            // The document exists already and we just need to open it.
            [self openWithCompletionHandler:completionHandler];
        }else {
            // This is a new document so we save it to the local store first and
            // then in the completion handler we will move it to the ubiquitous
            // store if it is accesible.
            [self saveToURL:transientLocalURL forSaveOperation:UIDocumentSaveForCreating completionHandler:completionHandler];
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
@end
