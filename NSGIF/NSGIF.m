//
//  NSGIF.m
//  
//  Created by Sebastian Dobrincu
//

#import "NSGIF.h"

@implementation NSGIF

// Declare constants
#define fileName     @"NSGIF.gif"
#define timeInterval @(600)
#define tolerance    @(0.01)

typedef NS_ENUM(NSInteger, GIFSize) {
    GIFSizeVeryLow  = 2,
    GIFSizeLow      = 3,
    GIFSizeMedium   = 5,
    GIFSizeHigh     = 7,
    GIFSizeOriginal = 10
};

#pragma mark - Public methods

+ (void)optimalGIFfromURL:(NSURL*)videoURL loopCount:(int)loopCount size:(CGSize)size completion:(void(^)(NSURL *GifURL))completionBlock {

    int delayTime = 0.2;
    
    // Create properties dictionaries
    NSDictionary *fileProperties = [self filePropertiesWithLoopCount:loopCount];
    NSDictionary *frameProperties = [self framePropertiesWithDelayTime:delayTime];
    
    AVURLAsset *asset = [AVURLAsset assetWithURL:videoURL];
    
    float videoWidth = [[[asset tracksWithMediaType:AVMediaTypeVideo] objectAtIndex:0] naturalSize].width;
    float videoHeight = [[[asset tracksWithMediaType:AVMediaTypeVideo] objectAtIndex:0] naturalSize].height;
    
    GIFSize optimalSize = GIFSizeMedium;
    if (videoWidth >= 1200 || videoHeight >= 1200)
        optimalSize = GIFSizeVeryLow;
    else if (videoWidth >= 800 || videoHeight >= 800)
        optimalSize = GIFSizeLow;
    else if (videoWidth >= 400 || videoHeight >= 400)
        optimalSize = GIFSizeMedium;
    else if (videoWidth < 400|| videoHeight < 400)
        optimalSize = GIFSizeHigh;
    
    // Get the length of the video in seconds
    float videoLength = (float)asset.duration.value/asset.duration.timescale;
    int framesPerSecond = 4;
    int frameCount = videoLength*framesPerSecond;
    
    // How far along the video track we want to move, in seconds.
    float increment = (float)videoLength/frameCount;
    
    // Add frames to the buffer
    NSMutableArray *timePoints = [NSMutableArray array];
    for (int currentFrame = 0; currentFrame<frameCount; ++currentFrame) {
        float seconds = (float)increment * currentFrame;
        CMTime time = CMTimeMakeWithSeconds(seconds, [timeInterval intValue]);
        [timePoints addObject:[NSValue valueWithCMTime:time]];
    }
    
    // Prepare group for firing completion block
    dispatch_group_t gifQueue = dispatch_group_create();
    dispatch_group_enter(gifQueue);
    
    __block NSURL *gifURL;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
        gifURL = [self createGIFforTimePoints:timePoints fromURL:videoURL fileProperties:fileProperties frameProperties:frameProperties frameCount:frameCount contentMode:UIViewContentModeScaleAspectFit gifSize:size];
        
        dispatch_group_leave(gifQueue);
    });
    
    dispatch_group_notify(gifQueue, dispatch_get_main_queue(), ^{
        // Return GIF URL
        completionBlock(gifURL);
    });

}

