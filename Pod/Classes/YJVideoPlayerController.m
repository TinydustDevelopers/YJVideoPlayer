//
//  KRVideoPlayerController.m
//  KRKit
//
//  Created by aidenluo on 5/23/15.
//  Copyright (c) 2015 36kr. All rights reserved.
//

#import "YJVideoPlayerController.h"
#import "YJVideoPlayerControlView.h"

static const CGFloat kVideoPlayerControllerAnimationTimeinterval = 0.3f;
static const CGFloat kScreenEdgeOffset = 35.0f;

@interface YJVideoPlayerController ()

@property (nonatomic, strong) YJVideoPlayerControlView *videoControl;
@property (nonatomic, strong) UIView *movieBackgroundView;
@property (nonatomic, assign) BOOL isFullscreenMode;
@property (nonatomic, assign) CGRect originFrame;
@property (nonatomic, strong) NSTimer *durationTimer;
@property (nonatomic, strong) UIPanGestureRecognizer *panGestureRecognizer;
@property (nonatomic, strong) UITapGestureRecognizer *tapGestureRecognizer;
@property CGPoint lastCoord;
@property BOOL adjustingVolume;
@property BOOL adjustingBrightness;
@property BOOL adjustingPlayBackTime;

@end

@implementation YJVideoPlayerController

- (void)dealloc {
    [self cancelObserver];
    [self removeGestures];
}

- (instancetype)initWithFrame:(CGRect)frame contentURL:(NSURL *)url {
    self = [super initWithContentURL:url];
    if (self) {
        [self prepareToPlay];

        self.view.frame = frame;
        self.view.backgroundColor = [UIColor blackColor];
        
        self.controlStyle = MPMovieControlStyleNone;
        [self.view addSubview:self.videoControl];
        self.videoControl.frame = self.view.bounds;
        
        self.view.layer.shadowOffset = CGSizeMake(0, 3);
        self.view.layer.shadowRadius = 6.0f;
        self.view.layer.shadowColor = [UIColor blackColor].CGColor;
        self.view.layer.shadowOpacity = 0.6f;
        
        [self configObservers];
        [self configGestures];
        [self configControlActions];
    }
    return self;
}

#pragma mark - Override Method

- (void)setContentURL:(NSURL *)contentURL {
    [self stop];
    [super setContentURL:contentURL];
    [self play];
}

#pragma mark - Publick Method

- (void)showInWindow {
    UIWindow *keyWindow = [[UIApplication sharedApplication] keyWindow];
    if (!keyWindow) {
        keyWindow = [[[UIApplication sharedApplication] windows] firstObject];
    }
    [keyWindow addSubview:self.view];
    self.view.alpha = 0.0;
    [UIView animateWithDuration:kVideoPlayerControllerAnimationTimeinterval animations:^{
        self.view.alpha = 1.0;
    } completion:^(BOOL finished) {
        
    }];
    [[UIApplication sharedApplication] setStatusBarHidden:YES withAnimation:UIStatusBarAnimationFade];
}

- (void)dismiss {
    [self stopDurationTimer];
    [self stop];
    [UIView animateWithDuration:kVideoPlayerControllerAnimationTimeinterval animations:^{
        self.view.alpha = 0.0;
    } completion:^(BOOL finished) {
        [self.view removeFromSuperview];
        if (self.dimissCompleteBlock) {
            self.dimissCompleteBlock();
        }
    }];
    [[UIApplication sharedApplication] setStatusBarHidden:NO withAnimation:UIStatusBarAnimationFade];
}

#pragma mark - Private Method

- (void)configObservers {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onMPMoviePlayerPlaybackStateDidChangeNotification) name:MPMoviePlayerPlaybackStateDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onMPMoviePlayerLoadStateDidChangeNotification) name:MPMoviePlayerLoadStateDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onMPMoviePlayerReadyForDisplayDidChangeNotification) name:MPMoviePlayerReadyForDisplayDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onMPMovieDurationAvailableNotification) name:MPMovieDurationAvailableNotification object:nil];
}

- (void)configGestures {
    self.panGestureRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragging:)];
    self.tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapping:)];
    self.tapGestureRecognizer.numberOfTapsRequired = 2;

    [self.view addGestureRecognizer:self.panGestureRecognizer];
    [self.view addGestureRecognizer:self.tapGestureRecognizer];
}

