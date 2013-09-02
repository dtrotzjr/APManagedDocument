//
//  APManagedDocumentManager.h
//  MultiDocument
//
//  Created by David Trotz on 8/31/13.
//  Copyright (c) 2013 AppPoetry LLC. All rights reserved.
//

// See: http://www.axelpeju.com/blog/2012/01/31/core-data-and-icloud/
//      http://oleb.net/blog/2011/11/ios5-tech-talk-michael-jurewitz-on-icloud-storage/
//      http://www.freelancemadscience.com/fmslabs_blog/2011/12/19/syncing-multiple-core-data-documents-using-icloud.html

#import <Foundation/Foundation.h>
#import "APManagedDocumentDelegate.h"

// Posted whenever a document scan is initiated. Interested clients should
//          prepare for recieve APNewDocumentFound calls.
//          userInfo is nil.
extern NSString * const APDocumentScanStarted;

// Posted whenever a document scan is finished.
//          userInfo is nil.
extern NSString * const APDocumentScanFinished;

// Posted whenever a document scan was stopped prematurely.
extern NSString * const APDocumentScanCancelled;

// Posted whenever a new documenthas been found.
//          userInfo dictionary contains an NSString object indicating the
//          identifier of the newly found document.
extern NSString * const APNewDocumentFound;

@class APManagedDocument;

@interface APManagedDocumentManager : NSObject

// Public: Specifies the subdirectory where documents are stored. This path is
//          relative to the current storage path which is dependent on whther
//          iCloud is available or not. This parameter is optional but providing
//          something here keeps your application's files nice and tidey on the
//          user's device.
@property (nonatomic, copy) NSString* documentsSubFolder;

// Public: Specifies where to store the Transaction Logs within the ubiquitous
//          storage directory. The default for this value is 'TransactionLogs'
@property (nonatomic, copy) NSString*transactionLogsSubFolder; // NSPersistentStoreUbiquitousContentURLKey 'CoreDataSupport'

// Public: Specifies the URL for where the managed documents are expected to
//          reside.
@property (nonatomic, readonly) NSURL* documentsURL;

// Public: Specifies the location that iCloud should use for transaction logs.
- (NSURL*)transactionLogsURL;

// Public: Generates a URL that indicates where the document is to be stored
//          based on the current state of the document manager
- (NSURL*)urlForDocumentWithIdentifier:(NSString*)identifier;

// Public: Specifies an identifier used to identify a document as part of the
//          user's set of documents. Defaults to "APMD_DATA".
@property (nonatomic, copy) NSString* documentSetIdentifier;

// Public: Optional parameter to indicate what the document manager should use
//          for a file extention for the managed documents it creates and
//          manages. Defaults to an empty string
@property (nonatomic, copy) NSString* documentsExtention;

// Public: If set the manager will move any local stores to the ubiquitous store
//          under the documentsSubFolder and any future documents are stored
//          there as well. If this is unset then any documents in the ubiquitous
//          store are moved to the local Documents sandbox under the
//          documentsSubFolder.
//  Throws an exception if this is enabled but iCloud is unavailable.
@property (nonatomic, assign) BOOL useiCloud;

// Public: A singleton object that is shared accross the application
+ (APManagedDocumentManager*)sharedDocumentManager;

// Public: Creates a new managed document and manages it in regards to iCloud
//          storage.
- (APManagedDocument*)createNewManagedDocumentWithName:(NSString*)documentName;

// Public: Opens an existing managed document and manages it in regards to
//          iCloud storage.
- (APManagedDocument*)openExistingManagedDocumentWithIdentifier:(NSString*)identifier;

// Public: Kicks off a scan to find documents that this manager should track
//          and manage.
- (void)startDocumentScan;

// Public: Stops any document scans currently in progress.
- (void)stopDocumentScan;

// Public: After a document scan this array will be filled with the identiers of
//          the documents that it found.
- (NSArray*)documentIdentifiers;

@property (nonatomic, weak) id<APManagedDocumentDelegate>documentDelegate;

@end
