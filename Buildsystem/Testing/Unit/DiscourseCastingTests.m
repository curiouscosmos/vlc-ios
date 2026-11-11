/* Copyright (c) 2026 Sandalbar Enterprises, Inc. GPLv2 or later; see COPYING. */
#import <XCTest/XCTest.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <VLCKit/VLCKit.h>
#import "VLCPlaybackService.h"

@interface VLCPlaybackService (DiscourseCastingTests)
- (void)updateCastingBackgroundKeepalive;
- (void)stopCastingBackgroundKeepalive;
- (void)applicationDidEnterBackground:(NSNotification *)notification;
- (void)applicationWillEnterForeground:(NSNotification *)notification;
- (void)handleInterruption:(NSNotification *)notification;
- (void)prepareForShutdown:(NSNotification *)notification;
- (void)mediaPlayerStateChanged:(VLCMediaPlayerState)state;
- (void)saveCurrentMediaList;
@end

@interface RDCastingEngineStub : VLCMediaPlayer
@property BOOL simulatedPlaying;
@property VLCMediaPlayerState simulatedState;
@property NSUInteger stopCount;
@property BOOL stoppedOnMainThread;
@end
@implementation RDCastingEngineStub
- (BOOL)isPlaying { return self.simulatedPlaying; }
- (VLCMediaPlayerState)state { return self.simulatedState; }
- (BOOL)setRendererItem:(VLCRendererItem *)item { return YES; }
- (void)pause { self.simulatedPlaying = NO; self.simulatedState = VLCMediaPlayerStatePaused; }
- (void)stop
{
    self.stopCount++;
    self.stoppedOnMainThread = NSThread.isMainThread;
    self.simulatedPlaying = NO;
    self.simulatedState = VLCMediaPlayerStateStopped;
}
@end

// Lifecycle tests must not overwrite the app's legacy last-played playlist.
@interface RDCastingServiceStub : VLCPlaybackService
@end
@implementation RDCastingServiceStub
- (void)saveCurrentMediaList {}
@end

@interface DiscourseCastingTests : XCTestCase
@property RDCastingServiceStub *service;
@property RDCastingEngineStub *engine;
@end

@implementation DiscourseCastingTests
- (void)setUp
{
    [super setUp];
    self.service = [RDCastingServiceStub new];
    self.engine = [RDCastingEngineStub new];
    self.engine.simulatedState = VLCMediaPlayerStateStopped;
    [self.service setValue:self.engine forKey:@"mediaPlayer"];
    [self.service setRenderer:(VLCRendererItem *)[NSObject new]];
}

- (void)tearDown
{
    [self.service stopCastingBackgroundKeepalive];
    [self.service setValue:nil forKey:@"mediaPlayer"];
    self.service = nil;
    self.engine = nil;
    [super tearDown];
}

- (void)simulateState:(VLCMediaPlayerState)state playing:(BOOL)playing
{
    self.engine.simulatedState = state;
    self.engine.simulatedPlaying = playing;
    [self.service setValue:@(state) forKey:@"mediaPlayerState"];
}

- (RDCastingEngineStub *)installKeepalive
{
    RDCastingEngineStub *player = [RDCastingEngineStub new];
    player.simulatedPlaying = YES;
    player.simulatedState = VLCMediaPlayerStatePlaying;
    [self.service setValue:player forKey:@"backgroundDummyPlayer"];
    return player;
}

- (void)testSelectedRendererDoesNotKeepPausedStoppedOrForegroundAppAlive
{
    [self simulateState:VLCMediaPlayerStatePlaying playing:YES];
    [self.service updateCastingBackgroundKeepalive];
    XCTAssertNil([self.service valueForKey:@"backgroundDummyPlayer"]);
    for (NSNumber *state in @[@(VLCMediaPlayerStatePaused), @(VLCMediaPlayerStateStopped), @(VLCMediaPlayerStateOpening),
                             @(VLCMediaPlayerStateStopping), @(VLCMediaPlayerStateError)]) {
        [self simulateState:state.integerValue playing:NO];
        [self.service applicationDidEnterBackground:nil];
        XCTAssertNil([self.service valueForKey:@"backgroundDummyPlayer"]);
    }
    [self simulateState:VLCMediaPlayerStatePlaying playing:NO];
    [self.service updateCastingBackgroundKeepalive];
    XCTAssertNil([self.service valueForKey:@"backgroundDummyPlayer"]);
    [self simulateState:VLCMediaPlayerStatePlaying playing:YES];
    for (NSString *flag in @[@"restoredPaused", @"retainingPlayback", @"shuttingDown"]) {
        [self.service setValue:@YES forKey:flag];
        [self.service updateCastingBackgroundKeepalive];
        XCTAssertNil([self.service valueForKey:@"backgroundDummyPlayer"], @"%@ must suppress the keepalive", flag);
        [self.service setValue:@NO forKey:flag];
    }
}

