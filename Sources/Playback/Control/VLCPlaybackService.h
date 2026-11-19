/*****************************************************************************
 * VLCPlaybackService.h
 * VLC for iOS
 *****************************************************************************
 * Copyright (c) 2013-2026 VLC authors and VideoLAN
 * $Id$
 *
 * Authors: Felix Paul Kühne <fkuehne # videolan.org>
 *          Tobias Conradi <videolan # tobias-conradi.de>
 *          Maxime Chapelet <umxprime # videolabs.io>
 *          Diogo Simao Marques <dogo@videolabs.io>
 *          Pratik Ray <raypratik365@gmail.com>
 *
 * Refer to the COPYING file of the official project for license.
 *****************************************************************************/

NS_ASSUME_NONNULL_BEGIN
extern NSString *const VLCPlaybackServicePlaybackDidStart;
extern NSString *const VLCPlaybackServicePlaybackDidPause;
extern NSString *const VLCPlaybackServicePlaybackDidResume;
extern NSString *const VLCPlaybackServicePlaybackWillStop;
extern NSString *const VLCPlaybackServicePlaybackDidStop;
extern NSString *const VLCPlaybackServicePlaybackDidFail;
extern NSString *const VLCPlaybackServicePlaybackMetadataDidChange;
extern NSString *const VLCPlaybackServicePlaybackRateDidChange;
extern NSString *const VLCPlaybackServicePlaybackPositionUpdated;
extern NSString *const VLCPlaybackServicePlaybackModeUpdated;
extern NSString *const VLCPlaybackServiceShuffleModeUpdated;
extern NSString *const VLCPlaybackServicePlaybackDidMoveOnToNextItem;
extern NSString *const VLCPlaybackServiceSleepTimerDidChange;
extern NSString *const VLCLastPlaylistPlayedMedia;

@class VLCPlaybackService;
@class VLCMetaData;
@class VLCMLMedia;
@class VLCPlayerDisplayController;
@class VLCPlaybackServiceAdjustFilter;
@class VLCMediaPlayerTitleDescription;
@class VLCMediaPlayerChapterDescription;
@class VLCMediaPlayerTrack;
@class VLCAudioEqualizerPreset;

@protocol VLCPlaybackServiceDelegate <NSObject>
@optional
- (void)playbackPositionUpdated:(VLCPlaybackService *)playbackService;
- (void)mediaPlayerStateChanged:(VLCMediaPlayerState)currentState
                      isPlaying:(BOOL)isPlaying
currentMediaHasTrackToChooseFrom:(BOOL)currentMediaHasTrackToChooseFrom
        currentMediaHasChapters:(BOOL)currentMediaHasChapters
             forPlaybackService:(VLCPlaybackService *)playbackService;
- (void)mediaPlayerBufferingChanged:(float)progress
                 forPlaybackService:(VLCPlaybackService *)playbackService;
- (void)prepareForMediaPlayback:(VLCPlaybackService *)playbackService;
- (void)showStatusMessage:(NSString *)statusMessage;
- (void)displayMetadataForPlaybackService:(VLCPlaybackService *)playbackService
                                 metadata:(VLCMetaData *)metadata;
- (void)playbackServiceDidSwitchAspectRatio:(NSInteger)aspectRatio;
- (void)playbackService:(VLCPlaybackService *)playbackService
              nextMedia:(VLCMedia *)media;
- (void)playModeUpdated;
- (void)reloadPlayQueue;
- (void)pictureInPictureStateDidChange:(BOOL)isEnabled
NS_SWIFT_NAME(pictureInPictureStateDidChange(enabled:));
- (void)updateWidgetsIfNeeded;
@end

NS_SWIFT_NAME(PlaybackService)
@interface VLCPlaybackService : NSObject
#if TARGET_OS_IOS
@property (nonatomic, readonly, getter=isRestoredPaused) BOOL restoredPaused;
- (BOOL)restoreReadyPlayback;
- (void)saveReadyPlayback;
- (void)configureReadyPlayback:(NSDictionary *)snapshot;
#endif

#if !TARGET_OS_IOS
@property (nonatomic, strong, nullable) UIView *videoOutputView API_UNAVAILABLE(watchos);
#endif

@property (nonatomic, retain) VLCMediaList *mediaList;
@property (nonatomic, retain) VLCMediaList *shuffledList;

/* returns nil if currently playing item is not available,*/

@property (nonatomic, strong, readonly, nullable) VLCMedia *currentlyPlayingMedia;
@property (nonatomic, strong, readonly, nullable) VLCMLMedia *currentlyPlayingLibraryMedia;

@property (nonatomic, weak) id<VLCPlaybackServiceDelegate> delegate;

@property (nonatomic, readonly) VLCMediaPlayerState mediaPlayerState;
@property (nonatomic, readonly) VLCMetaData *metadata;

