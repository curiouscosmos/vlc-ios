/* Copyright (c) 2026 Sandalbar Enterprises, Inc.
 * Refer to COPYING for licensing. */
#import <XCTest/XCTest.h>
#import <UIKit/UIKit.h>
#import <VLCKit/VLCKit.h>
#import "VLCPlaybackService.h"
@import AVFoundation;

@interface VLCMediaPlayer (RDNoiseReductionTests)
- (BOOL)prepareNoiseReduction;
- (BOOL)noiseReductionReady;
- (BOOL)applyNoiseReductionEnabled:(BOOL)enabled;
@end

@interface DiscourseNoiseOutputTests : XCTestCase <VLCMediaPlayerDelegate, VLCLogging>
@property XCTestExpectation *finished;
@property BOOL started;
@property VLCLogLevel level;
@property NSUInteger outputErrors;
@end

@implementation DiscourseNoiseOutputTests
- (void)handleMessage:(NSString *)message logLevel:(VLCLogLevel)level context:(VLCLogContext *)context
{
    if ([message containsString:@"write error"]) self.outputErrors++;
}

- (void)mediaPlayerStateChanged:(VLCMediaPlayerState)state
{
    if (state == VLCMediaPlayerStatePlaying) self.started = YES;
    if (state == VLCMediaPlayerStateStopped && self.started) [self.finished fulfill];
}

- (void)testColdFilterPlaybackProducesAudio
{
    for (NSNumber *rate in @[@22050, @44100, @48000]) {
        NSURL *directory = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
        XCTAssertTrue([NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:nil]);
        NSURL *input = [directory URLByAppendingPathComponent:@"tone.wav"];
        NSURL *output = [directory URLByAppendingPathComponent:@"output.pcm"];
        AVAudioFormat *format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:rate.doubleValue channels:1];
        AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:rate.unsignedIntValue * 2];
        buffer.frameLength = buffer.frameCapacity;
        for (AVAudioFrameCount i = 0; i < buffer.frameLength; ++i)
            buffer.floatChannelData[0][i] = 0.25f * sinf(2.f * M_PI * 440.f * i / rate.floatValue);
        NSError *error = nil;
        AVAudioFile *file = [[AVAudioFile alloc] initForWriting:input settings:format.settings error:&error];
        XCTAssertNotNil(file, @"%@", error);
        XCTAssertTrue([file writeFromBuffer:buffer error:&error], @"%@", error);
        file = nil;

        VLCMediaPlayer *player = [[VLCMediaPlayer alloc] initWithOptions:@[@"--aout=file", @"--audiofile-format=float32", @"--no-audiofile-wav", [@"--audiofile-file=" stringByAppendingString:output.path]]];
        self.level = kVLCLogLevelError;
        self.outputErrors = 0;
        player.libraryInstance.loggers = @[self];
        XCTAssertTrue([player prepareNoiseReduction]);
        XCTAssertTrue([player applyNoiseReductionEnabled:NO]);
        self.started = NO;
        self.finished = [self expectationWithDescription:@"tone playback finishes"];
        player.delegate = self;
        player.media = [VLCMedia mediaWithURL:input];
        [player play];
        [self waitForExpectations:@[self.finished] timeout:15];
        [player stop];
        XCTAssertEqual(self.outputErrors, 0U, @"Resampler startup must not send empty buffers to audio output at %@ Hz", rate);
        NSData *pcm = [NSData dataWithContentsOfURL:output];
        XCTAssertGreaterThan(pcm.length, (NSUInteger)rate.unsignedIntValue * sizeof(float));
        const float *samples = pcm.bytes;
        double energy = 0;
        for (NSUInteger i = 0; i < pcm.length / sizeof(float); ++i) energy += samples[i] * samples[i];
        XCTAssertGreaterThan(energy, 100.0, @"Cold RNNoise output must retain the tone at %@ Hz", rate);
        player.delegate = nil;
        player.libraryInstance.loggers = @[];
        [NSFileManager.defaultManager removeItemAtURL:directory error:nil];
    }
}
@end