+ (void)createGIFfromURL:(NSURL*)videoURL withFrameCount:(int)frameCount maxDuration:(NSTimeInterval)maxDuration delayTime:(int)delayTime rotate:(BOOL)rotate loopCount:(int)loopCount size:(CGSize)size contentMode:(UIViewContentMode)contentMode completion:(void(^)(NSURL *GifURL))completionBlock {
    
    // Convert the video at the given URL to a GIF, and return the GIF's URL if it was created.
    // The frames are spaced evenly over the video, and each has the same duration.
    // delayTime is the amount of time for each frame in the GIF.
    // loopCount is the number of times the GIF will repeat. Defaults to 0, which means repeat infinitely.
    
    // Create properties dictionaries
    NSDictionary *fileProperties = [self filePropertiesWithLoopCount:loopCount];
    NSDictionary *frameProperties = [self framePropertiesWithDelayTime:delayTime];
    
    AVURLAsset *asset = [AVURLAsset assetWithURL:videoURL];

    // Get the length of the video in seconds
    float videoLength = (float)asset.duration.value/asset.duration.timescale;
    
    // How far along the video track we want to move, in seconds.
    float increment = (float)MIN(maxDuration, videoLength)/frameCount;
    
    // Add frames to the buffer
    NSMutableArray *timePoints = [NSMutableArray array];
    for (int currentFrame = 0; currentFrame<frameCount; ++currentFrame) {
        float seconds = (float)increment * currentFrame;
        CMTime time = CMTimeMakeWithSeconds(seconds, [timeInterval intValue]);
        [timePoints addObject:[NSValue valueWithCMTime:time]];
    }
    if (rotate) {
        
        for (int currentFrame = frameCount-1; currentFrame>0; --currentFrame) {
            float seconds = (float)increment * currentFrame;
            CMTime time = CMTimeMakeWithSeconds(seconds, [timeInterval intValue]);
            [timePoints addObject:[NSValue valueWithCMTime:time]];
        }
    }

    // Prepare group for firing completion block
    dispatch_group_t gifQueue = dispatch_group_create();
    dispatch_group_enter(gifQueue);
    
    __block NSURL *gifURL;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
        gifURL = [self createGIFforTimePoints:timePoints fromURL:videoURL fileProperties:fileProperties frameProperties:frameProperties frameCount:(int)timePoints.count contentMode:contentMode gifSize:size];

        dispatch_group_leave(gifQueue);
    });
    
    dispatch_group_notify(gifQueue, dispatch_get_main_queue(), ^{
        // Return GIF URL
        completionBlock(gifURL);
    });
    
}

#pragma mark - Base methods

+ (NSURL *)createGIFforTimePoints:(NSArray *)timePoints fromURL:(NSURL *)url fileProperties:(NSDictionary *)fileProperties frameProperties:(NSDictionary *)frameProperties frameCount:(int)frameCount contentMode:(UIViewContentMode)contentMode gifSize:(CGSize)gifSize{
    
    NSString *temporaryFile = [NSTemporaryDirectory() stringByAppendingString:fileName];
    NSURL *fileURL = [NSURL fileURLWithPath:temporaryFile];
    CGImageDestinationRef destination = CGImageDestinationCreateWithURL((__bridge CFURLRef)fileURL, kUTTypeGIF , frameCount, NULL);
    
    if (fileURL == nil)
        return nil;

    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
    AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
    generator.appliesPreferredTrackTransform = YES;
    
    CMTime tol = CMTimeMakeWithSeconds([tolerance floatValue], [timeInterval intValue]);
    generator.requestedTimeToleranceBefore = tol;
    generator.requestedTimeToleranceAfter = tol;
    
    NSError *error = nil;
    int missingImage = 0;
    NSMutableDictionary* timePointImage = [NSMutableDictionary dictionary];
    CGImageRef lastImageRef = NULL;
    for (NSValue *time in timePoints) {
        CMTime t = [time CMTimeValue];
        CGImageRef imageRef = (__bridge CGImageRef)([timePointImage objectForKey:@(t.value)]);
        if(!imageRef){
            imageRef = ResizedImage([generator copyCGImageAtTime:t actualTime:nil error:&error], gifSize, contentMode);
            if(!imageRef){
                NSLog(@"Error generating frame: %f %@", t, error);
                missingImage ++;
                continue;
            }
            [timePointImage setObject:(__bridge id _Nonnull)(imageRef) forKey:@(t.value)];
        }
        if (error) {
            NSLog(@"Error copying image: %@", error);
        }
        lastImageRef = imageRef;
        CGImageDestinationAddImage(destination, imageRef, (CFDictionaryRef)frameProperties);
    }
    
    for(int i=0;i<missingImage;i++){
        if(!lastImageRef) return nil;
        
        CGImageDestinationAddImage(destination, lastImageRef, (CFDictionaryRef)frameProperties);
    }
    
    for (id key in [timePointImage allKeys]) {
        CGImageRef imageRef = (__bridge CGImageRef)([timePointImage objectForKey:key]);
        CGImageRelease(imageRef);
    }
    [timePointImage removeAllObjects];
    
    CGImageDestinationSetProperties(destination, (CFDictionaryRef)fileProperties);
    // Finalize the GIF
    if (!CGImageDestinationFinalize(destination)) {
        NSLog(@"Failed to finalize GIF destination: %@", error);
        return nil;
    }
    CFRelease(destination);
    
    return fileURL;
}

