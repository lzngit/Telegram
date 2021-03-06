#import "TGModernGalleryVideoScrubbingInterfaceView.h"

#import <LegacyComponents/LegacyComponents.h>

#import "TGAudioSliderArea.h"

static CGFloat scrubberPadding = 13.0f;
static CGFloat scrubberInternalInset = 4.0f;

@interface TGModernGalleryVideoScrubbingInterfaceView () <TGAudioSliderAreaDelegate>
{
    UILabel *_currentTimeLabel;
    UILabel *_durationLabel;
    
    UIImageView *_scrubberBackground;
    UIImageView *_scrubberForegroundImage;
    UIView *_scrubberForegroundContainer;
    UIImageView *_scrubberHandle;
    TGAudioSliderArea *_sliderArea;
    
    CGFloat _position;
    bool _isScrubbing;
    CGPoint _sliderButtonStartLocation;
    CGFloat _sliderButtonStartValue;
    CGFloat _scrubbingPosition;
    bool _isPlaying;
    CFAbsoluteTime _positionTimestamp;
    NSTimeInterval _duration;
    
    CGFloat _currentTimeMinWidth;
}

@end

@implementation TGModernGalleryVideoScrubbingInterfaceView

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self != nil)
    {
        _currentTimeLabel = [[UILabel alloc] init];
        _currentTimeLabel.font = TGSystemFontOfSize(12.0f);
        _currentTimeLabel.backgroundColor = [UIColor clearColor];
        _currentTimeLabel.textColor = [UIColor whiteColor];
        [self addSubview:_currentTimeLabel];

        _durationLabel = [[UILabel alloc] init];
        _durationLabel.font = TGSystemFontOfSize(12.0f);
        _durationLabel.backgroundColor = [UIColor clearColor];
        _durationLabel.textColor = [UIColor whiteColor];
        [self addSubview:_durationLabel];
        
        static UIImage *backgroundImage = nil;
        static UIImage *trackImage = nil;
        static dispatch_once_t onceToken1;
        dispatch_once(&onceToken1, ^
        {
            UIGraphicsBeginImageContextWithOptions(CGSizeMake(5.0f, 5.0f), false, 0.0f);
            CGContextRef context = UIGraphicsGetCurrentContext();
            CGContextSetFillColorWithColor(context, UIColorRGBA(0xffffff, 0.25f).CGColor);
            CGContextFillEllipseInRect(context, CGRectMake(0, 0, 5.0f, 5.0f));
            backgroundImage = [UIGraphicsGetImageFromCurrentImageContext() resizableImageWithCapInsets:UIEdgeInsetsMake(0, 2, 0, 2)];
            CGContextClearRect(context, CGRectMake(0.0f, 0.0f, 5.0f, 5.0f));
            CGContextSetFillColorWithColor(context, UIColorRGBA(0xffffff, 0.65f).CGColor);
            CGContextFillEllipseInRect(context, CGRectMake(0, 0, 5.0f, 5.0f));
            trackImage = [UIGraphicsGetImageFromCurrentImageContext() resizableImageWithCapInsets:UIEdgeInsetsMake(0, 2, 0, 2)];
            UIGraphicsEndImageContext();
        });
        
        static UIImage *knobViewImage = nil;
        static dispatch_once_t onceToken2;
        dispatch_once(&onceToken2, ^
        {
            UIGraphicsBeginImageContextWithOptions(CGSizeMake(17.0f, 17.0f), false, 0.0f);
            CGContextRef context = UIGraphicsGetCurrentContext();
            CGContextSetShadowWithColor(context, CGSizeMake(0, 1.0f), 2.0f, [UIColor colorWithWhite:0.0f alpha:0.15f].CGColor);
            CGContextSetFillColorWithColor(context, [UIColor whiteColor].CGColor);
            CGContextFillEllipseInRect(context, CGRectMake(3.0f, 3.0f, 11.0f, 11.0f));
            knobViewImage = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();
        });
        
        _scrubberBackground = [[UIImageView alloc] initWithImage:backgroundImage];
        [self addSubview:_scrubberBackground];
        
        _scrubberForegroundImage = [[UIImageView alloc] initWithImage:trackImage];
        
        _scrubberForegroundContainer = [[UIView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, 0.0f, 5.0f)];
        _scrubberForegroundContainer.clipsToBounds = true;
        [self addSubview:_scrubberForegroundContainer];
        
        [_scrubberForegroundContainer addSubview:_scrubberForegroundImage];
        
        _scrubberHandle = [[UIImageView alloc] initWithImage:knobViewImage];
        [self addSubview:_scrubberHandle];
        
        _sliderArea = [[TGAudioSliderArea alloc] init];
        _sliderArea.delegate = self;
        _sliderArea.userInteractionEnabled = false;
        [self addSubview:_sliderArea];
        
        static dispatch_once_t onceToken;
        static CGFloat currentTimeMinWidth;
        dispatch_once(&onceToken, ^
        {
            currentTimeMinWidth = floor([[[NSAttributedString alloc] initWithString:@"0:00" attributes:@{ NSFontAttributeName: _currentTimeLabel.font }] boundingRectWithSize:CGSizeMake(FLT_MAX, FLT_MAX) options:NSStringDrawingUsesLineFragmentOrigin context:nil].size.width) + TGScreenPixel;
        });
        _currentTimeMinWidth = currentTimeMinWidth;
    }
    return self;
}