@property (nonatomic, readonly) NSInteger mediaDuration;
@property (nonatomic, readonly) VLCTime *mediaLength;
@property (nonatomic, readonly) BOOL isPlaying;
@property (nonatomic, readonly) BOOL playerIsSetup;
@property (nonatomic, readwrite) BOOL playAsAudio;
@property (nonatomic, readwrite) BOOL expectsAudioOnlyContent;
@property (nonatomic, readwrite) VLCRepeatMode repeatMode;
@property (nonatomic, assign, getter=isShuffleMode) BOOL shuffleMode;
@property (nonatomic, readwrite) float playbackRate; // default = 1.0
@property (nonatomic, readonly) CGFloat defaultPlaybackRate; // user-configured default speed
@property (nonatomic, readwrite) float audioDelay; // in milliseconds, default = 0.0
@property (nonatomic, readwrite) float playbackPosition; // in seconds, default = 0.0
@property (nonatomic, readwrite) float startPosition; // [0;1] applied when the next media opens, negative to enforce none
#if !TARGET_OS_IOS
@property (nonatomic, readwrite) float subtitleDelay; // in milliseconds, default = 0.0
@property (nonatomic, readonly) VLCPlaybackServiceAdjustFilter *adjustFilter;
@property (nonatomic, readonly) CGFloat yaw; //  between ]-180;180]
@property (nonatomic, readonly) CGFloat pitch; // ]-90;90]
@property (nonatomic, readonly) CGFloat roll; // ]-180;180]
@property (nonatomic, readonly) CGFloat fov; // ]0;180[ (default 80.)
#endif

@property (readonly) NSInteger indexOfCurrentAudioTrack;
#if !TARGET_OS_IOS
@property (readonly) NSInteger indexOfCurrentPrimaryVideoSubtitleTrack;
@property (readonly) NSInteger indexOfCurrentSecondaryVideoSubtitleTrack;
#endif
@property (readonly) NSInteger indexOfCurrentTitle;
@property (readonly, nullable) VLCMediaPlayerTitleDescription *currentTitleDescription;
@property (readonly) NSInteger indexOfCurrentChapter;
@property (readonly, nullable) VLCMediaPlayerChapterDescription *currentChapterDescription;
#if !TARGET_OS_IOS
@property (readonly) NSInteger numberOfVideoTracks;
#endif
@property (readonly) NSInteger numberOfAudioTracks;
#if !TARGET_OS_IOS
@property (readonly) NSInteger numberOfVideoSubtitlesIndexes;
#endif
@property (nonatomic, readonly) NSArray<VLCMediaPlayerTrack *> *audioTracks;
#if !TARGET_OS_IOS
@property (nonatomic, readonly) NSArray<VLCMediaPlayerTrack *> *textTracks;
#endif
@property (readonly) NSInteger numberOfTitles;
@property (readonly) NSInteger numberOfChaptersForCurrentTitle;
@property (assign, readonly) BOOL currentMediaHasTrackToChooseFrom;
@property (assign, readwrite) BOOL fullscreenSessionRequested;
@property (assign, readonly) BOOL isSeekable;
#if !TARGET_OS_IOS
@property (assign, readonly) BOOL currentMediaIs360Video;
#endif
@property (readonly) BOOL isNextMediaAvailable;
@property (readonly) NSNumber *playbackTime;
@property (nonatomic, readonly) NSDictionary *mediaOptionsDictionary;
@property (nonatomic, readonly, nullable) NSTimer *sleepTimer;
@property (nonatomic, readonly) NSTimeInterval sleepTimerInterval;
@property (nonatomic) BOOL stopAfterCurrentItem;

@property (nonatomic, readwrite) CGFloat preAmplification;

#if TARGET_OS_IOS
@property (nonatomic, nullable) VLCRendererItem *renderer;
#endif

#if !TARGET_OS_IOS
@property (nonatomic, readonly) NSInteger currentAspectRatio;
#endif

@property (nonatomic, readonly) VLCPlayerDisplayController *playerDisplayController;

@property (nonatomic) NSMutableArray *openedLocalURLs;

+ (VLCPlaybackService *)sharedInstance;
+ (void)migrateToRelativePreampLevel;
- (VLCTime *)playedTime;
#pragma mark - playback
- (void)startPlayback;
- (void)stopPlayback;
- (void)playPause;
#if TARGET_OS_IOS
/// Absolute timestamp seek for clip previews.
- (void)seekToTime:(NSInteger)milliseconds NS_SWIFT_NAME(seek(toMilliseconds:));
#endif
- (void)play;
- (void)pause;
- (BOOL)next;
- (BOOL)previous;
- (void)jumpForward:(int)interval;
- (void)jumpBackward:(int)interval;
#if !TARGET_OS_IOS
- (void)nextFrame;
- (void)previousFrame;
#endif
- (void)toggleRepeatMode;
- (void)changePlaybackRateByFactor:(float)factor;
- (float)restorePlaybackRateForCurrentMedia;
- (void)savePlaybackRateForCurrentMedia;

