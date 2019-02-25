///////////////////////////////////////////////////////////////
#pragma mark Headers
///////////////////////////////////////////////////////////////

#import "Internal/XIWidgetManager.h"

#import <WebKit/WebKit.h>
#import <objc/runtime.h>

#include <dlfcn.h>

@class WebView;
@class WebScriptObject;

@interface WebFrame : NSObject
- (id)dataSource;
@end

@interface XENHWidgetController : NSObject
// Internal webviews
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) UIWebView *legacyWebView;
@end

@interface WKWebView (Additions)
@property (nonatomic, assign) id<WKNavigationDelegate> hijackedNavigationDelegate;
@property (nonatomic, copy) NSNumber *_xenhtml;
@end

@interface UIWebView (Additions)
@property (nonatomic, assign) id<UIWebViewDelegate> hijackedDelegate;
@property (nonatomic, copy) NSNumber *_xenhtml;
@end


///////////////////////////////////////////////////////////////
#pragma mark Internal Hooks
///////////////////////////////////////////////////////////////

#pragma mark Add Xen HTML (only!) webviews to our widget manager as required.

%hook XENHWidgetController

// WKWebView
 - (void)_unloadWebView {
     WKWebView *widget = self.webView;
     if (widget) {
         NSString *url = [widget.URL absoluteString];
         Xlog(@"Unregistering widget (WKWebView) for URL: %@", url);
         
        [[XIWidgetManager sharedInstance] unregisterWidget:widget];
     }
     
     %orig;
 }
 
 - (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
     %orig;
     
     NSString *url = [webView.URL absoluteString];
     
     if (![url isEqualToString:@""] && ![url isEqualToString:@"about:blank"]) {
         Xlog(@"Registering widget (WKWebView) for URL: %@", url);
         
         webView._xenhtml = @YES;
         [[XIWidgetManager sharedInstance] registerWidget:webView];
     }
 }

// UIWebView
 - (void)_unloadLegacyWebView {
     UIWebView *widget = self.legacyWebView;
     if (widget) {
         NSString *href = [[widget.request URL] absoluteString];
         Xlog(@"Unregistering widget (UIWebView) for href: %@", href);
         
         [[XIWidgetManager sharedInstance] unregisterWidget:widget];
     }
     
     %orig;
 }
 
 - (void)setLegacyWebView:(UIWebView *)arg1 {
     %orig;
 
     if (arg1) {
         arg1._xenhtml = @YES;
     }
 }
 
 %end

// Not using UIWebView delegate, so use a workaround
%hook UIWebView

%property (nonatomic, copy) NSNumber *_xenhtml; // readwrite not supported by my version of theos.

%new
- (void)webViewDidFinishLoad:(UIWebView *)webView {
    if (self.hijackedDelegate) {
        [self.hijackedDelegate webViewDidFinishLoad:webView];
    }
    
    NSString *href = [[self.request URL] absoluteString];
    
    if ([self._xenhtml isEqual:@YES] && href && ![href isEqualToString:@""] && ![href isEqualToString:@"about:blank"]) {
        Xlog(@"Registering widget (UIWebView) for href: %@", href);
        [[XIWidgetManager sharedInstance] registerWidget:self];
    }
}

%end

%hook WKWebView

%property (nonatomic, copy) NSNumber *_xenhtml;

%end

#pragma mark Handle when a webview is deciding to navigate to a new page

// The idea is that we force the WKWebView to become its own navigationDelegate.
// Therefore, we can then intercept any incoming delegate calls as required, then
// forward them to the actual navigationDelegate we hijacked.

%hook WKWebView

%property (nonatomic, assign) id hijackedNavigationDelegate;

- (instancetype)initWithFrame:(CGRect)arg1 configuration:(id)arg2 {
    WKWebView *orig = %orig;
    
    if (orig) {
        // Set the navigationDelegate initially.
        orig.navigationDelegate = (id<WKNavigationDelegate>)orig;
    }
    
    return orig;
}

// Override the navigationDelegate if updated
- (void)setNavigationDelegate:(id)delegate {
    if([delegate isKindOfClass:[objc_getClass("XENHWidgetController") class]]){
        if(![delegate isEqual:self]){
            self.hijackedNavigationDelegate = delegate;
            %orig((id<WKNavigationDelegate>)self);
        }
    }else{
        %orig;
    }
}