- (void)setFrame:(CGRect)frame
{
    [super setFrame:frame];
    [self _layout];
}

- (void)removeRelevantAnimationsFromView:(UIView *)layer
{
    [layer pop_removeAnimationForKey:@"progress"];
}

- (void)addFrameAnimationToView:(UIView *)view from:(CGRect)fromFrame to:(CGRect)toFrame duration:(NSTimeInterval)duration
{
    [self removeRelevantAnimationsFromView:view];

    {
        POPBasicAnimation *animation = [POPBasicAnimation linearAnimation];
        animation.fromValue = [NSValue valueWithCGRect:fromFrame];
        animation.toValue = [NSValue valueWithCGRect:toFrame];
        animation.duration = duration;
        animation.clampMode = kPOPAnimationClampBoth;
        animation.property = [POPAnimatableProperty propertyWithName:@"frame" initializer:^(POPMutableAnimatableProperty *prop) {
            prop.readBlock = ^(UIView *view, CGFloat *values) {
                CGRect frame = view.frame;
                memcpy(values, &frame, sizeof(CGFloat) * 4);
            };
            prop.writeBlock = ^(UIView *view, CGFloat const *values) {
                CGRect frame;
                memcpy(&frame, values, sizeof(CGFloat) * 4);
                view.frame = frame;
            };
            prop.threshold = 0.5f;
        }];
        [view pop_addAnimation:animation forKey:@"progress"];
    }
}

- (CGRect)sliderForegroundFrameForProgress:(CGFloat)progress
{
    return (CGRect){{scrubberPadding, CGFloor((self.frame.size.height - _scrubberForegroundContainer.frame.size.height) / 2.0f) - 7.0f}, {CGFloor((_scrubberBackground.frame.size.width) * progress), _scrubberForegroundContainer.frame.size.height}};
}

- (CGRect)sliderButtonFrameForProgress:(CGFloat)progress
{
    return (CGRect){{scrubberPadding - scrubberInternalInset + CGFloor((_scrubberBackground.frame.size.width - (_scrubberHandle.frame.size.width - scrubberInternalInset * 2.0f)) * progress), CGFloor((self.frame.size.height - _scrubberHandle.frame.size.height) / 2.0f) - 7.0f}, _scrubberHandle.frame.size};
}

