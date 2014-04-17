//
//  PSCRotatePagesWithGestureExample.m
//  PSPDFCatalog-static
//
//  Created by Peter Steinberger on 21/02/14.
//  Copyright (c) 2014 PSPDFKit GmbH. All rights reserved.
//

#import "PSCExample.h"
#import "PSCAssetLoader.h"

@interface PSCRotatablePDFViewController : PSPDFViewController @end

@interface PSCRotatePagesWithGestureExample : PSCExample @end
@implementation PSCRotatePagesWithGestureExample

- (id)init {
    if (self = [super init]) {
        self.title = @"Rotate PDF pages";
        self.contentDescription = @"Use a UIRotationGestureRecognizer to rotate pages.";
        self.category = PSCExampleCategoryViewCustomization;
        self.priority = 60;
    }
    return self;
}

- (UIViewController *)invokeWithDelegate:(id<PSCExampleRunnerDelegate>)delegate {
    // Set up the document.
    PSPDFDocument *document = [PSCAssetLoader sampleDocumentWithName:kHackerMagazineExample];

    // And also the controller.
    PSPDFViewController *pdfController = [[PSCRotatablePDFViewController alloc] initWithDocument:document];
    return pdfController;
}

@end

@interface PSCRotatableScrollView : PSPDFScrollView @end

@implementation PSCRotatablePDFViewController

///////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - PSPDFViewController

- (void)commonInitWithDocument:(PSPDFDocument *)document {
    [super commonInitWithDocument:document];

    // prevents page flashing when there's cached content available at the cost of slight main thread blocking.
    self.renderingMode = PSPDFPageRenderingModeFullPageBlocking;

    // Optional: Allow rotation via a gesture.
    [self overrideClass:PSPDFScrollView.class withClass:PSCRotatableScrollView.class];

    // Add manual rotation button.
    UIBarButtonItem *rotate = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemReply target:self action:@selector(rotateAction:)];
    self.leftBarButtonItems = @[rotate];
    self.navigationItem.leftItemsSupplementBackButton = YES;
}

///////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Private

static NSUInteger PSCNormalizeRotation(NSInteger rotation) {
    rotation %= 360;
    while (rotation < 0) rotation += 360;

    // correct weird rotation values. (Only 0, 90, 180, 270 are allowed)
    if (rotation % 90 != 0) {
        if (rotation < 45) rotation = 0;
        else if (rotation < 135) rotation = 90;
        else if (rotation < 225) rotation = 180;
        else if (rotation < 315) rotation = 270;
        else rotation = 0;
    }
    return rotation;
}

- (void)rotateAction:(id)sender {
    // We need to invalidate the cache of the current page.
    [PSPDFCache.sharedCache invalidateImageFromDocument:self.document page:self.page];

    // rotate 90 degree counter-clock-wise (and make sure we don't set something >= 360)
    BOOL rotateAll = NO;
    if (rotateAll) {
        for (NSUInteger pageIndex=0; pageIndex < self.document.pageCount; pageIndex++) {
            PSPDFPageInfo *pageInfo = [self.document pageInfoForPage:pageIndex];
            PSPDFPageInfo *newPageInfo = [[PSPDFPageInfo alloc] initWithPage:pageInfo.page rect:pageInfo.pageRect rotation:PSCNormalizeRotation(pageInfo.pageRotation - 90) documentProvider:pageInfo.documentProvider];
            [self.document setPageInfo:newPageInfo forPage:pageIndex];
        }
    }else {
        PSPDFPageInfo *pageInfo = [self.document pageInfoForPage:self.page];
        PSPDFPageInfo *newPageInfo = [[PSPDFPageInfo alloc] initWithPage:pageInfo.page rect:pageInfo.pageRect rotation:PSCNormalizeRotation(pageInfo.pageRotation - 90) documentProvider:pageInfo.documentProvider];
        [self.document setPageInfo:newPageInfo forPage:self.page];
    }

    // Request an immediate rendering of the current page, will block the main thread but prevent flashing.
    [PSPDFCache.sharedCache imageFromDocument:self.document page:self.page size:self.view.frame.size options:PSPDFCacheOptionSizeRequireExact|PSPDFCacheOptionDiskLoadSkip|PSPDFCacheOptionRenderSync];

    // reload the controller
    [self reloadData];
}

@end

///////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - PSPDFRotatableScrollView

@implementation PSCRotatableScrollView

- (id)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        // Add page rotation gesture.
        UIRotationGestureRecognizer *rotationGesture = [[UIRotationGestureRecognizer alloc] initWithTarget:self action:@selector(handleRotation:)];
        rotationGesture.delegate = self;
        [self addGestureRecognizer:rotationGesture];
    }
    return self;
}

#define PSCRadiansToDegrees(degrees) ((CGFloat)degrees * (180.f / (CGFloat)M_PI))

- (void)handleRotation:(UIRotationGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer.state == UIGestureRecognizerStateEnded) {
        // Invalidate the cache.
        [PSPDFCache.sharedCache invalidateImageFromDocument:self.document page:self.page];

        // Get rotation and snap to the closest position.
        PSPDFPageInfo *pageInfo = [self.document pageInfoForPage:self.page];
        NSUInteger degrees = (NSUInteger)PSCRadiansToDegrees(atan2(self.transform.b, self.transform.a));
        PSPDFPageInfo *newPageInfo = [[PSPDFPageInfo alloc] initWithPage:pageInfo.page rect:pageInfo.pageRect rotation:PSCNormalizeRotation(pageInfo.pageRotation + degrees) documentProvider:pageInfo.documentProvider];
        [self.document setPageInfo:newPageInfo forPage:pageInfo.page];
        PSCLog(@"Snap rotation to: %tu", pageInfo.pageRotation);

        // Request an immediate rendering, will block the main thread but prevent flashing.
        PSPDFViewController *pdfController = self.pdfController;
        [PSPDFCache.sharedCache imageFromDocument:self.document page:self.page size:pdfController.view.frame.size options:PSPDFCacheOptionSizeRequireExact|PSPDFCacheOptionDiskLoadSkip|PSPDFCacheOptionRenderSync];

        // Reset view and reload the controller. (this is efficient and will re-use views)
        gestureRecognizer.view.transform = CGAffineTransformIdentity;
        [pdfController reloadData];
    }else {
        // Transform the current view.
        gestureRecognizer.view.transform = CGAffineTransformRotate(gestureRecognizer.view.transform, gestureRecognizer.rotation);
        gestureRecognizer.rotation = 0;
    }
}

// Allow zooming and rotating at the same time.
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    if ([gestureRecognizer isKindOfClass:[UIRotationGestureRecognizer class]]) return YES;
    return [super gestureRecognizer:gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:otherGestureRecognizer];
}

@end