- (void)cancelObserver {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)removeGestures {
    [self.view removeGestureRecognizer:self.panGestureRecognizer];
    [self.view removeGestureRecognizer:self.tapGestureRecognizer];
}

- (void)configControlActions {
    [self.videoControl.playButton addTarget:self action:@selector(playButtonClick) forControlEvents:UIControlEventTouchUpInside];
    [self.videoControl.pauseButton addTarget:self action:@selector(pauseButtonClick) forControlEvents:UIControlEventTouchUpInside];
    [self.videoControl.closeButton addTarget:self action:@selector(closeButtonClick) forControlEvents:UIControlEventTouchUpInside];
    [self.videoControl.fullScreenButton addTarget:self action:@selector(fullScreenButtonClick) forControlEvents:UIControlEventTouchUpInside];
    [self.videoControl.shrinkScreenButton addTarget:self action:@selector(shrinkScreenButtonClick) forControlEvents:UIControlEventTouchUpInside];
    [self.videoControl.progressSlider addTarget:self action:@selector(progressSliderValueChanged:) forControlEvents:UIControlEventValueChanged];
    [self.videoControl.progressSlider addTarget:self action:@selector(progressSliderTouchBegan:) forControlEvents:UIControlEventTouchDown];
    [self.videoControl.progressSlider addTarget:self action:@selector(progressSliderTouchEnded:) forControlEvents:UIControlEventTouchUpInside];
    [self.videoControl.progressSlider addTarget:self action:@selector(progressSliderTouchEnded:) forControlEvents:UIControlEventTouchUpOutside];
    [self setProgressSliderMaxMinValues];
    [self monitorVideoPlayback];
}

- (void)onMPMoviePlayerPlaybackStateDidChangeNotification {
    if (self.playbackState == MPMoviePlaybackStatePlaying) {
        self.videoControl.pauseButton.hidden = NO;
        self.videoControl.playButton.hidden = YES;
        [self startDurationTimer];
        [self.videoControl.indicatorView stopAnimating];
        [self.videoControl autoFadeOutControlBar];
    } else {
        self.videoControl.pauseButton.hidden = YES;
        self.videoControl.playButton.hidden = NO;
        [self stopDurationTimer];
        if (self.playbackState == MPMoviePlaybackStateStopped) {
            [self.videoControl animateShow];
        }
    }
}

- (void)onMPMoviePlayerLoadStateDidChangeNotification {
    if (self.loadState & MPMovieLoadStateStalled) {
        [self.videoControl.indicatorView startAnimating];
    }
}

- (void)onMPMoviePlayerReadyForDisplayDidChangeNotification {
    
}

- (void)onMPMovieDurationAvailableNotification {
    [self setProgressSliderMaxMinValues];
}

- (void)playButtonClick {
    [self play];
    self.videoControl.playButton.hidden = YES;
    self.videoControl.pauseButton.hidden = NO;
}

- (void)pauseButtonClick {
    [self pause];
    self.videoControl.playButton.hidden = NO;
    self.videoControl.pauseButton.hidden = YES; 
}

- (void)closeButtonClick {
    [self dismiss];
}

- (void)fullScreenButtonClick {
    if (self.isFullscreenMode) {
        return;
    }
    self.originFrame = self.view.frame;
    CGFloat height = [[UIScreen mainScreen] bounds].size.width;
    CGFloat width = [[UIScreen mainScreen] bounds].size.height;
    CGRect frame = CGRectMake((height - width) / 2, (width - height) / 2, width, height);
    [UIView animateWithDuration:0.3f animations:^{
        self.frame = frame;
        [self.view setTransform:CGAffineTransformMakeRotation(M_PI_2)];
    } completion:^(BOOL finished) {
        self.isFullscreenMode = YES;
        self.videoControl.fullScreenButton.hidden = YES;
        self.videoControl.shrinkScreenButton.hidden = NO;
    }];
}

- (void)shrinkScreenButtonClick {
    if (!self.isFullscreenMode) {
        return;
    }
    [UIView animateWithDuration:0.3f animations:^{
        [self.view setTransform:CGAffineTransformIdentity];
        self.frame = self.originFrame;
    } completion:^(BOOL finished) {
        self.isFullscreenMode = NO;
        self.videoControl.fullScreenButton.hidden = NO;
        self.videoControl.shrinkScreenButton.hidden = YES;
    }];
}