- (void)updatePositionAnimations:(bool)immediate
{
    if (_isPlaying && !_isScrubbing && _duration > 0.1)
    {
        CGPoint handleStartPosition = CGPointMake(CGRectGetMidX(_scrubberHandle.frame), CGRectGetMidY(_scrubberHandle.frame));
        CGRect foregroundStartFrame = _scrubberForegroundContainer.frame;
        
        float playedProgress = MAX(0.0f, MIN(1.0f, (float)((CACurrentMediaTime() - _positionTimestamp) / _duration)));
        
        CGRect handlePositionFrame = [self sliderButtonFrameForProgress:_position + playedProgress];
        CGRect foregroundFrame = [self sliderForegroundFrameForProgress:_position + playedProgress];
        CGPoint handlePositionPosition = CGPointMake(CGRectGetMidX(handlePositionFrame), CGRectGetMidY(handlePositionFrame));
        
        if (immediate || (handlePositionFrame.origin.x > [self sliderButtonFrameForProgress:0.0f].origin.x + FLT_EPSILON && (handlePositionPosition.x < handleStartPosition.x - 50.0f)))
        {
            handleStartPosition = handlePositionPosition;
            foregroundStartFrame = foregroundFrame;
        }
        
        CGRect handleEndFrame = [self sliderButtonFrameForProgress:1.0f];
        CGRect foregroundEndFrame = [self sliderForegroundFrameForProgress:1.0f];
        
        NSTimeInterval duration = MAX(0.0, _duration - _position * _duration);
        
        CGRect handleStartFrame = CGRectMake(handleStartPosition.x - _scrubberHandle.frame.size.width / 2.0f, handleStartPosition.y - _scrubberHandle.frame.size.height / 2.0f, _scrubberHandle.frame.size.width, _scrubberHandle.frame.size.height);
        
        [self addFrameAnimationToView:_scrubberHandle from:handleStartFrame to:handleEndFrame duration:duration];
        [self addFrameAnimationToView:_scrubberForegroundContainer from:foregroundStartFrame to:foregroundEndFrame duration:duration];
    }
    else
    {
        CGFloat progressValue = _isScrubbing ? _scrubbingPosition : _position;
        
        [self removeRelevantAnimationsFromView:_scrubberHandle];
        [self removeRelevantAnimationsFromView:_scrubberForegroundContainer];
        
        CGRect handleCurrentFrame = [self sliderButtonFrameForProgress:progressValue];
        _scrubberHandle.frame = handleCurrentFrame;
        _scrubberForegroundContainer.frame = [self sliderForegroundFrameForProgress:progressValue];
    }
}

- (void)setDuration:(NSTimeInterval)duration currentTime:(NSTimeInterval)currentTime isPlaying:(bool)isPlaying isPlayable:(bool)isPlayable animated:(bool)animated
{
    NSString *currentTimeString = @"-:--";
    NSString *durationString = @"-:--";
    if (duration < DBL_EPSILON)
    {
        _position = 0.0f;
    }
    else
    {
        currentTimeString = [[NSString alloc] initWithFormat:@"%d:%02d", ((int)currentTime) / 60, ((int)currentTime) % 60];
        durationString = [[NSString alloc] initWithFormat:@"%d:%02d", ((int)duration) / 60, ((int)duration) % 60];
        _position = MAX(0.0f, MIN(1.0f, (CGFloat)(currentTime / duration)));
    }
    
    if (!TGStringCompare(durationString, _durationLabel.text) || !TGStringCompare(currentTimeString, _currentTimeLabel.text))
    {
        _durationLabel.text = durationString;
        _currentTimeLabel.text = currentTimeString;
        [self _layout];
    }
    
    _isPlaying = isPlaying;
    
    _sliderArea.userInteractionEnabled = isPlayable;
    
    _duration = duration;
    _positionTimestamp = CACurrentMediaTime();
    
    if (!_isScrubbing)
    {
        if (_isPlaying && _duration > 0.1)
            [self updatePositionAnimations:false];
        else
        {
            if (animated)
            {
                [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^
                {
                    _scrubberHandle.frame = [self sliderButtonFrameForProgress:_position];
                    _scrubberForegroundContainer.frame = [self sliderForegroundFrameForProgress:_position];
                } completion:nil];
            }
            else
                [self _layout];
        }
    }
}

