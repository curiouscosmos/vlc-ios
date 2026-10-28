/*****************************************************************************
 * VLCActivityViewControllerVendor.m
 * VLC for iOS
 *****************************************************************************
 * Copyright (c) 2017 VideoLAN. All rights reserved.
 * $Id$
 *
 * Authors: Carola Nitz <nitz.carola # gmail.com>
 *
 * Refer to the COPYING file of the official project for license.
 *****************************************************************************/

#import "VLCActivityViewControllerVendor.h"
#import "VLCOpeninActivity.h"

@implementation VLCActivityViewControllerVendor

+ (UIActivityViewController *)activityViewControllerForFiles:(NSArray *)files
                                            presentingButton:(UIButton *)button
                                    presentingViewController:(UIViewController *)viewController
                                           completionHandler:(void (^)(BOOL))completionHandler
{
    if (![files count]) {
        [viewController vlc_showAlertWithTitle:NSLocalizedString(@"SHARING_ERROR_NO_FILES", nil)
                             message:nil
                         buttonTitle:NSLocalizedString(@"BUTTON_OK", nil)];
        return nil;
    }

    VLCOpenInActivity *openInActivity = [[VLCOpenInActivity alloc] init];
    openInActivity.presentingViewController = viewController;
    openInActivity.presentingButton = button;

    UIActivityViewController *controller = [[UIActivityViewController alloc] initWithActivityItems:files applicationActivities:@[openInActivity]];

    controller.excludedActivityTypes = @[
        UIActivityTypePrint,
        UIActivityTypeAssignToContact,
        UIActivityTypeAddToReadingList,
        UIActivityTypeOpenInIBooks,
        UIActivityTypeMarkupAsPDF,
        UIActivityTypeSaveToCameraRoll
    ];
    controller.completionWithItemsHandler = ^(UIActivityType  _Nullable activityType, BOOL completed, NSArray * _Nullable returnedItems, NSError * _Nullable activityError) {
        APLog(@"UIActivityViewController finished with activity type: %@, completed: %i", activityType, completed);
        completionHandler(completed);
    };
    return controller;
}
@end