- (void)setABLoopFromPosition:(double)from toPosition:(double)to;
- (void)resetABLoop;
- (VLCTime *)remainingTime;

- (NSString *)audioTrackNameAtIndex:(NSInteger)index;
#if !TARGET_OS_IOS
- (NSString *)videoSubtitleNameAtIndex:(NSInteger)index;
#endif
- (nullable VLCMediaPlayerTitleDescription *)titleDescriptionAtIndex:(NSInteger)index;
- (nullable VLCMediaPlayerChapterDescription *)chapterDescriptionAtIndex:(NSInteger)index;
- (void)selectAudioTrackAtIndex:(NSInteger)index;
- (void)disableAudio;
#if !TARGET_OS_IOS
- (void)selectPrimaryVideoSubtitleAtIndex:(NSInteger)index;
- (void)selectSecondaryVideoSubtitleAtIndex:(NSInteger)index;
- (void)disablePrimaryVideoSubtitle;
- (void)disableSecondaryVideoSubtitle;
- (void)syncVideoSubtitleState;
#endif
- (void)selectTitleAtIndex:(NSInteger)index;
- (void)selectChapterAtIndex:(NSInteger)index;
- (void)setAudioPassthrough:(BOOL)shouldPass;
#if !TARGET_OS_IOS
- (void)switchAspectRatio:(BOOL)toggleFullScreen;
- (void)setCurrentAspectRatio:(NSInteger)currentAspectRatio;
#endif

- (void)playItemAtIndex:(NSUInteger)index;

#if !TARGET_OS_IOS
- (BOOL)updateViewpoint:(CGFloat)yaw pitch:(CGFloat)pitch roll:(CGFloat)roll fov:(CGFloat)fov absolute:(BOOL)absolute;
- (NSInteger)currentMediaProjection;
#endif

- (void)recoverDisplayedMetadata;
- (void)refreshCurrentMediaMetadata;
- (void)recoverPlaybackState;
#if !TARGET_OS_IOS
- (void)disableSubtitlesIfNeeded;
#endif
- (BOOL)isPlayingOnExternalScreen;

- (void)setPlayerHidden:(BOOL)hidden;
- (void)setPlayerDisplayController:(VLCPlayerDisplayController *)playerDisplayController;

- (void)setNeedsMetadataUpdate;
- (void)scheduleSleepTimerWithInterval:(NSTimeInterval)timeInterval;
- (void)cancelSleepTimer;
- (void)performNavigationAction:(VLCMediaPlaybackNavigationAction)action;
- (void)playMediaList:(VLCMediaList *)mediaList firstIndex:(NSInteger)index subtitlesFilePath:(nullable NSString *)subsFilePath;
- (void)playMediaList:(VLCMediaList *)mediaList firstIndex:(NSInteger)index subtitlesFilePath:(nullable NSString *)subsFilePath completion:(void (^ __nullable)(BOOL success))completion;
- (void)replacePlayingMedia:(VLCMedia *)media;
- (void)addAudioToCurrentPlaybackFromURL:(NSURL *)audioURL;
#if !TARGET_OS_IOS
- (void)addSubtitlesToCurrentPlaybackFromURL:(NSURL *)subtitleURL;
#endif
- (void)setAmplification:(CGFloat)amplification forBand:(unsigned int)index;
- (CGFloat)amplificationOfBand:(unsigned int)index;
- (unsigned int)numberOfBands;
- (CGFloat)frequencyOfBandAtIndex:(unsigned int)index;
- (NSArray<VLCAudioEqualizerPreset *> *)equalizerProfiles;
#if !TARGET_OS_IOS
- (void)togglePictureInPicture;
#endif

- (void)savePlaybackState;

- (void)configurePlaybackWithMediaAtIndex:(NSInteger)index fromMediaList:(VLCMediaList *)mediaList;
#if TARGET_OS_IOS || TARGET_OS_VISION
- (void)restoreAudioAndSubtitleTrack;
- (BOOL)mediaListContains:(NSURL *)url;
- (void)removeMediaFromMediaListAtIndex:(NSUInteger)index;
- (NSIndexPath *)selectedEqualizerProfile;
@property (nonatomic, readonly) NSArray<NSString *> *customEqualizerProfileNames;
- (void)applyEqualizerPreset:(unsigned int)profile;
- (void)applyCustomEqualizerProfileAtIndex:(NSUInteger)index;
- (void)restoreSavedEqualizerProfile;
- (void)saveCustomEqualizerProfileWithName:(NSString *)name;
- (void)renameCustomEqualizerProfileAtIndex:(NSUInteger)index toName:(NSString *)name;
- (void)deleteCustomEqualizerProfileAtIndex:(NSUInteger)index;
- (void)moveCustomEqualizerProfileAtIndex:(NSUInteger)index up:(BOOL)up;
#endif

#if !TARGET_OS_WATCH
- (void)saveCurrentlyPlayingMediaIdentifier;
#endif

NS_ASSUME_NONNULL_END
@end
