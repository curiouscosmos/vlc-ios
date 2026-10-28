/*****************************************************************************
 * VLCRadioFavoriteMenu.m
 * VLC for iOS
 *****************************************************************************
 * Copyright (c) 2026 VideoLAN. All rights reserved.
 * $Id$
 *
 * Authors: Felix Paul Kühne <fkuehne # videolan.org>
 *
 * Refer to the COPYING file of the official project for license.
 *****************************************************************************/

#import "VLCRadioFavoriteMenu.h"
#import "VLCFavoriteService.h"
#import "VLCAppCoordinator.h"

@implementation VLCRadioFavoriteMenu

+ (NSArray<UIMenuElement *> *)menuElementsForFavorite:(VLCFavorite *)favorite
                             presentingViewController:(UIViewController *)presenter
                                            didChange:(void (^)(void))didChange
{
    NSMutableArray<UIMenuElement *> *actions = [NSMutableArray array];

    UIAction *removeAction = [UIAction actionWithTitle:NSLocalizedString(@"REMOVE_FAVORITE", nil)
                                                 image:[UIImage systemImageNamed:@"heart.slash"]
                                            identifier:nil
                                               handler:^(__kindof UIAction * _Nonnull action) {
        [[[VLCAppCoordinator sharedInstance] favoriteService] removeFavorite:favorite];
        didChange();
    }];
    removeAction.attributes = UIMenuElementAttributesDestructive;
    [actions addObject:removeAction];

    return actions;
}

+ (UIMenu *)menuForFavorite:(VLCFavorite *)favorite
   presentingViewController:(UIViewController *)presenter
                  didChange:(void (^)(void))didChange
{
    UIDeferredMenuElement *elements =
        [UIDeferredMenuElement elementWithProvider:^(void (^completion)(NSArray<UIMenuElement *> *)) {
        completion([self menuElementsForFavorite:favorite
                        presentingViewController:presenter
                                       didChange:didChange]);
    }];

    return [UIMenu menuWithTitle:@"" children:@[elements]];
}

@end
