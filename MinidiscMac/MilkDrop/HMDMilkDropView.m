#import "HMDMilkDropView.h"

#define GL_SILENCE_DEPRECATION 1
#import <OpenGL/gl3.h>
#import <projectM-4/projectM.h>

// NSOpenGLView, NSOpenGLContext and NSOpenGLPixelFormat are deprecated but still the way to host
// OpenGL in AppKit, which projectM needs.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

@interface HMDMilkDropOpenGLView : NSOpenGLView
@property (nonatomic, weak) HMDMilkDropView *owner;
@end

@interface HMDMilkDropView ()
@property (nonatomic, strong) HMDMilkDropOpenGLView *glView;
@property (nonatomic) projectm_handle projectM;
@property (nonatomic) NSSize drawableSize;
- (void)openGLDidPrepare;
@end

static void HMDPresetSwitchRequested(bool isHardCut, void *userData) {
    HMDMilkDropView *view = (__bridge HMDMilkDropView *)userData;
    void (^handler)(BOOL) = view.presetSwitchRequested;
    if (handler) {
        dispatch_async(dispatch_get_main_queue(), ^{ handler(isHardCut); });
    }
}

static void HMDPresetFailed(const char *filename, const char *message, void *userData) {
    HMDMilkDropView *view = (__bridge HMDMilkDropView *)userData;
    void (^handler)(NSString *, NSString *) = view.presetFailed;
    if (handler) {
        NSString *path = filename ? @(filename) : @"";
        NSString *text = message ? @(message) : @"";
        dispatch_async(dispatch_get_main_queue(), ^{ handler(path, text); });
    }
}

@implementation HMDMilkDropOpenGLView

- (void)prepareOpenGL {
    [super prepareOpenGL];
    GLint swapInterval = 1;
    [self.openGLContext setValues:&swapInterval forParameter:NSOpenGLContextParameterSwapInterval];
    [self.owner openGLDidPrepare];
}

// Swift drives every frame from a display link; AppKit's own redraws would draw a stale one.
- (void)drawRect:(NSRect)dirtyRect {}

- (BOOL)isOpaque { return YES; }

// Clicks, double-clicks and the context menu belong to the MilkDrop view and its window.
- (NSView *)hitTest:(NSPoint)point { return nil; }

@end

@implementation HMDMilkDropView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    _presetDuration = 30;
    NSOpenGLPixelFormatAttribute attributes[] = {
        NSOpenGLPFAOpenGLProfile, NSOpenGLProfileVersion4_1Core,
        NSOpenGLPFAColorSize, 24,
        NSOpenGLPFAAlphaSize, 8,
        NSOpenGLPFADepthSize, 24,
        NSOpenGLPFADoubleBuffer,
        NSOpenGLPFAAccelerated,
        0
    };
    NSOpenGLPixelFormat *format = [[NSOpenGLPixelFormat alloc] initWithAttributes:attributes];
    if (format) {
        _glView = [[HMDMilkDropOpenGLView alloc] initWithFrame:self.bounds pixelFormat:format];
        _glView.owner = self;
        _glView.wantsBestResolutionOpenGLSurface = YES;
        _glView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [self addSubview:_glView];
        // Start projectM now, so presets can load before the window first draws.
        [_glView.openGLContext makeCurrentContext];
        [self openGLDidPrepare];
    }
    return self;
}

- (void)dealloc {
    if (_projectM) {
        [_glView.openGLContext makeCurrentContext];
        projectm_destroy(_projectM);
        [NSOpenGLContext clearCurrentContext];
    }
}

- (BOOL)isReady { return _projectM != NULL; }

- (void)openGLDidPrepare {
    if (_projectM) return;
    [_glView.openGLContext makeCurrentContext];
    _projectM = projectm_create();
    if (!_projectM) {
        NSLog(@"MilkDrop: projectM couldn't start with this OpenGL context");
        return;
    }
    projectm_set_preset_duration(_projectM, _presetDuration);
    projectm_set_soft_cut_duration(_projectM, 3);
    projectm_set_hard_cut_enabled(_projectM, true);
    projectm_set_hard_cut_duration(_projectM, 20);
    projectm_set_aspect_correction(_projectM, true);
    projectm_set_fps(_projectM, 60);
    projectm_set_preset_switch_requested_event_callback(_projectM, HMDPresetSwitchRequested, (__bridge void *)self);
    projectm_set_preset_switch_failed_event_callback(_projectM, HMDPresetFailed, (__bridge void *)self);
}

- (void)setPresetDuration:(double)presetDuration {
    _presetDuration = presetDuration;
    if (_projectM) projectm_set_preset_duration(_projectM, presetDuration);
}

- (void)addMonoSamples:(const float *)samples count:(NSUInteger)count {
    if (!_projectM || count == 0) return;
    projectm_pcm_add_float(_projectM, samples, (unsigned int)count, PROJECTM_MONO);
}

- (void)loadPresetAtPath:(NSString *)path smooth:(BOOL)smooth {
    if (!_projectM) return;
    [_glView.openGLContext makeCurrentContext];
    projectm_load_preset_file(_projectM, path.fileSystemRepresentation, smooth);
}

- (void)renderFrame {
    if (!_projectM) return;
    NSOpenGLContext *context = _glView.openGLContext;
    [context makeCurrentContext];
    NSSize size = [_glView convertRectToBacking:_glView.bounds].size;
    if (!NSEqualSizes(size, _drawableSize) && size.width >= 1 && size.height >= 1) {
        _drawableSize = size;
        [context update];
        projectm_set_window_size(_projectM, (size_t)size.width, (size_t)size.height);
    }
    projectm_opengl_render_frame(_projectM);
    [context flushBuffer];
}

@end

#pragma clang diagnostic pop
