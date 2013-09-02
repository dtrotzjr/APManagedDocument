APManagedDocument
=================

APManagedDocument is meant to be a lightweight wrapper for UIManagedDocument created to abstract some of the messiness of creating and opening a UIManagedDocument.


##APManagedDocumentManager:
This singleton is used to create and open any managed documents it manages.

```
[APManagedDocumentManager sharedDocumentManager]
```
###Preparing the manager:
You will need to add the following keys to your Info.plist file if you want to override the defaults:

* **APTransactionLogsSubFolder** This is where core data keeps its transaction logs in the ubiquitous storage area. Defaults to 'CoreDataSupport'.

* **APDocumentsSubFolder** This subdirectory under the sandbox's Documents folder is where we will keep your UIManagedDocuments. Defaults to 'managedDocuments'.

* **APDocumentSetIdentifier** This string is used to decorate a managed document's filename so that all documents created by the document manager are easily identifiable. Defaults to 'APMD_DATA'.

* **APDocumentsExtention** This string is used as the file extention for all managed documents created bt the document manager.

***Note:*** Based on the values provided above a document name will take the form of: 
`[DocumentName]_[DocumentSetIdentifier]_[UUID].[Extention]`
For example in Password Caddy my files look something like:`Passwords_DATA_AF90C0C2_F02DE35B.caddy`

When you look at the transaction logs they will be filed under the full name minus the file extention. So for my previous example they would be something like:

```
<UbiquitousStorePath>/CoreDataSupport/<device_identifier>/Passwords_DATA_AF90C0C2_F02DE35B
```

Once you have the Info.plist flags set you will want to set yourself up as a delegate for the manager and enable iCloud.

```
    [[APManagedDocumentManager sharedDocumentManager] setUseiCloud:YES];
    [[APManagedDocumentManager sharedDocumentManager] setDocumentDelegate:gSharedCaddyManager];
```

This will require you to implement the delegate protocol `documentInitialized:success:` in your delegate object.

Currently the useiCloud flag isn't very useful when it is off and toggling between on and off does nothing at this time.

The document manager automatically starts scanning for documents that it should manage and updates its documentIdentifiers accordingly. If you want to kick off a scan yourself you can call `[[APManagedDocumentManager sharedDocumentManager] startDocumentScan]`. You will probably want to listen for one or more of these notifications. `APDocumentScanStarted` `APDocumentScanFinished` `APDocumentScanCancelled`.


##APManagedDocument

###Creation:
To create a new APManagedDocument you will ask the manager to create one for you like so:

```
APManagedDocument *doc = [[APManagedDocumentManager sharedDocumentManager] createNewManagedDocumentWithName:name];
```
This will create a new document, configure it for iCloud sync and store it in the local sandbox. The manager takes care of creating the identifier and fully decorated file name.


###Opening:
Once the document manager has found a document it will update its `documentIdentifiers` property. You can then take any of these identifiers and open that document like this:

```
NSString* identifier = [[[APManagedDocumentManager sharedDocumentManager] documentIdentifiers] objectAtIndex:0];
APManagedDocument *doc = [[APManagedDocumentManager sharedDocumentManager] openExistingManagedDocumentWithIdentifier:identifier];
```

##APManagedDocumentDelegate

Currently this protcol has only one method

```
- (void)documentInitialized:(APManagedDocument*)document success:(BOOL)success;
```

This will be called whenever a document is opened or saved for creation.

##iOS NDA
Until iOS 7 ships I cannot go into how some of this works or any of the notifications that you will want to observe. 

###To be contniued...