- (void)setProgressSliderMaxMinValues {
    CGFloat duration = self.duration;
    self.videoControl.progressSlider.minimumValue = 0.f;
    self.videoControl.progressSlider.maximumValue = duration;
}

- (void)progressSliderTouchBegan:(UISlider *)slider {
    [self pause];
    [self.videoControl cancelAutoFadeOutControlBar];
}

- (void)progressSliderTouchEnded:(UISlider *)slider {
    [self setCurrentPlaybackTime:floor(slider.value)];
    [self play];
    [self.videoControl autoFadeOutControlBar];
}

- (void)progressSliderValueChanged:(UISlider *)slider {
    double currentTime = floor(slider.value);
    double totalTime = floor(self.duration);
    [self setTimeLabelValues:currentTime totalTime:totalTime];
}

- (void)monitorVideoPlayback
{
    double currentTime = floor(self.currentPlaybackTime);
    double totalTime = floor(self.duration);
    [self setTimeLabelValues:currentTime totalTime:totalTime];
    self.videoControl.progressSlider.value = ceil(currentTime);
}

- (void)setTimeLabelValues:(double)currentTime totalTime:(double)totalTime {
    double minutesElapsed = floor(currentTime / 60.0);
    double secondsElapsed = fmod(currentTime, 60.0);
    NSString *timeElapsedString = [NSString stringWithFormat:@"%02.0f:%02.0f", minutesElapsed, secondsElapsed];
    
    double minutesRemaining = floor(totalTime / 60.0);;
    double secondsRemaining = floor(fmod(totalTime, 60.0));;
    NSString *timeRmainingString = [NSString stringWithFormat:@"%02.0f:%02.0f", minutesRemaining, secondsRemaining];
    
    self.videoControl.timeLabel.text = [NSString stringWithFormat:@"%@/%@",timeElapsedString,timeRmainingString];
}

- (void)startDurationTimer {
    self.durationTimer = [NSTimer scheduledTimerWithTimeInterval:0.2 target:self selector:@selector(monitorVideoPlayback) userInfo:nil repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:self.durationTimer forMode:NSDefaultRunLoopMode];
}

- (void)stopDurationTimer {
    [self.durationTimer invalidate];
}

- (void)fadeDismissControl {
    [self.videoControl animateHide];
}

