//
//  MIT License
//
//  Copyright (c) 2014 Bob McCune http://bobmccune.com/
//  Copyright (c) 2014 TapHarmonic, LLC http://tapharmonic.com/
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

#import "THCameraController.h"
#import <AVFoundation/AVFoundation.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import "NSFileManager+THAdditions.h"

NSString *const THThumbnailCreatedNotification = @"THThumbnailCreated";

@interface THCameraController () <AVCaptureFileOutputRecordingDelegate>

@property (strong, nonatomic) dispatch_queue_t videoQueue;
@property (strong, nonatomic) AVCaptureSession *captureSession;
@property (weak, nonatomic) AVCaptureDeviceInput *activeVideoInput;
@property (strong, nonatomic) AVCaptureStillImageOutput *imageOutput;
@property (strong, nonatomic) AVCaptureMovieFileOutput *movieOutput;
@property (strong, nonatomic) NSURL *outputURL;

@end

@implementation THCameraController

- (BOOL)setupSession:(NSError **)error {
    // 1. Create the capture session
    self.captureSession = [[AVCaptureSession alloc] init];
    self.captureSession.sessionPreset = AVCaptureSessionPresetHigh;

    // 2. Get a pointer to the *default* video capture device (usually back-facing cam)
    AVCaptureDevice *videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];

    // 3. Need to wrap device in a device input before you can add it to the capture session
    AVCaptureDeviceInput *videoInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:error];

    // 4. If you get a valid input back you need to check that you can add it. If it's not valid, fail.
    if (videoInput) {
        if ([self.captureSession canAddInput:videoInput]) {
            [self.captureSession addInput:videoInput];
            self.activeVideoInput = videoInput;
        }
    } else {
        return NO;
    }

    // 5. Do the same thing we did for default audio device
    AVCaptureDevice *audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    // 6. Wrap it in an input
    AVCaptureDeviceInput *audioInput = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice error:error];
    // 7. Make sure it's valid, otherwise fail.
    if (audioInput) {
        if ([self.captureSession canAddInput:audioInput]) {
            [self.captureSession addInput:audioInput];
        }
    } else {
        return NO;
    }

    // 8. Create a still image output to capture still images from cam
    self.imageOutput = [[AVCaptureStillImageOutput alloc] init];
    self.imageOutput.outputSettings = @{AVVideoCodecKey: AVVideoCodecJPEG};
    if ([self.captureSession canAddOutput:self.imageOutput]) {
        [self.captureSession addOutput:self.imageOutput];
    }

    // 9. Create a movie output to capture videos
    self.movieOutput = [[AVCaptureMovieFileOutput alloc] init];
    if ([self.captureSession canAddOutput: self.movieOutput]) {
        [self.captureSession addOutput:self.movieOutput];
    }

    self.videoQueue = dispatch_queue_create("com.tapharmonic.VideoQueue", NULL);

    return YES;
}

- (void)startSession {

    if (![self.captureSession isRunning]) {
        dispatch_async(self.videoQueue, ^{
            [self.captureSession startRunning];
        });
    }
}

- (void)stopSession {
    if ([self.captureSession isRunning]) {
        dispatch_async(self.videoQueue, ^{
            [self.captureSession stopRunning];
        });
    }
}

#pragma mark - Device Configuration

- (AVCaptureDevice *)cameraWithPosition:(AVCaptureDevicePosition)position {

    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for (AVCaptureDevice *device in devices) {
        if (device.position == position) {
            return device;
        }
    }
    return nil;
}

- (AVCaptureDevice *)activeCamera {

    return self.activeVideoInput.device;
}

- (AVCaptureDevice *)inactiveCamera {

    AVCaptureDevice *device = nil;
    if (self.cameraCount > 1) {
        if ([self activeCamera].position == AVCaptureDevicePositionBack) {
            device = [self cameraWithPosition:AVCaptureDevicePositionFront];
        } else {
            device = [self cameraWithPosition:AVCaptureDevicePositionBack];
        }
    }
    return device;
}

- (BOOL)canSwitchCameras {

    return self.cameraCount > 1;
}

- (NSUInteger)cameraCount {

    return [[AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo] count];
}

- (BOOL)switchCameras {
    if (![self canSwitchCameras]) {
        return NO;
    }

    NSError *error;
    AVCaptureDevice *videoDevice = [self inactiveCamera];
    AVCaptureDeviceInput *videoInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:&error];
    if (videoInput) {
        [self.captureSession beginConfiguration];
        [self.captureSession removeInput:self.activeVideoInput];
        if ([self.captureSession canAddInput:videoInput]) {
            [self.captureSession addInput:videoInput];
            self.activeVideoInput = videoInput;
        } else {
            [self.captureSession addInput:self.activeVideoInput];
        }

        [self.captureSession commitConfiguration];
        return YES;
    } else {
        [self.delegate deviceConfigurationFailedWithError:error];
        return NO;
    }
}

