//
//  APManagedDocumentDelegate.h
//  PassCaddy
//
//  Created by David Trotz on 9/1/13.
//  Copyright (c) 2013 David Trotz. All rights reserved.
//

#import <Foundation/Foundation.h>
@class APManagedDocument;

@protocol APManagedDocumentDelegate <NSObject>
- (void)documentInitialized:(APManagedDocument*)document success:(BOOL)success;
@end