#pragma mark - Helpers

CGImageRef ResizedImage(CGImageRef imageRef, CGSize sizeLimit, UIViewContentMode contentMode) {


    #if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR
    CGSize imageSize = CGSizeMake(CGImageGetWidth(imageRef), CGImageGetHeight(imageRef));
    CGSize newSize;
    if (contentMode == UIViewContentModeScaleAspectFit) {
        
        if ((imageSize.width <= sizeLimit.width && imageSize.height <= sizeLimit.height) || imageSize.width == 0 || imageSize.height == 0) {
            return imageRef;
        }
        if (imageSize.width / imageSize.height > sizeLimit.width / sizeLimit.height) {
            CGFloat height = sizeLimit.width / imageSize.width * imageSize.height;
            newSize = CGSizeMake(sizeLimit.width, height);
        }else{
            CGFloat width = sizeLimit.height / imageSize.height * imageSize.width;
            newSize = CGSizeMake(width, sizeLimit.height);
        }
    }else if(contentMode == UIViewContentModeScaleAspectFill){
        // TODO
        newSize = sizeLimit;
    }else {
        if ((imageSize.width <= sizeLimit.width && sizeLimit.height <= newSize.height) || sizeLimit.width == 0 || imageSize.height == 0) {
            return imageRef;
        }
        // stretch
        newSize = sizeLimit;
    }
    UIGraphicsBeginImageContextWithOptions(newSize, NO, 1);
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (!context) {
        return nil;
    }
    
    // Set the quality level to use when rescaling
    CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
    CGAffineTransform flipVertical = CGAffineTransformMake(1, 0, 0, -1, 0, newSize.height);
    
    CGContextConcatCTM(context, flipVertical);
    CGRect drawRect;
    if (contentMode == UIViewContentModeScaleAspectFit) {
        drawRect = CGRectMake(0, 0, newSize.width, newSize.height);
    }else if(contentMode == UIViewContentModeScaleAspectFill){
        
        // TODO
        
        drawRect = CGRectMake(0, 0, newSize.width, newSize.height);
    }else {
        // stretch
        drawRect = CGRectMake(0, 0, newSize.width, newSize.height);
    }
    
    CGContextDrawImage(context, drawRect, imageRef);
    
    //Release old image
    CFRelease(imageRef);
    // Get the resized image from the context and a UIImage
    imageRef = CGBitmapContextCreateImage(context);
    
    UIGraphicsEndImageContext();
    #endif
    
    return imageRef;
}

#pragma mark - Properties

+ (NSDictionary *)filePropertiesWithLoopCount:(int)loopCount {
    return @{(NSString *)kCGImagePropertyGIFDictionary:
                @{(NSString *)kCGImagePropertyGIFLoopCount: @(loopCount)}
             };
}

+ (NSDictionary *)framePropertiesWithDelayTime:(int)delayTime {

    return @{(NSString *)kCGImagePropertyGIFDictionary:
                @{(NSString *)kCGImagePropertyGIFDelayTime: @(delayTime)},
                (NSString *)kCGImagePropertyColorModel:(NSString *)kCGImagePropertyColorModelRGB
            };
}

@end