#pragma mark - Focus Methods

- (BOOL)cameraSupportsTapToFocus {
    
    return [[self activeCamera] isFocusPointOfInterestSupported];
}

- (void)focusAtPoint:(CGPoint)point {
    
    AVCaptureDevice *device = [self activeCamera];
    if (device.isFocusPointOfInterestSupported && [device isFocusModeSupported:AVCaptureFocusModeAutoFocus]) {
        NSError *error;
        if ([device lockForConfiguration:&error]) {
            device.focusPointOfInterest = point;
            device.focusMode = AVCaptureFocusModeAutoFocus;
            [device unlockForConfiguration];
        } else {
            [self.delegate deviceConfigurationFailedWithError:error];
        }
    }
    
}

#pragma mark - Exposure Methods

- (BOOL)cameraSupportsTapToExpose {
    return [[self activeCamera] isExposurePointOfInterestSupported];
}

static const NSString *THCameraAdjustingExposureContext;

- (void)exposeAtPoint:(CGPoint)point {

    AVCaptureDevice *device = [self activeCamera];
    AVCaptureExposureMode exposureMode = AVCaptureExposureModeContinuousAutoExposure;
    if (device.isExposurePointOfInterestSupported && [device isExposureModeSupported:exposureMode]) {
        NSError *error;
        if ([device lockForConfiguration:&error]) {
            device.exposurePointOfInterest = point;
            device.exposureMode = exposureMode;
            if ([device isExposureModeSupported:AVCaptureExposureModeLocked]) {
                // 4. Determine when the exposure adjustment has completed, letting you lock exposure at that point
                [device addObserver:self forKeyPath:@"adjusting-Exposure" options:NSKeyValueObservingOptionNew context:&THCameraAdjustingExposureContext];
            }
        }
    }

}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {

    if (context == &THCameraAdjustingExposureContext) {
        AVCaptureDevice *device = (AVCaptureDevice *)object;
        if (!device.isAdjustingExposure && [device isExposureModeSupported:AVCaptureExposureModeLocked]) {
            [object removeObserver:self forKeyPath:@"adjusting-Exposure" context:&THCameraAdjustingExposureContext];
            // vvv needs to be async so that there's time for removeObserver to do its thing
            dispatch_async(dispatch_get_main_queue(), ^{
                NSError *error;
                if (![device lockForConfiguration:&error]) {
                    device.exposureMode = AVCaptureExposureModeLocked;
                    [device unlockForConfiguration];
                } else {
                    [self.delegate deviceConfigurationFailedWithError:error];
                }
            });
        }
    }

}

- (void)resetFocusAndExposureModes {

    // Listing 6.10

}



#pragma mark - Flash and Torch Modes

- (BOOL)cameraHasFlash {

    // Listing 6.11
    
    return NO;
}

- (AVCaptureFlashMode)flashMode {

    // Listing 6.11
    
    return 0;
}

- (void)setFlashMode:(AVCaptureFlashMode)flashMode {

    // Listing 6.11

}

- (BOOL)cameraHasTorch {

    // Listing 6.11
    
    return NO;
}

- (AVCaptureTorchMode)torchMode {

    // Listing 6.11
    
    return 0;
}

- (void)setTorchMode:(AVCaptureTorchMode)torchMode {

    // Listing 6.11
    
}


#pragma mark - Image Capture Methods

- (void)captureStillImage {

    // Listing 6.12

}

- (AVCaptureVideoOrientation)currentVideoOrientation {
    
    // Listing 6.12
    
    // Listing 6.13
    
    return 0;
}


- (void)writeImageToAssetsLibrary:(UIImage *)image {

    // Listing 6.13
    
}

- (void)postThumbnailNotifification:(UIImage *)image {

    // Listing 6.13
    
}

#pragma mark - Video Capture Methods

- (BOOL)isRecording {

    // Listing 6.14
    
    return NO;
}

- (void)startRecording {

    // Listing 6.14

}

- (CMTime)recordedDuration {
    return self.movieOutput.recordedDuration;
}

- (NSURL *)uniqueURL {


    // Listing 6.14
    
    return nil;
}

- (void)stopRecording {

    // Listing 6.14
}

#pragma mark - AVCaptureFileOutputRecordingDelegate

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput
didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL
      fromConnections:(NSArray *)connections
                error:(NSError *)error {

    // Listing 6.15

}

- (void)writeVideoToAssetsLibrary:(NSURL *)videoURL {

    // Listing 6.15
    
}

- (void)generateThumbnailForVideoAtURL:(NSURL *)videoURL {

    // Listing 6.15
    
}


@end