// Add appropriate delegate methods, forwarding back to the hijacked navigationDelegate as
// required.

%new
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    
    // Allow other tweaks etc to handle this one.
    if ([self._xenhtml isEqual:@NO]) {
        if (self.hijackedNavigationDelegate) {
            [(id<WKNavigationDelegate>)self.hijackedNavigationDelegate webView:webView decidePolicyForNavigationAction:navigationAction decisionHandler:decisionHandler];
        } else {
            decisionHandler(WKNavigationActionPolicyAllow);
        }
        
        return;
    }
    
    NSURLRequest *request = navigationAction.request;
    NSString *url = [[request URL] absoluteString];
    
    if ([url hasPrefix:@"xeninfo:"]) {
        NSArray *components = [url componentsSeparatedByString:@":"];

        NSString *function = [components objectAtIndex:1];
        
        // Pass through the function and parameters through to the widget manager.
        NSString *parameter = components.count > 2 ? [components objectAtIndex:2] : @"";
        
        Xlog(@"Recieved a command: '%@' with parameter '%@'", function, parameter);
        
        // Send to widget manager.
        [[XIWidgetManager sharedInstance] widget:self didRequestAction:function withParameter:parameter];
        
        // Make sure to cancel this navigation!
        decisionHandler(WKNavigationActionPolicyCancel);
    } else {
        decisionHandler(WKNavigationActionPolicyAllow);
    }
}

%new
- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    if (self.hijackedNavigationDelegate) {
        [(id<WKNavigationDelegate>)self.hijackedNavigationDelegate webView:webView didStartProvisionalNavigation:navigation];
    }
}

%new
- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    if (self.hijackedNavigationDelegate) {
        [(id<WKNavigationDelegate>)self.hijackedNavigationDelegate webView:webView didFailProvisionalNavigation:navigation withError:error];
    }
}

%new
- (void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)navigation {
    if (self.hijackedNavigationDelegate) {
        [(id<WKNavigationDelegate>)self.hijackedNavigationDelegate webView:webView didCommitNavigation:navigation];
    }
}

%new
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    if (self.hijackedNavigationDelegate) {
        [(id<WKNavigationDelegate>)self.hijackedNavigationDelegate webView:webView didFinishNavigation:navigation];
    }
}

%new
- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    if (self.hijackedNavigationDelegate) {
        [(id<WKNavigationDelegate>)self.hijackedNavigationDelegate webView:webView didFailNavigation:navigation withError:error];
    }
}

%new
- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {
    if (self.hijackedNavigationDelegate) {
        [(id<WKNavigationDelegate>)self.hijackedNavigationDelegate webViewWebContentProcessDidTerminate:webView];
    }
}

%end

%hook UIWebView

%property (nonatomic, assign) id hijackedDelegate;

- (id)initWithFrame:(CGRect)arg1 {
    UIWebView *orig = %orig;
    
    if (orig) {
        // Set the delegate initially.
        orig.delegate = (id<UIWebViewDelegate>)orig;
    }
    
    return orig;
}

// Update the hijacked delegate if XEN controller
- (void)setDelegate:(id<UIWebViewDelegate>)delegate {
    if([delegate isKindOfClass:[objc_getClass("XENHWidgetController") class]]){
        if(![delegate isEqual:self]){
            self.hijackedDelegate = delegate;
            %orig((id<UIWebViewDelegate>)self);
        }
    }else{
        %orig;
    }
}

%new
- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType {
    
    // Allow other tweaks etc to handle this one.
    if ([self._xenhtml isEqual:@NO]) {
        if (self.hijackedDelegate) {
            return [self.hijackedDelegate webView:webView shouldStartLoadWithRequest:request navigationType:navigationType];
        } else {
            return YES;
        }
    }
    
    NSString *url = [[request URL] absoluteString];
    
    if ([url hasPrefix:@"xeninfo:"]) {
        NSArray *components = [url componentsSeparatedByString:@":"];
        
        NSString *function = [components objectAtIndex:1];
        
        // Pass through the function and parameters through to the widget manager.
        NSString *parameter = components.count > 2 ? [components objectAtIndex:2] : @"";
        
        Xlog(@"Recieved a command: '%@' with parameter '%@'", function, parameter);
        
        // Send to widget manager.
        [[XIWidgetManager sharedInstance] widget:self didRequestAction:function withParameter:parameter];
        
        // Make sure to cancel this navigation!
        return NO;
    } else {
        return YES;
    }
}

