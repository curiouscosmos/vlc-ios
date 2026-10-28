/*****************************************************************************
 * VLCCloudStorageTableViewCell.m
 * VLC for iOS
 *****************************************************************************
 * Copyright (c) 2013-2026 VideoLAN. All rights reserved.
 * $Id$
 *
 * Authors:  Carola Nitz <nitz.carola # googlemail.com>
 *        Felix Paul Kühne <fkuehne # videolan.org>
 *        Eshan Singh <eeeshan789 # gmail.com>
 * Refer to the COPYING file of the official project for license.
 *****************************************************************************/

#import "VLCCloudStorageTableViewCell.h"
#import "VLCNetworkImageView.h"
#import "VLCBoxController.h"
#import "NSString+SupportedMedia.h"

#import "VLC-Swift.h"

@implementation VLCCloudStorageTableViewCell

+ (VLCCloudStorageTableViewCell *)cellWithReuseIdentifier:(NSString *)ident
{
    NSArray *nibContentArray = [[NSBundle mainBundle] loadNibNamed:@"VLCCloudStorageTableViewCell" owner:nil options:nil];
    NSAssert([nibContentArray count] == 1, @"meh");
    NSAssert([[nibContentArray lastObject] isKindOfClass:[VLCCloudStorageTableViewCell class]], @"meh meh");
    VLCCloudStorageTableViewCell *cell = (VLCCloudStorageTableViewCell *)[nibContentArray lastObject];

    cell.titleLabel.hidden = YES;
    cell.subtitleLabel.hidden = YES;
    cell.folderTitleLabel.hidden = YES;
    
    cell.isFavourite = NO;
    cell.isFavourable = NO;
    
    [[NSNotificationCenter defaultCenter] addObserver:cell selector:@selector(updateAppearanceForColorScheme) name:kVLCThemeDidChangeNotification object:nil];
    [cell updateAppearanceForColorScheme];

    return cell;
}

- (IBAction)didTapFavorite:(id)sender
{
    self.isFavourite = !self.isFavourite;
   [self.delegate triggerFavoriteForCell: self];
    
}

- (void)setDropboxFile:(DBFILESMetadata *)dropboxFile
{
    if (dropboxFile != _dropboxFile)
        _dropboxFile = dropboxFile;

    [self performSelectorOnMainThread:@selector(_updatedDisplayedInformation)
                           withObject:nil waitUntilDone:NO];
}

- (void)setBoxFile:(BoxItem *)boxFile
{
    if (boxFile != _boxFile)
        _boxFile = boxFile;

    [self performSelectorOnMainThread:@selector(_updatedDisplayedInformation)
                           withObject:nil waitUntilDone:NO];
}

- (void)setPcloudFile:(VLCPCloudCellContentWrapper *)pcloudFile {
    if (pcloudFile != _pcloudFile)
        _pcloudFile = pcloudFile;

    [self performSelectorOnMainThread:@selector(_updatedDisplayedInformation)
                           withObject:nil waitUntilDone:NO];
}

