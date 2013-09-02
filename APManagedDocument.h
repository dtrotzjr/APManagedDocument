//
//  APManagedDocument.h
//  MultiDocument
//
//  Created by David Trotz on 8/30/13.
//  Copyright (c) 2013 AppPoetry LLC. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "APManagedDocumentDelegate.h"

extern NSString * const APPersistentStoreCoordinatorStoresWillChangeNotification;
extern NSString * const APPersistentStoreCoordinatorStoresDidChangeNotification;

@interface APManagedDocument : UIManagedDocument

// Public: This is a unique identifier for a given document. No two documents
//          can have the same unique identifier.
@property (nonatomic, readonly) NSString* documentIdentifier;

// Public: This is a user readable document name. This does not have to be
//          unique as the identifier above distinguishes one document from
//          from another.
@property (nonatomic, copy) NSString* documentName;

// Don't use this initializer with this class as it will result in a thrown
//          exception. We want to coordinate document locations with the
//          APManagedDocumentManager. Use initWithDocumentName: instead.
- (id)initWithFileURL:(NSURL *)url;


- (id)initWithDocumentIdentifier:(NSString*)identifier;

@end
