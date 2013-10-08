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
@end