- (void)testActiveBackgroundCastingStartsOnceAndDisconnectStopsIt
{
    [self simulateState:VLCMediaPlayerStatePlaying playing:YES];
    [self.service applicationDidEnterBackground:nil];
    VLCMediaPlayer *keepalive = [self.service valueForKey:@"backgroundDummyPlayer"];
    XCTAssertNotNil(keepalive);
    XCTAssertEqualObjects(keepalive.media.url.path, @"/dev/zero");
    [self.service updateCastingBackgroundKeepalive];
    XCTAssertEqual([self.service valueForKey:@"backgroundDummyPlayer"], keepalive);
    [self.service setRenderer:nil];
    XCTAssertNil([self.service valueForKey:@"backgroundDummyPlayer"]);
}

- (void)testPauseAndStopReleaseKeepaliveImmediately
{
    RDCastingEngineStub *paused = [self installKeepalive];
    [self.service pause];
    XCTAssertEqual(paused.stopCount, 1U);
    XCTAssertNil([self.service valueForKey:@"backgroundDummyPlayer"]);
    RDCastingEngineStub *stopped = [self installKeepalive];
    [self.service stopPlayback];
    XCTAssertEqual(stopped.stopCount, 1U);
    XCTAssertNil([self.service valueForKey:@"backgroundDummyPlayer"]);
}

- (void)testForegroundStopsOrphanEvenWithoutRenderer
{
    [self.service setRenderer:nil];
    RDCastingEngineStub *orphan = [self installKeepalive];
    [self.service applicationWillEnterForeground:nil];
    XCTAssertEqual(orphan.stopCount, 1U);
    XCTAssertNil([self.service valueForKey:@"backgroundDummyPlayer"]);
}

- (void)testInterruptionAndShutdownStopKeepalive
{
    RDCastingEngineStub *interrupted = [self installKeepalive];
    NSNotification *notification = [NSNotification notificationWithName:AVAudioSessionInterruptionNotification object:nil
                                                             userInfo:@{AVAudioSessionInterruptionTypeKey: @(AVAudioSessionInterruptionTypeBegan)}];
    [self.service handleInterruption:notification];
    XCTAssertEqual(interrupted.stopCount, 1U);
    XCTAssertNil([self.service valueForKey:@"backgroundDummyPlayer"]);
    RDCastingEngineStub *shutdown = [self installKeepalive];
    [self.service prepareForShutdown:nil];
    XCTAssertEqual(shutdown.stopCount, 1U);
    XCTAssertNil([self.service valueForKey:@"backgroundDummyPlayer"]);
}

- (void)testNativePauseResumeAndStalePlayingCallbackFollowActualState
{
    [self.service setValue:@YES forKey:@"castingInBackground"];
    [self simulateState:VLCMediaPlayerStatePlaying playing:YES];
    XCTestExpectation *resumed = [self expectationForNotification:VLCPlaybackServicePlaybackDidResume object:self.service handler:nil];
    [self.service mediaPlayerStateChanged:VLCMediaPlayerStatePlaying];
    [self waitForExpectations:@[resumed] timeout:3];
    XCTAssertNotNil([self.service valueForKey:@"backgroundDummyPlayer"]);
    [self simulateState:VLCMediaPlayerStatePaused playing:NO];
    XCTestExpectation *paused = [self expectationForNotification:VLCPlaybackServicePlaybackDidPause object:self.service handler:nil];
    [self.service mediaPlayerStateChanged:VLCMediaPlayerStatePaused];
    [self waitForExpectations:@[paused] timeout:3];
    XCTAssertNil([self.service valueForKey:@"backgroundDummyPlayer"]);
    XCTestExpectation *stale = [self expectationForNotification:VLCPlaybackServicePlaybackDidResume object:self.service handler:nil];
    [self.service mediaPlayerStateChanged:VLCMediaPlayerStatePlaying];
    [self waitForExpectations:@[stale] timeout:3];
    XCTAssertNil([self.service valueForKey:@"backgroundDummyPlayer"]);
}

- (void)testPauseOffMainStopsKeepaliveOnMainThread
{
    RDCastingEngineStub *keepalive = [self installKeepalive];
    XCTestExpectation *paused = [self expectationWithDescription:@"Background pause is reconciled on main"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        [self.service pause];
        dispatch_async(dispatch_get_main_queue(), ^{ [paused fulfill]; });
    });
    [self waitForExpectations:@[paused] timeout:3];
    XCTAssertEqual(keepalive.stopCount, 1U);
    XCTAssertTrue(keepalive.stoppedOnMainThread);
    XCTAssertNil([self.service valueForKey:@"backgroundDummyPlayer"]);
}
@end