- (void)_updatedDisplayedInformation
{
    /* cells are reused across providers, so never inherit a badge */

    if (_dropboxFile != nil) {
        if ([_dropboxFile isKindOfClass:[DBFILESFolderMetadata class]]) {
            self.folderTitleLabel.text = self.dropboxFile.name;
            self.titleLabel.hidden = self.subtitleLabel.hidden = YES;
            self.folderTitleLabel.hidden = NO;
            self.downloadButton.hidden = NO;
            self.isFavourable = YES;
        
            VLCFavoriteService *service =  [VLCAppCoordinator sharedInstance].favoriteService;
            
            NSString *selectedFilePath = _dropboxFile.pathLower;
            NSString *urlString = [NSString stringWithFormat:@"file://DropBox/%@", selectedFilePath];
            NSURL *url = [NSURL URLWithString:urlString];
            self.isFavourite = [service isFavoriteURL:url];
            self.thumbnailView.image = [UIImage systemImageNamed:@"folder"];
        } else if ([_dropboxFile isKindOfClass:[DBFILESFileMetadata class]]) {
            DBFILESFileMetadata *file = (DBFILESFileMetadata *)_dropboxFile;
            self.titleLabel.text = file.name;
            self.subtitleLabel.text = (file.size.integerValue > 0) ? [NSByteCountFormatter stringFromByteCount:file.size.longLongValue countStyle:NSByteCountFormatterCountStyleFile] : @"";
            self.titleLabel.hidden = self.subtitleLabel.hidden = NO;
            self.folderTitleLabel.hidden = YES;
            self.downloadButton.hidden = ![file.name isSupportedFormat];
            self.isFavourable = NO;
            self.favouriteButton.hidden = YES;

            self.thumbnailView.image = [UIImage imageNamed:@"blank"];

            [[VLCDropboxController sharedInstance] loadThumbnailForFile:file completion:^(UIImage * _Nullable image) {
                if (image) {
                    self->_thumbnailView.image = image;
                }
            }];
        }
    }
    else if(_boxFile != nil) {
        BOOL isDirectory = [self.boxFile.type isEqualToString:@"folder"];
        if (isDirectory) {
            self.folderTitleLabel.text = self.boxFile.name;
            self.titleLabel.hidden = self.subtitleLabel.hidden = YES;
            self.folderTitleLabel.hidden = NO;
            self.downloadButton.hidden = NO;
            self.isFavourable = YES;
            
            VLCFavoriteService *service =  [VLCAppCoordinator sharedInstance].favoriteService;
            NSString *selectedFilePath = _boxFile.modelID;
            NSString *urlString = [NSString stringWithFormat:@"file://Box/%@", selectedFilePath];
            NSURL *url = [NSURL URLWithString:urlString];
            
            self.isFavourite = [service isFavoriteURL:url];
        } else {
            NSString *title = self.boxFile.name;
            self.titleLabel.text = title;
            self.subtitleLabel.text = (self.boxFile.size > 0) ? [NSByteCountFormatter stringFromByteCount:[self.boxFile.size longLongValue] countStyle:NSByteCountFormatterCountStyleFile]: @"";
            self.titleLabel.hidden = self.subtitleLabel.hidden = NO;
            self.folderTitleLabel.hidden = YES;
            self.downloadButton.hidden = NO;
            self.favouriteButton.hidden = YES;
        }

        if (isDirectory) {
            self.thumbnailView.image = [UIImage systemImageNamed:@"folder"];
        } else {
            self.thumbnailView.image = [UIImage imageNamed:@"blank"];
        }

        if (!isDirectory) {
            [[VLCBoxController sharedInstance] loadThumbnailForFileID:self.boxFile.modelID completion:^(UIImage * _Nullable image) {
                if (image) {
                    self->_thumbnailView.image = image;
                }
            }];
        }
    } else if(_pcloudFile != nil) {
        BOOL isDirectory = self.pcloudFile.isDirectory;

        if (isDirectory) {
            self.folderTitleLabel.text = self.pcloudFile.name;
            self.titleLabel.hidden = self.subtitleLabel.hidden = YES;
            self.folderTitleLabel.hidden = NO;
            self.downloadButton.hidden = YES;
            self.isFavourable = YES;

            VLCFavoriteService *service =  [VLCAppCoordinator sharedInstance].favoriteService;
            NSNumber *folderIDNumber = _pcloudFile.folderID;
            NSString *selectedFilePath = [folderIDNumber stringValue];
            NSString *urlString = [NSString stringWithFormat:@"file://PCloud/%@", selectedFilePath];
            NSURL *url = [NSURL URLWithString:urlString];
            self.isFavourite = [service isFavoriteURL:url];
        } else {
            self.titleLabel.text = self.pcloudFile.name;
            self.titleLabel.hidden = self.subtitleLabel.hidden = NO;
            self.subtitleLabel.text = (self.pcloudFile.fileSize > 0) ? [NSByteCountFormatter stringFromByteCount:[self.pcloudFile.fileSize longLongValue] countStyle:NSByteCountFormatterCountStyleFile]: @"";
            self.folderTitleLabel.hidden = YES;
            self.downloadButton.hidden = NO;
        }

        if (isDirectory) {
            self.thumbnailView.image = [UIImage systemImageNamed:@"folder"];
        } else if (self.pcloudFile.isAudioFile) {
            self.thumbnailView.image = [UIImage imageNamed:@"audioFile"];
        } else if (self.pcloudFile.isVideoFile) {
            self.thumbnailView.image = [UIImage imageNamed:@"movie"];
        } else {
            self.thumbnailView.image = [UIImage imageNamed:@"blank"];
        }

        if (!isDirectory && self.pcloudFile.hasThumbnail && self.pcloudFile.fileID != nil) {
            [[VLCPCloudController pCloudInstance] thumbnailURLForFileID:self.pcloudFile.fileID completion:^(NSURL * _Nullable url) {
                if (url) {
                    [self->_thumbnailView setImageWithURL:url];
                }
            }];
        }
    }

    [self setNeedsDisplay];
}

- (IBAction)triggerDownload:(id)sender
{
    if ([self.delegate respondsToSelector:@selector(triggerDownloadForCell:)])
        [self.delegate triggerDownloadForCell:self];
}


+ (CGFloat)heightOfCell
{
    return 8. * 4. + [[UIFont preferredFontForTextStyle:UIFontTextStyleBody] lineHeight] + [[UIFont preferredFontForTextStyle:UIFontTextStyleCaption2] lineHeight];
}

- (void)setIsDownloadable:(BOOL)isDownloadable
{
    self.downloadButton.hidden = !isDownloadable;
}



- (void)setIsFavourite:(BOOL)isFavourite
{
    _favouriteButton.hidden = !isFavourite;
    if (isFavourite) {
        [_favouriteButton setImage:[UIImage systemImageNamed:@"heart.fill"] forState:UIControlStateNormal];
    }
       
    _isFavourite = isFavourite;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    _thumbnailView.image = nil;
}

- (void)updateAppearanceForColorScheme
{
    ColorPalette *colors = PresentationTheme.current.colors;
    self.backgroundColor = colors.cellBackgroundA;
    self.titleLabel.textColor = colors.cellTextColor;
    self.folderTitleLabel.textColor = colors.cellTextColor;
    self.subtitleLabel.textColor = colors.cellDetailTextColor;
}

@end
