//
//  HRPGCustomizationCollectionViewController.h
//  Habitica
//
//  Created by Phillip Thelen on 09/05/15.
//  Copyright © 2017 HabitRPG Inc. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "HRPGBaseCollectionViewController.h"
#import "User.h"

@interface HRPGCustomizationCollectionViewController
    : HRPGBaseCollectionViewController<NSFetchedResultsControllerDelegate>

@property(nonatomic, weak) User *user;
@property(nonatomic, strong) NSString *userKey;
@property(nonatomic, strong) NSString *type;
@property(nonatomic, strong) NSString *group;
@property(nonatomic, strong) NSString *entityName;
@property BOOL allowUnset;

@end
