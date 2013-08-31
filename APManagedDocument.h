//
//  APManagedDocument.h
//  MultiDocument
//
//  Created by David Trotz on 8/30/13.
//  Copyright (c) 2013 Freelance Mad Science Labs. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface APManagedDocument : UIManagedDocument

// Public: Specifies the subdirectory where documents are stored. This path is
//          relative to the current storage path which is dependent on whther
//          iCloud is available or not. This parameter is optional but providing
//          something here keeps your application's files nice and tidey on the
//          user's device.
@property (nonatomic, copy) NSString* documentsSubFolder;

// Public: This is a unique identifier for a given document. No two documents
//          can have the same unique identifier.
@property (nonatomic, copy) NSString* documentIdentifier;

// Public: This is a user readable document name. This does not have to be
//          unique as the identifier above distinguishes one document from
//          from another.
@property (nonatomic, copy) NSString* documentName;

// Public: Specifies where to store the Transaction Logs within the ubiquitous
//          storage directory. The default for this value is 'TransactionLogs'
@property (nonatomic, copy) NSString*transactionLogsSubFolder;

@end