- (void)dragging:(UIPanGestureRecognizer *)recognizer {
    if (!self.isFullscreenMode) {
//        Move player with finger moves
        if (recognizer.state == UIGestureRecognizerStateBegan) {
            self.lastCoord = self.view.center;
        }

        CGPoint translation = [recognizer translationInView:self.view.superview];
        self.view.center = CGPointMake(self.lastCoord.x + translation.x,
                                       self.lastCoord.y + translation.y);

//        we can't let player fly out of the screen totally.
        if (recognizer.state == UIGestureRecognizerStateEnded) {
            CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
            CGFloat screenHeight = [UIScreen mainScreen].bounds.size.height;
            CGFloat screenX = 0.0f;
            CGFloat screenY = 0.0f;
            CGPoint finalPoint = self.view.frame.origin;
            BOOL needOffset = NO;
            
            if (self.view.frame.origin.x + self.view.bounds.size.width <= screenX + kScreenEdgeOffset) {
                //            move back right a little bit
                finalPoint = CGPointMake(screenX + kScreenEdgeOffset - self.view.bounds.size.width, finalPoint.y);
                needOffset = YES;
            }
            
            if (self.view.frame.origin.y + self.view.bounds.size.height <= screenY + kScreenEdgeOffset) {
                //            move back down a little bit
                finalPoint = CGPointMake(finalPoint.x, screenY + kScreenEdgeOffset - self.view.bounds.size.height);
                needOffset = YES;
            }
            
            if (self.view.frame.origin.x >= screenWidth - kScreenEdgeOffset) {
                //            move back left a little bit
                finalPoint = CGPointMake(screenWidth - kScreenEdgeOffset, finalPoint.y);
                needOffset = YES;
            }
            
            if (self.view.frame.origin.y >= screenHeight - kScreenEdgeOffset) {
                //            move back up a little bit
                finalPoint = CGPointMake(finalPoint.x, screenHeight - kScreenEdgeOffset);
                needOffset = YES;
            }
            
            if (needOffset) {
                [UIView animateWithDuration:0.2f animations:^() {
                    self.view.frame = CGRectMake(finalPoint.x, finalPoint.y, self.view.bounds.size.width, self.view.bounds.size.height);
                }];
            }
        }
    } else {
//        Adjust volume, brightness, playback in full screen mode
        CGPoint location = [recognizer locationInView:self.view];
        if (recognizer.state == UIGestureRecognizerStateEnded) {
            [self.videoControl autoFadeOutControlBar];
            
            if (self.adjustingPlayBackTime) {
                [self setCurrentPlaybackTime:floor(self.videoControl.progressSlider.value)];
                [self play];
                self.lastCoord = CGPointZero;
            }
        }
        if (recognizer.state == UIGestureRecognizerStateBegan) {
            self.lastCoord = location;
        }
        if (recognizer.state == UIGestureRecognizerStateEnded || recognizer.state == UIGestureRecognizerStateBegan) {
            self.adjustingBrightness = NO;
            self.adjustingVolume = NO;
            self.adjustingPlayBackTime = NO;
        }

        if ([UIScreen mainScreen].bounds.size.width - location.y <= self.videoControl.bottomBar.bounds.size.height) {
            return;
        }

        CGPoint velocity = [recognizer velocityInView:self.view];
        
        if (self.adjustingVolume) {
            CGFloat volume = [[MPMusicPlayerController applicationMusicPlayer] volume];
            if (volume >= 0 && volume <= 1.0f) {
                [[MPMusicPlayerController applicationMusicPlayer] setVolume:(volume + (-velocity.y)/7000.f)];
            }
            
            return;
        }
        
        if (self.adjustingBrightness) {
            CGFloat brightness = [[UIScreen mainScreen] brightness];
            if (brightness >= 0 && brightness <= 1.0f ) {
                [[UIScreen mainScreen] setBrightness:(brightness + -velocity.y/7000.f)];
            }
            
            return;
        }
        
        if (self.adjustingPlayBackTime) {
            CGFloat distance = location.x - self.lastCoord.x;

            double currentTime = self.currentPlaybackTime;

            currentTime = currentTime + distance * self.duration / 300.0f;

            if (currentTime < 0) {
                currentTime = 0;
            }
            
            if (currentTime > self.duration) {
                currentTime = self.duration;
            }
            
            [self.videoControl.progressSlider setValue:currentTime animated:YES];

            double totalTime = floor(self.duration);
            [self setTimeLabelValues:currentTime totalTime:totalTime];

            return;
        }

        if (fabs(velocity.x) - fabs(velocity.y) >= 50.0f) {
//            pan left or right, start adjusting play back time
            [self pause];
            [self.videoControl animateShow];

            self.adjustingPlayBackTime = YES;

            return;
        }

        if (fabs(velocity.y) - fabs(velocity.x) >= 50.0f) {
//            pan up or down, start adjusting volume or brightness
            if (location.x > ([UIScreen mainScreen].bounds.size.height / 2)) {
                self.adjustingVolume = YES;
                return;
            } else {
                self.adjustingBrightness = YES;
                return;
            }
            
            return;
        }
    }
}

- (void)tapping:(UITapGestureRecognizer *)recognizer {
    if (self.isFullscreenMode) {
        [self.videoControl animateShow];

        if (self.playbackState == MPMoviePlaybackStatePlaying) {
            [self pause];
        } else {
            [self play];
        }

        [self.videoControl animateHide];
    } else {
        [self fullScreenButtonClick];
    }
}

#pragma mark - Property

- (YJVideoPlayerControlView *)videoControl {
    if (!_videoControl) {
        _videoControl = [[YJVideoPlayerControlView alloc] init];
    }
    return _videoControl;
}

- (UIView *)movieBackgroundView {
    if (!_movieBackgroundView) {
        _movieBackgroundView = [UIView new];
        _movieBackgroundView.alpha = 0.0;
        _movieBackgroundView.backgroundColor = [UIColor blackColor];
    }
    return _movieBackgroundView;
}

- (void)setFrame:(CGRect)frame {
    [self.view setFrame:frame];
    [self.videoControl setFrame:CGRectMake(0, 0, frame.size.width, frame.size.height)];
    [self.videoControl setNeedsLayout];
    [self.videoControl layoutIfNeeded];
}

@end
