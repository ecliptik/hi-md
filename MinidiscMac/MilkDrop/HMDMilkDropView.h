#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// MilkDrop drawn by projectM in an OpenGL 4.1 view. Swift owns the window, the presets and the
/// audio; this view only renders. It is Objective-C because AppKit's OpenGL classes are
/// deprecated, and the Swift targets treat deprecation warnings as errors.
@interface HMDMilkDropView : NSView

/// False when OpenGL or projectM couldn't start; the view then stays black.
@property (nonatomic, readonly) BOOL isReady;
/// Seconds before projectM asks for another preset.
@property (nonatomic) double presetDuration;
/// Called on the main thread when projectM wants the next preset: the time is up, or a beat hit
/// hard enough for a cut.
@property (nonatomic, copy, nullable) void (^presetSwitchRequested)(BOOL hardCut);
/// Called on the main thread when a preset couldn't be loaded or compiled.
@property (nonatomic, copy, nullable) void (^presetFailed)(NSString *path, NSString *message);

/// Mono samples between -1 and 1, oldest first.
- (void)addMonoSamples:(const float *)samples count:(NSUInteger)count;
/// Draws one frame with the audio added since the last.
- (void)renderFrame;
/// Switches to the preset file, blending from the current one when `smooth`.
- (void)loadPresetAtPath:(NSString *)path smooth:(BOOL)smooth;

@end

NS_ASSUME_NONNULL_END