%new
- (void)webViewDidStartLoad:(UIWebView *)webView {
    if (self.hijackedDelegate)
        [self.hijackedDelegate webViewDidStartLoad:webView];
}

%new
- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error {
    if (self.hijackedDelegate)
        [self.hijackedDelegate webView:webView didFailLoadWithError:error];
}

%end

///////////////////////////////////////////////////////////////
#pragma mark Battery Information Hooks
///////////////////////////////////////////////////////////////

#import "Battery/XIInfoStats.h"

%hook SBUIController

- (void)updateBatteryState:(id)arg1{
    %orig;
    
    // Forward message that new data is available
    [[XIWidgetManager sharedInstance] requestRefreshForDataProviderTopic:[XIInfoStats topic]];
}

%end

///////////////////////////////////////////////////////////////
#pragma mark Music Hooks
///////////////////////////////////////////////////////////////

#import "Music/XIMusicHeaders.h"
#import "Music/XIMusic.h"

static MPUNowPlayingController *globalMPUNowPlaying;

/*
    Used for iOS 11 and 11.1.2 not 11.3
*/
static long shuffle;
static long repeat;

%hook MPCPlaybackEngineMiddleware

%new
+(long)getRepeat{
    return repeat;
}

%new
+(long)getShuffle{
    return shuffle;
}

-(long long)playerRepeatType:(long long)arg1 chain:(id)arg2{
    repeat = arg1;
    return %orig;
}
-(long long)playerShuffleType:(long long)arg1 chain:(id)arg2{
    shuffle = arg1;
    return %orig;
}
%end

NSMutableDictionary* xen_metaData = [[NSMutableDictionary alloc] init];

%hook MRContentItem

%new
+(id)_xeninfo_metaData{
    return xen_metaData;
}

-(id)itemMetadata{
    MRContentItemMetadata* meta = %orig;
    if([meta duration] > 0){
        [xen_metaData setValue:[NSNumber numberWithDouble:[meta duration]] forKey:@"duration"];
        [xen_metaData setValue:[NSNumber numberWithDouble:[meta elapsedTime]] forKey:@"elapsed"];
        [xen_metaData setValue:[meta title] forKey:@"title"];
        [xen_metaData setValue:[meta albumName] forKey: @"albumName"];
        [xen_metaData setValue:[meta trackArtistName] forKey: @"artistName"];
    }
    return meta;
}
%end

%hook SBMediaController

/* 
    Note: Delay needed othewise info isn't correct
    Example: If you press pause it will still say isPlaying.
*/

- (void)_nowPlayingInfoChanged{
    %orig;
    dispatch_time_t delay = dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC * 0.5);
    dispatch_after(delay, dispatch_get_main_queue(), ^(void){
        // Forward message that new data is available after delay
        [[XIWidgetManager sharedInstance] requestRefreshForDataProviderTopic:[XIMusic topic]];
    });
}


//iOS 11>
- (void)_mediaRemoteNowPlayingInfoDidChange:(id)arg1 {
    %orig;
    [[XIWidgetManager sharedInstance] requestRefreshForDataProviderTopic:[XIMusic topic]];
}
%end

%hook MPUNowPlayingController

- (id)init {
    id orig = %orig;
    
    if (orig) {
        globalMPUNowPlaying = orig;
    }
    return orig;
}

%new
+(id)_xeninfo_MPUNowPlayingController{
    return globalMPUNowPlaying;
}

%new
+(id)_xeninfo_albumArt {
    if (!globalMPUNowPlaying){
        MPUNowPlayingController *nowPlayingController = [[objc_getClass("MPUNowPlayingController") alloc] init];
        [nowPlayingController startUpdating];
        return [nowPlayingController currentNowPlayingArtwork];
    }
    return [globalMPUNowPlaying currentNowPlayingArtwork];
}

%end