@interface RDNoisePlayerStub : NSObject
@property BOOL succeeds;
@property BOOL enabled;
@property BOOL ready;
@end
@implementation RDNoisePlayerStub
- (BOOL)noiseReductionReady { return self.ready; }
- (BOOL)applyNoiseReductionEnabled:(BOOL)enabled
{
    if (!self.succeeds) return NO;
    self.enabled = enabled;
    return YES;
}
- (void)setRendererItem:(id)item { (void)item; }
@end

@interface DiscourseNoiseReductionTests : XCTestCase
@property VLCPlaybackService *service;
@property RDNoisePlayerStub *player;
@property id previousPreference;
@end

@implementation DiscourseNoiseReductionTests
- (void)setUp
{
    [super setUp];
    self.previousPreference = [NSUserDefaults.standardUserDefaults objectForKey:@"RDNoiseReductionEnabled"];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"RDNoiseReductionEnabled"];
    self.service = [VLCPlaybackService new];
    self.player = [RDNoisePlayerStub new];
    self.player.succeeds = YES;
    self.player.ready = YES;
    [self.service setValue:self.player forKey:@"mediaPlayer"];
    [self.service setValue:@YES forKey:@"noiseReductionPrepared"];
}
- (void)tearDown
{
    if (self.previousPreference)
        [NSUserDefaults.standardUserDefaults setObject:self.previousPreference forKey:@"RDNoiseReductionEnabled"];
    else
        [NSUserDefaults.standardUserDefaults removeObjectForKey:@"RDNoiseReductionEnabled"];
    [self.service setValue:nil forKey:@"mediaPlayer"];
    self.service = nil;
    self.player = nil;
    [super tearDown];
}
- (void)testDefaultAndSuccessfulToggle
{
    XCTAssertFalse(self.service.noiseReductionEnabled);
    XCTestExpectation *changed = [self expectationForNotification:VLCPlaybackServiceNoiseReductionDidChange
                                                          object:self.service handler:nil];
    XCTAssertTrue([self.service applyNoiseReductionEnabled:YES]);
    XCTAssertTrue(self.player.enabled);
    XCTAssertTrue(self.service.noiseReductionEnabled);
    XCTAssertTrue([NSUserDefaults.standardUserDefaults boolForKey:@"RDNoiseReductionEnabled"]);
    [self waitForExpectations:@[changed] timeout:1];
    XCTAssertTrue([self.service applyNoiseReductionEnabled:NO]);
    XCTAssertFalse(self.player.enabled);
    XCTAssertFalse(self.service.noiseReductionEnabled);
}
- (void)testFailurePreservesPreviousChoice
{
    XCTAssertTrue([self.service applyNoiseReductionEnabled:YES]);
    self.player.succeeds = NO;
    XCTAssertFalse([self.service applyNoiseReductionEnabled:NO]);
    XCTAssertTrue(self.service.noiseReductionEnabled);
    XCTAssertTrue(self.player.enabled);
}
- (void)testUpstreamEngineCannotEnableNoiseReduction
{
    [self.service setValue:@NO forKey:@"noiseReductionPrepared"];
    XCTAssertFalse(self.service.noiseReductionAvailable);
    XCTAssertFalse([self.service applyNoiseReductionEnabled:YES]);
    XCTAssertFalse([NSUserDefaults.standardUserDefaults boolForKey:@"RDNoiseReductionEnabled"]);
}
- (void)testRendererDisablesControlWithoutErasingPreference
{
    XCTAssertTrue([self.service applyNoiseReductionEnabled:YES]);
    [self.service setRenderer:(VLCRendererItem *)[NSObject new]];
    XCTAssertFalse(self.service.noiseReductionAvailable);
    XCTAssertFalse(self.player.enabled);
    XCTAssertFalse([self.service applyNoiseReductionEnabled:NO]);
    [self.service setRenderer:nil];
    XCTAssertTrue(self.service.noiseReductionAvailable);
    XCTAssertTrue(self.player.enabled);
}
- (void)testOutputFailureDisablesControlWithoutErasingPreference
{
    XCTAssertTrue([self.service applyNoiseReductionEnabled:YES]);
    self.player.ready = NO;
    XCTAssertFalse(self.service.noiseReductionAvailable);
    XCTAssertFalse([self.service applyNoiseReductionEnabled:NO]);
    XCTAssertTrue([NSUserDefaults.standardUserDefaults boolForKey:@"RDNoiseReductionEnabled"]);
    self.player.ready = YES;
    XCTAssertTrue(self.service.noiseReductionEnabled);
}
- (void)testNativeEngineProcessesAudioAndTogglesWithoutStopping
{
    VLCMediaPlayer *engine = [[VLCMediaPlayer alloc] initWithOptions:@[]];
    XCTSkipUnless([engine respondsToSelector:@selector(prepareNoiseReduction)], @"Requires the custom VLCKit artifact");
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:
                                       [NSUUID.UUID.UUIDString stringByAppendingString:@".caf"]]];
    NSError *error = nil;
    AVAudioFormat *format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100 channels:2];
    AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:44100 * 15];
    buffer.frameLength = buffer.frameCapacity;
    for (unsigned channel = 0; channel < 2; ++channel)
        memset(buffer.floatChannelData[channel], 0, buffer.frameLength * sizeof(float));
    AVAudioFile *file = [[AVAudioFile alloc] initForWriting:url settings:format.settings error:&error];
    XCTAssertNotNil(file, @"%@", error);
    XCTAssertTrue([file writeFromBuffer:buffer error:&error], @"%@", error);
    file = nil;
    @try {
        XCTAssertTrue([engine prepareNoiseReduction]);
        XCTAssertTrue([engine applyNoiseReductionEnabled:NO]);
        engine.media = [VLCMedia mediaWithURL:url];
        [engine play];
        NSPredicate *ready = [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
            (void)object; (void)bindings;
            return engine.isPlaying && [engine noiseReductionReady];
        }];
        XCTNSPredicateExpectation *opened = [[XCTNSPredicateExpectation alloc] initWithPredicate:ready object:nil];
        [self waitForExpectations:@[opened] timeout:10];
        NSInteger before = engine.time.intValue;
        for (unsigned i = 0; i < 100; ++i) {
            XCTAssertTrue([engine applyNoiseReductionEnabled:i % 2]);
            XCTAssertTrue([engine noiseReductionReady]);
            XCTAssertTrue(engine.isPlaying);
        }
        engine.equalizer = [VLCAudioEqualizer new];
        XCTNSPredicateExpectation *equalized = [[XCTNSPredicateExpectation alloc] initWithPredicate:ready object:nil];
        [self waitForExpectations:@[equalized] timeout:5];
        XCTAssertTrue([engine applyNoiseReductionEnabled:YES]);
        NSPredicate *advanced = [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
            (void)object; (void)bindings;
            return engine.isPlaying && engine.time.intValue > before + 100;
        }];
        XCTNSPredicateExpectation *progress = [[XCTNSPredicateExpectation alloc] initWithPredicate:advanced object:nil];
        [self waitForExpectations:@[progress] timeout:5];
        XCTAssertTrue([engine noiseReductionReady]);
        [engine pause];
        NSPredicate *paused = [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
            (void)object; (void)bindings;
            return engine.state == VLCMediaPlayerStatePaused;
        }];
        XCTNSPredicateExpectation *pause = [[XCTNSPredicateExpectation alloc] initWithPredicate:paused object:nil];
        [self waitForExpectations:@[pause] timeout:3];
        XCTAssertTrue([engine applyNoiseReductionEnabled:NO]);
        [engine play];
        XCTNSPredicateExpectation *resumed = [[XCTNSPredicateExpectation alloc] initWithPredicate:ready object:nil];
        [self waitForExpectations:@[resumed] timeout:3];
    } @finally {
        [engine stop];
        [NSFileManager.defaultManager removeItemAtURL:url error:nil];
    }
}
@end