- (void)_layout
{
    [_durationLabel sizeToFit];
    [_currentTimeLabel sizeToFit];
    
    CGFloat progressValue = _isScrubbing ? _scrubbingPosition : _position;
    
    _currentTimeLabel.frame = (CGRect){{scrubberPadding, CGFloor((self.frame.size.height - _currentTimeLabel.frame.size.height) / 2.0f) + 11.0f}, { MAX(_currentTimeMinWidth, _currentTimeLabel.frame.size.width), _currentTimeLabel.frame.size.height }};
    
    _durationLabel.frame = (CGRect){{self.frame.size.width - scrubberPadding - _durationLabel.frame.size.width, CGFloor((self.frame.size.height - _durationLabel.frame.size.height) / 2.0f) + 11.0f}, _durationLabel.frame.size};
    
    CGFloat scrubberOriginX = scrubberPadding;
    _scrubberBackground.frame = (CGRect){{scrubberOriginX, CGFloor((self.frame.size.height - _scrubberBackground.frame.size.height) / 2.0f) - 7.0f}, {self.frame.size.width - scrubberPadding - scrubberOriginX, _scrubberBackground.frame.size.height}};
    
    _sliderArea.frame = CGRectMake(0.0f, 0.0f, self.frame.size.width, self.frame.size.height);
    
    _scrubberForegroundImage.frame = _scrubberBackground.bounds;
    
    [self removeRelevantAnimationsFromView:_scrubberHandle];
    [self removeRelevantAnimationsFromView:_scrubberForegroundContainer];
    
    _scrubberForegroundContainer.frame = [self sliderForegroundFrameForProgress:progressValue];
    _scrubberHandle.frame = [self sliderButtonFrameForProgress:progressValue];
    
    [self updatePositionAnimations:false];
}

- (void)audioSliderDidBeginDragging:(TGAudioSliderArea *)__unused sliderArea withTouch:(UITouch *)touch
{
    _isScrubbing = true;
    
    _sliderButtonStartLocation = [touch locationInView:self];
    _sliderButtonStartValue = _position;
    _scrubbingPosition = _position;
    
    [self removeRelevantAnimationsFromView:_scrubberHandle];
    [self removeRelevantAnimationsFromView:_scrubberForegroundContainer];
    [self updatePositionAnimations:false];
    
    if (_scrubbingBegan)
        _scrubbingBegan();
}

- (void)audioSliderDidFinishDragging:(TGAudioSliderArea *)__unused sliderArea
{
    [self removeRelevantAnimationsFromView:_scrubberHandle];
    [self removeRelevantAnimationsFromView:_scrubberForegroundContainer];
    [self updatePositionAnimations:false];
    
    _isScrubbing = false;
    
    if (_scrubbingFinished)
        _scrubbingFinished(_scrubbingPosition);
}

- (void)audioSliderDidCancelDragging:(TGAudioSliderArea *)__unused sliderArea
{
    _isScrubbing = false;
    
    int currentPosition = (int)(_duration * _position);
    
    _currentTimeLabel.text = [[NSString alloc] initWithFormat:@"%d:%02d", currentPosition / 60, currentPosition % 60];
    [_currentTimeLabel sizeToFit];
    
    [self _layout];
    
    if (_scrubbingCancelled)
        _scrubbingCancelled();
}

- (void)audioSliderWillMove:(TGAudioSliderArea *)__unused sliderArea withTouch:(UITouch *)touch
{
    if (_isScrubbing && _scrubberBackground.frame.size.width > 1.0f)
    {
        CGFloat positionDistance = [touch locationInView:self].x - _sliderButtonStartLocation.x;
        
        CGFloat newValue = MAX(0.0f, MIN(1.0f, _sliderButtonStartValue + positionDistance / _scrubberBackground.frame.size.width));
        _scrubbingPosition = newValue;
        int currentPosition = (int)(_duration * _scrubbingPosition);

        _currentTimeLabel.text = [[NSString alloc] initWithFormat:@"%d:%02d", currentPosition / 60, currentPosition % 60];
        [_currentTimeLabel sizeToFit];
        
        [self removeRelevantAnimationsFromView:_scrubberHandle];
        [self removeRelevantAnimationsFromView:_scrubberForegroundContainer];
        [self _layout];
        
        if (_scrubbingChanged)
            _scrubbingChanged(_scrubbingPosition);
    }
}

@end
