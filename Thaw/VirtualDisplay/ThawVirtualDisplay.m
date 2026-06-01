//
//  ThawVirtualDisplay.m
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

#import "ThawVirtualDisplay.h"

// Private CoreGraphics interfaces (CGVirtualDisplay*), declared locally. The
// classes are resolved at runtime via NSClassFromString and the whole creation
// path is wrapped in @try/@catch, so a missing class or a renamed selector
// degrades to NULL instead of crashing the app. These are the long-standing
// symbol/property names used by tools such as BetterDisplay.
@interface CGVirtualDisplayDescriptor : NSObject
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) NSUInteger maxPixelsWide;
@property (nonatomic, assign) NSUInteger maxPixelsHigh;
@property (nonatomic, assign) CGSize sizeInMillimeters;
@property (nonatomic, assign) uint32_t productID;
@property (nonatomic, assign) uint32_t vendorID;
@property (nonatomic, assign) uint32_t serialNum;
@end

@interface CGVirtualDisplayMode : NSObject
- (instancetype)initWithWidth:(NSUInteger)width
                       height:(NSUInteger)height
                  refreshRate:(double)refreshRate;
@end

@interface CGVirtualDisplaySettings : NSObject
@property (nonatomic, assign) NSUInteger hiDPI;
@property (nonatomic, copy) NSArray<CGVirtualDisplayMode *> *modes;
@end

@interface CGVirtualDisplay : NSObject
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
@property (nonatomic, readonly) uint32_t displayID;
@end

void *ThawVirtualDisplayCreate(void) {
    Class descriptorClass = NSClassFromString(@"CGVirtualDisplayDescriptor");
    Class settingsClass = NSClassFromString(@"CGVirtualDisplaySettings");
    Class modeClass = NSClassFromString(@"CGVirtualDisplayMode");
    Class displayClass = NSClassFromString(@"CGVirtualDisplay");
    if (!descriptorClass || !settingsClass || !modeClass || !displayClass) {
        NSLog(@"[ThawVirtualDisplay] CGVirtualDisplay classes unavailable; cannot create");
        return NULL;
    }

    @try {
        const NSUInteger width = 1920;
        const NSUInteger height = 1080;

        CGVirtualDisplayDescriptor *descriptor = [[descriptorClass alloc] init];
        descriptor.queue = dispatch_get_main_queue();
        descriptor.name = @"Thaw Resolver";
        descriptor.maxPixelsWide = width;
        descriptor.maxPixelsHigh = height;
        descriptor.sizeInMillimeters = CGSizeMake(600.0, 340.0);
        descriptor.productID = 0x1234;
        descriptor.vendorID = 0x3456;
        descriptor.serialNum = 0x0001;

        CGVirtualDisplay *display = [[displayClass alloc] initWithDescriptor:descriptor];
        if (!display) {
            NSLog(@"[ThawVirtualDisplay] initWithDescriptor returned nil");
            return NULL;
        }

        CGVirtualDisplayMode *mode = [[modeClass alloc] initWithWidth:width
                                                               height:height
                                                          refreshRate:60.0];
        if (!mode) {
            NSLog(@"[ThawVirtualDisplay] mode init returned nil");
            return NULL;
        }

        CGVirtualDisplaySettings *settings = [[settingsClass alloc] init];
        settings.hiDPI = 0;
        settings.modes = @[mode];

        if (![display applySettings:settings]) {
            NSLog(@"[ThawVirtualDisplay] applySettings failed");
            return NULL;
        }

        // Retain across the C boundary; ThawVirtualDisplayDestroy releases it,
        // and deallocating the CGVirtualDisplay removes the display.
        return (void *)CFBridgingRetain(display);
    } @catch (NSException *exception) {
        NSLog(@"[ThawVirtualDisplay] creation raised %@: %@", exception.name, exception.reason);
        return NULL;
    }
}

uint32_t ThawVirtualDisplayGetID(void *handle) {
    if (!handle) {
        return 0;
    }
    @try {
        CGVirtualDisplay *display = (__bridge CGVirtualDisplay *)handle;
        return display.displayID;
    } @catch (NSException *exception) {
        return 0;
    }
}

void ThawVirtualDisplayDestroy(void *handle) {
    if (!handle) {
        return;
    }
    // Transfers ownership back to ARC and releases; dealloc removes the display.
    CFBridgingRelease(handle);
}