///////////////////////////////////////////////////////////////
#pragma mark Statusbar state
///////////////////////////////////////////////////////////////

#import "Statusbar/XIStatusBar.h"

%hook SBStatusBarStateAggregator

- (void)_notifyItemChanged:(int)arg1{
    %orig;
    
    [[XIWidgetManager sharedInstance] requestRefreshForDataProviderTopic:[XIStatusBar topic]];
}

-(void)_updateDataNetworkItem{
    %orig;
    
    [[XIWidgetManager sharedInstance] requestRefreshForDataProviderTopic:[XIStatusBar topic]];
}

%end

///////////////////////////////////////////////////////////////
#pragma mark Display state
///////////////////////////////////////////////////////////////

// iOS 9
%hook SBLockScreenViewController

-(void)_handleDisplayTurnedOff {
    %orig;
    
    [[XIWidgetManager sharedInstance] noteDeviceDidEnterSleep];
}

// When in a phone call, this code is not run.
- (void)_handleDisplayTurnedOnWhileUILocked:(id)locked {
    [[XIWidgetManager sharedInstance] noteDeviceDidExitSleep];
    
    %orig;
}

%end

// iOS 10
%hook SBLockScreenManager

- (void)_handleBacklightLevelChanged:(NSNotification*)arg1 {
    %orig;
    
    if ([UIDevice currentDevice].systemVersion.floatValue >= 10.0) {
        NSDictionary *userInfo = arg1.userInfo;
        
        CGFloat newBacklight = [[userInfo objectForKey:@"SBBacklightNewFactorKey"] floatValue];
        CGFloat oldBacklight = [[userInfo objectForKey:@"SBBacklightOldFactorKey"] floatValue];
        
        if (newBacklight == 0.0) {
            [[XIWidgetManager sharedInstance] noteDeviceDidEnterSleep];
        } else if (oldBacklight == 0.0 && newBacklight > 0.0) {
            [[XIWidgetManager sharedInstance] noteDeviceDidExitSleep];
        }
    }
}

%end

// iOS 11
%hook SBScreenWakeAnimationController

- (void)_handleAnimationCompletionIfNecessaryForWaking:(_Bool)wokeLS {
    if (!wokeLS) {
        [[XIWidgetManager sharedInstance] noteDeviceDidEnterSleep];
    }
    
    %orig;
}

- (void)_startWakeAnimationsForWaking:(_Bool)arg1 animationSettings:(id)arg2 {
    if (arg1) {
        [[XIWidgetManager sharedInstance] noteDeviceDidExitSleep];
    }
    
    %orig;
}

%end

///////////////////////////////////////////////////////////////
#pragma mark Alarms
///////////////////////////////////////////////////////////////

#import "Alarms/XIAlarms.h"


// iOS 10 and 11
%hook SBClockNotificationManager

- (void)_updateAlarmStatusBarItemForPendingNotificationRequests:(id)arg1 {
    %orig;
    
    [[XIWidgetManager sharedInstance] requestRefreshForDataProviderTopic:[XIAlarms topic]];
}

%end

// iOS 12+
%hook MTAlarmManagerExportedObject

-(void)alarmsAdded:(id)arg1 {
    %orig;
    [[XIWidgetManager sharedInstance] requestRefreshForDataProviderTopic:[XIAlarms topic]];
}

-(void)alarmsUpdated:(id)arg1 {
    %orig;
    Xlog(@"Alarms updated: %@", arg1);
    [[XIWidgetManager sharedInstance] requestRefreshForDataProviderTopic:[XIAlarms topic]];
}

-(void)alarmsRemoved:(id)arg1 {
    %orig;
    [[XIWidgetManager sharedInstance] requestRefreshForDataProviderTopic:[XIAlarms topic]];
}

-(void)alarmFired:(id)arg1 {
    %orig;
    [[XIWidgetManager sharedInstance] requestRefreshForDataProviderTopic:[XIAlarms topic]];
}

%end

///////////////////////////////////////////////////////////////
#pragma mark Constructor
///////////////////////////////////////////////////////////////

%ctor {
    Xlog(@"Injecting...");
    
    // Load Weather.framework if needed
    dlopen("/System/Library/PrivateFrameworks/Weather.framework/Weather", RTLD_NOW);
    
    %init;
}
