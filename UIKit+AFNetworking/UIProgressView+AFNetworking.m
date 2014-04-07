// UIProgressView+AFNetworking.m
//
// Copyright (c) 2013-2014 AFNetworking (http://afnetworking.com)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "UIProgressView+AFNetworking.h"

#import <objc/runtime.h>

#if defined(__IPHONE_OS_VERSION_MIN_REQUIRED)

#import "AFURLConnectionOperation.h"

#if __IPHONE_OS_VERSION_MIN_REQUIRED >= 70000
#import "AFURLSessionManager.h"
#endif

static void * AFTaskCountOfBytesSentContext = &AFTaskCountOfBytesSentContext;
static void * AFTaskCountOfBytesReceivedContext = &AFTaskCountOfBytesReceivedContext;

@interface AFURLConnectionOperation (_UIProgressView)
@property (readwrite, nonatomic, copy) void (^uploadProgress)(NSUInteger bytes, long long totalBytes, long long totalBytesExpected);

@property (readwrite, nonatomic, copy) void (^downloadProgress)(NSUInteger bytes, long long totalBytes, long long totalBytesExpected);
@end

@implementation AFURLConnectionOperation (_UIProgressView)
@dynamic uploadProgress; // Implemented in AFURLConnectionOperation

@dynamic downloadProgress; // Implemented in AFURLConnectionOperation
@end

@interface AFTaskProgressObserver : NSObject
@property (readonly, nonatomic, weak) UIProgressView *progressView;
@property (readonly, nonatomic, assign) BOOL animated;

- (instancetype)initWithProgressView:(UIProgressView *)progressView animated:(BOOL)animated;
@end

#pragma mark -

@implementation UIProgressView (AFNetworking)

#if __IPHONE_OS_VERSION_MIN_REQUIRED >= 70000
- (void)setProgressWithUploadProgressOfTask:(NSURLSessionUploadTask *)task
                                   animated:(BOOL)animated
{
    AFTaskProgressObserver *taskProgressObserver = [[AFTaskProgressObserver alloc] initWithProgressView:self animated:animated];
    [task addObserver:taskProgressObserver forKeyPath:@"state" options:0 context:AFTaskCountOfBytesSentContext];
    [task addObserver:taskProgressObserver forKeyPath:@"countOfBytesSent" options:0 context:AFTaskCountOfBytesSentContext];
}

- (void)setProgressWithDownloadProgressOfTask:(NSURLSessionDownloadTask *)task
                                     animated:(BOOL)animated
{
    AFTaskProgressObserver *taskProgressObserver = [[AFTaskProgressObserver alloc] initWithProgressView:self animated:animated];
    [task addObserver:taskProgressObserver forKeyPath:@"state" options:0 context:AFTaskCountOfBytesReceivedContext];
    [task addObserver:taskProgressObserver forKeyPath:@"countOfBytesReceived" options:0 context:AFTaskCountOfBytesReceivedContext];
}
#endif

#pragma mark -

- (void)setProgressWithUploadProgressOfOperation:(AFURLConnectionOperation *)operation
                                        animated:(BOOL)animated
{
    __weak __typeof(self)weakSelf = self;
    void (^original)(NSUInteger bytesWritten, long long totalBytesWritten, long long totalBytesExpectedToWrite) = [operation.uploadProgress copy];
    [operation setUploadProgressBlock:^(NSUInteger bytesWritten, long long totalBytesWritten, long long totalBytesExpectedToWrite) {
        if (original) {
            original(bytesWritten, totalBytesWritten, totalBytesExpectedToWrite);
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (totalBytesExpectedToWrite > 0) {
                __strong __typeof(weakSelf)strongSelf = weakSelf;
                [strongSelf setProgress:(totalBytesWritten / (totalBytesExpectedToWrite * 1.0f)) animated:animated];
            }
        });
    }];
}

- (void)setProgressWithDownloadProgressOfOperation:(AFURLConnectionOperation *)operation
                                          animated:(BOOL)animated
{
    __weak __typeof(self)weakSelf = self;
    void (^original)(NSUInteger bytesRead, long long totalBytesRead, long long totalBytesExpectedToRead) = [operation.downloadProgress copy];
    [operation setDownloadProgressBlock:^(NSUInteger bytesRead, long long totalBytesRead, long long totalBytesExpectedToRead) {
        if (original) {
            original(bytesRead, totalBytesRead, totalBytesExpectedToRead);
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (totalBytesExpectedToRead > 0) {
                __strong __typeof(weakSelf)strongSelf = weakSelf;
                [strongSelf setProgress:(totalBytesRead / (totalBytesExpectedToRead  * 1.0f)) animated:animated];
            }
        });
    }];
}

@end

#pragma mark - NSKeyValueObserving

@implementation AFTaskProgressObserver

- (instancetype)initWithProgressView:(UIProgressView *)progressView animated:(BOOL)animated {
    self = [super init];
    if (!self) {
        return nil;
    }
    
    _progressView = progressView;
    _animated = animated;
    
    return self;
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(__unused NSDictionary *)change
                       context:(void *)context
{
#if __IPHONE_OS_VERSION_MIN_REQUIRED >= 70000
    if (context == AFTaskCountOfBytesSentContext || context == AFTaskCountOfBytesReceivedContext) {
        if ([keyPath isEqualToString:NSStringFromSelector(@selector(countOfBytesSent))]) {
            if ([object countOfBytesExpectedToSend] > 0) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    UIProgressView *progressView = self.progressView;
                    [progressView setProgress:[object countOfBytesSent] / ([object countOfBytesExpectedToSend] * 1.0f) animated:self.animated];
                });
            }
        }

        if ([keyPath isEqualToString:NSStringFromSelector(@selector(countOfBytesReceived))]) {
            if ([object countOfBytesExpectedToReceive] > 0) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    UIProgressView *progressView = self.progressView;
                    [progressView setProgress:[object countOfBytesReceived] / ([object countOfBytesExpectedToReceive] * 1.0f) animated:self.animated];
                });
            }
        }

        if ([keyPath isEqualToString:NSStringFromSelector(@selector(state))]) {
            if ([(NSURLSessionTask *)object state] == NSURLSessionTaskStateCompleted) {
                @try {
                    [object removeObserver:self forKeyPath:NSStringFromSelector(@selector(state))];

                    if (context == AFTaskCountOfBytesSentContext) {
                        [object removeObserver:self forKeyPath:NSStringFromSelector(@selector(countOfBytesSent))];
                    }

                    if (context == AFTaskCountOfBytesReceivedContext) {
                        [object removeObserver:self forKeyPath:NSStringFromSelector(@selector(countOfBytesReceived))];
                    }
                }
                @catch (NSException * __unused exception) {}
            }
        }
    }
#endif
}

@end

#endif
