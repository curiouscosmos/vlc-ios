/*****************************************************************************
 * VLCEmptyLibraryView.m
 * VLC for iOS
 *****************************************************************************
 * Copyright (c) 2018-2026 VideoLAN. All rights reserved.
 * $Id$
 *
 * Authors: Mike JS. Choi <mkchoi212 # icloud.com>
 *          Soomin Lee <bubu@mikan.io>
 *
 * Refer to the COPYING file of the official project for license.
 *****************************************************************************/

#import <Foundation/Foundation.h>
#import "VLCEmptyLibraryView.h"
#import "VLCFirstStepsViewController.h"
#import "VLC-Swift.h"

@implementation VLCEmptyLibraryView

- (void)awakeFromNib
{
    _emptyLibraryLabel.text = NSLocalizedString(@"EMPTY_LIBRARY", nil);
    _emptyLibraryLongDescriptionLabel.text = NSLocalizedString(@"EMPTY_LIBRARY_LONG", nil);
    [_learnMoreButton setTitle:NSLocalizedString(@"BUTTON_LEARN_MORE", nil) forState:UIControlStateNormal];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(themeDidChange)
                                                 name:kVLCThemeDidChangeNotification
                                               object:nil];
    [self themeDidChange];
    [super awakeFromNib];
}

- (IBAction)learnMore:(id)sender
{
    if (self.addExternalFolderHandler) {
        self.addExternalFolderHandler();
        return;
    }

      UIViewController *firstStepsVC = [[VLCFirstStepsViewController alloc] initWithNibName:nil bundle:nil];
      UINavigationController *navCon = [[UINavigationController alloc] initWithRootViewController:firstStepsVC];
      navCon.modalPresentationStyle = UIModalPresentationFormSheet;
      [self.window.rootViewController presentViewController:navCon animated:YES completion:nil];
}

- (void)themeDidChange
{
    ColorPalette *colors = PresentationTheme.current.colors;
    [_learnMoreButton setTitleColor:colors.orangeDarkAccent forState:UIControlStateHighlighted];
    _emptyLibraryLabel.textColor = colors.cellTextColor;
    _emptyLibraryLabel.backgroundColor = colors.background;
    _emptyLibraryLongDescriptionLabel.textColor = colors.lightTextColor;
    _emptyLibraryLongDescriptionLabel.backgroundColor = colors.background;
    // The empty state carries the branded app icon (the Osho artwork), not the
    // upstream VLC cone. Keep the cone as a fallback for targets without the
    // iOS asset catalog (tvOS).
    UIImage *appIcon = [UIImage imageNamed:@"LaunchIcon"];
    _iconView.image = appIcon ?: [UIImage imageNamed:(colors.isDark ? @"VLCCone26-dark-512x512"
                                                                   : @"VLCCone26-512x512")];
}

- (void)setContentType:(VLCEmptyLibraryViewContentType)contentType
{
    _contentType = contentType;

    NSString *title;
    NSString *description;

    switch (contentType) {
        case VLCEmptyLibraryViewContentTypeVideo:
        case VLCEmptyLibraryViewContentTypeAudio:
            title = NSLocalizedString(@"EMPTY_LIBRARY", nil);
            description = NSLocalizedString(@"EMPTY_LIBRARY_LONG", nil);
            _learnMoreButton.hidden = NO;
            break;
        case VLCEmptyLibraryViewContentTypePlaylist:
            title = NSLocalizedString(@"EMPTY_PLAYLIST", nil);
            description = NSLocalizedString(@"EMPTY_PLAYLIST_DESCRIPTION",
                                            nil);
            _learnMoreButton.hidden = YES;
            break;
        case VLCEmptyLibraryViewContentTypeNoHistory:
            title = NSLocalizedString(@"EMPTY_HISTORY", nil);
            description = NSLocalizedString(@"EMPTY_HISTORY_DESCRIPTION", nil);
            _learnMoreButton.hidden = YES;
            break;
        case VLCEmptyLibraryViewContentTypeNoPlaylists:
            title = NSLocalizedString(@"EMPTY_NO_PLAYLISTS", nil);
            description = NSLocalizedString(@"EMPTY_NO_PLAYLISTS_DESCRIPTION",
                                            nil);
            _learnMoreButton.hidden = YES;
            break;
        case VLCEmptyLibraryViewContentTypeNoFavorites:
            title = NSLocalizedString(@"NO_FAVORITES", nil);
            description = NSLocalizedString(@"NO_FAVORITES_DESCRIPTION", nil);
            _learnMoreButton.hidden = YES;
            break;
        case VLCEmptyLibraryViewContentTypeEmptyFolder:
            title = _folderName ? _folderName : NSLocalizedString(@"EMPTY_FOLDER", nil);
            description = _isAudioFolder ? NSLocalizedString(@"EMPTY_FOLDER_DES_AUDIO", nil)
                                         : NSLocalizedString(@"EMPTY_FOLDER_DES_VIDEO", nil);
            _learnMoreButton.hidden = YES;
            break;
        case VLCEmptyLibraryViewContentTypeNoLocalAudio:
            title = NSLocalizedString(@"LOCAL_AUDIO_EMPTY_TITLE", nil);
            description = NSLocalizedString(@"LOCAL_AUDIO_EMPTY_DESCRIPTION", nil);
            [_learnMoreButton setTitle:NSLocalizedString(@"ADD_EXTERNAL_FOLDER", nil) forState:UIControlStateNormal];
            _learnMoreButton.hidden = NO;
            break;
        case VLCEmptyLibraryViewContentTypeAddLocalAudioFolder:
            title = NSLocalizedString(@"LOCAL_AUDIO_ACCESS_TITLE", nil);
            description = NSLocalizedString(@"LOCAL_AUDIO_ACCESS_DESCRIPTION", nil);
            [_learnMoreButton setTitle:NSLocalizedString(@"ADD_EXTERNAL_FOLDER", nil) forState:UIControlStateNormal];
            _learnMoreButton.hidden = NO;
            break;
    }
    _emptyLibraryLabel.text = title;
    _emptyLibraryLongDescriptionLabel.text = description;
}

@end
