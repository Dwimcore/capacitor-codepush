#import <Capacitor/Capacitor-Swift.h>
#import <Capacitor/Capacitor.h>
#import "SSZipArchive/SSZipArchive.h"
#import "CodePush.h"
#import "CodePushPackageMetadata.h"
#import "CodePushPackageManager.h"
#import "Utilities.h"
#import "InstallOptions.h"
#import "InstallMode.h"
#import "CodePushReportingManager.h"
#import "StatusReport.h"
#import "UpdateHashUtils.h"
#import "CodePushJWT.h"



@interface CodePushPlugin () <UIScrollViewDelegate>

@property (readwrite, assign, nonatomic) NSString* getServerURL;
@property (readwrite, assign, nonatomic) NSString* getDeploymentKey;
@property (readwrite, assign, nonatomic) NSString* getNativeBuildTime;
@property (readwrite, assign, nonatomic) NSString* getAppVersion;
@property (readwrite, assign, nonatomic) BOOL install;
@property (readwrite, assign, nonatomic) BOOL preInstall;
@property (readwrite, assign, nonatomic) BOOL isFailedUpdate;
@property (readwrite, assign, nonatomic) BOOL isFirstRun;
@property (readwrite, assign, nonatomic) BOOL isPendingUpdate;
@property (readwrite, assign, nonatomic) BOOL restartApplication;
@property (readwrite, assign, nonatomic) NSString* getBinaryHash;
@property (readwrite, assign, nonatomic) NSString* getPackageHash;
@property (nonatomic, readwrite) NSString* decodeSignature;
@property (readwrite, assign, nonatomic) NSString* getPublicKey;

- (void) setServerBasePath:(NSString*)serverPath;

@end

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wprotocol"
// suppressing warnings of the type: "Class 'CodePushPlugin' does not conform to protocol 'CAPBridgedPlugin'"
// protocol conformance for this class is implemented by a macro and clang isn't detecting that
@implementation CodePushPlugin

static NSString *specifiedServerPath = @"";
bool didUpdate = false;
bool pendingInstall = false;
NSDate* lastResignedDate;
NSString* const DeploymentKeyPreference = @"IOS_DEPLOY_KEY";
NSString* const PublicKeyPreference = @"IOS_PUBLIC_KEY";
StatusReport* rollbackStatusReport = nil;

- (void)getBinaryHash:(CAPPluginCall *)call {
    NSString* binaryHash = [CodePushPackageManager getCachedBinaryHash];
    if (binaryHash) {
        [call resolve: @{@"value": binaryHash}];
    } else {
        NSError* error;
        binaryHash = [UpdateHashUtils getBinaryHash:&error];
        if (error) {
            [call reject:@"An error occurred when trying to get the hash of the binary contents. " :nil : error:@{}];
        } else {
            [CodePushPackageManager saveBinaryHash:binaryHash];
            [call resolve:@{@"value":binaryHash}];
        }
    }
}

- (void)getPackageHash:(CAPPluginCall *)call {
    NSString *path = [self getString:call field:@"path" defaultValue:nil];
    if (!path) {
        [call reject:@"No path supplied":nil:nil:@{}];
    } else {
        path = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0]
                stringByAppendingPathComponent:path]
                stringByAppendingPathComponent:@"public"];
        NSError *error;
        NSString *hash = [UpdateHashUtils getHashForPath:path error:&error];
        if (error) {
            [call reject:[NSString stringWithFormat:@"An error occured when trying to get the hash of %@. %@", path, error.description]:nil:error:@{}];
        } else {
            [call resolve:@{@"value":hash}];
        }
    }
}

- (void)getPublicKey:(CAPPluginCall *)call {
    NSString *publicKey = [self getConfigValue:PublicKeyPreference];
    if (!publicKey) {
        [call resolve:nil]; /* Returning @{@"value":nil} causes an uncaught exception */
    } else {
        [call resolve:@{@"value":publicKey}];
    }
}

- (void)decodeSignature:(CAPPluginCall *)call {
    NSString *publicKey = [self getString:call field:@"publicKey" defaultValue:nil];

    // remove BEGIN / END tags and line breaks from public key string
    publicKey = [publicKey stringByReplacingOccurrencesOfString:@"-----BEGIN PUBLIC KEY-----\n"
                                                     withString:@""];
    publicKey = [publicKey stringByReplacingOccurrencesOfString:@"-----END PUBLIC KEY-----"
                                                     withString:@""];
    publicKey = [publicKey stringByReplacingOccurrencesOfString:@"\n"
                                                     withString:@""];

    NSString *jwt = [self getString:call field:@"signature" defaultValue:nil];

    id <JWTAlgorithmDataHolderProtocol> verifyDataHolder = [JWTAlgorithmRSFamilyDataHolder new]
            .keyExtractorType([JWTCryptoKeyExtractor publicKeyWithPEMBase64].type)
            .algorithmName(@"RS256")
            .secret(publicKey);
    JWTCodingBuilder *verifyBuilder = [JWTDecodingBuilder decodeMessage:jwt].addHolder(verifyDataHolder);
    JWTCodingResultType *verifyResult = verifyBuilder.result;
    if (verifyResult.successResult) {
        NSLog(@"JWT signature verification succeeded, payload content:  %@", verifyResult.successResult.payload);
        [call resolve:@{@"value":verifyResult.successResult.payload[@"contentHash"]}];
    } else {
        [call reject:[@"Signature verification failed: " stringByAppendingString:verifyResult.errorResult.error.description]:nil:nil:@{}];
    }
}

- (void)handleUnconfirmedInstall:(BOOL)navigate {
    if ([CodePushPackageManager installNeedsConfirmation]) {
        /* save reporting status */
        CodePushPackageMetadata* currentMetadata = [CodePushPackageManager getCurrentPackageMetadata];
        rollbackStatusReport = [[StatusReport alloc] initWithStatus:UPDATE_ROLLED_BACK
                                                           andLabel:currentMetadata.label
                                                      andAppVersion:currentMetadata.appVersion
                                                   andDeploymentKey:currentMetadata.deploymentKey];
        [CodePushPackageManager clearInstallNeedsConfirmation];
        [CodePushPackageManager revertToPreviousVersion];
        if (navigate) {
            CodePushPackageMetadata* currentMetadata = [CodePushPackageManager getCurrentPackageMetadata];
            bool revertSuccess = (nil != currentMetadata && [self loadPackage:currentMetadata.localPath]);
            if (!revertSuccess) {
                /* first update failed, go back to binary version */
                [self loadStoreVersion];
            }
        }
    }
}

- (void)notifyApplicationReady:(CAPPluginCall *)call {
    if ([CodePushPackageManager isBinaryFirstRun]) {
        // Report first run of a binary version app
        [CodePushPackageManager markBinaryFirstRunFlag];
        NSString* appVersion = [Utilities getApplicationVersion];
        NSString* deploymentKey = [self getConfigValue:DeploymentKeyPreference];
        StatusReport* statusReport = [[StatusReport alloc] initWithStatus:STORE_VERSION
                                                                 andLabel:nil
                                                            andAppVersion:appVersion
                                                         andDeploymentKey:deploymentKey];
        [CodePushReportingManager reportStatus:statusReport
                                   withWebView:self.webView];
    } else if ([CodePushPackageManager installNeedsConfirmation]) {
        // Report CodePush update installation that has not been confirmed yet
        CodePushPackageMetadata* currentMetadata = [CodePushPackageManager getCurrentPackageMetadata];
        StatusReport* statusReport = [[StatusReport alloc] initWithStatus:UPDATE_CONFIRMED
                                                                 andLabel:currentMetadata.label
                                                            andAppVersion:currentMetadata.appVersion
                                                         andDeploymentKey:currentMetadata.deploymentKey];
        [CodePushReportingManager reportStatus:statusReport
                                withWebView:self.webView];
    } else if (rollbackStatusReport) {
        // Report a CodePush update that rolled back
        [CodePushReportingManager reportStatus:rollbackStatusReport
                                   withWebView:self.webView];
        rollbackStatusReport = nil;
    } else if ([CodePushReportingManager hasFailedReport]) {
        // Previous status report failed, so try it again
        [CodePushReportingManager reportStatus:[CodePushReportingManager getAndClearFailedReport]
                                   withWebView:self.webView];
    }

    // Mark the update as confirmed and not requiring a rollback
    [CodePushPackageManager clearInstallNeedsConfirmation];
    [CodePushPackageManager cleanOldPackage];
    [call resolve];
}

-(NSNumber *) getNumber:(CAPPluginCall *)call field:(NSString *)field defaultValue:(NSNumber *)defaultValue {
    id idVal = [call.options objectForKey:field];
    if(![idVal isKindOfClass:[NSNumber class]]) {
        return defaultValue;
    }
    NSNumber *value = (NSNumber *)idVal;
    if(value == nil) {
        return defaultValue;
    }
    return value;
}

- (void)install:(CAPPluginCall *)call {
    NSString* location = [self getString:call field:@"startLocation" defaultValue:nil];
    NSNumber* installMode = [self getNumber:call field:@"installMode" defaultValue:IMMEDIATE];
    NSNumber* minimumBackgroundDuration = [self getNumber:call field:@"minimumBackgroundDuration" defaultValue:0];

    InstallOptions* options = [[InstallOptions alloc] init];
    [options setInstallMode:[installMode intValue]];
    [options setMinimumBackgroundDuration:[minimumBackgroundDuration intValue]];

    if ([options installMode] == IMMEDIATE) {
        if (nil == location) {
            [call reject:@"Cannot read the start URL" : nil :nil:@{}];
        }
        else {
            bool applied = [self loadPackage: location];
            if (applied) {
                [self markUpdate];
                [call resolve];
            }
            else {
                [call reject: @"An error happened during package install.": nil:nil: @{} ];
            }
        }
    }
    else {
        /* install on restart or on resume */
        [CodePushPackageManager savePendingInstall:options];
        [call resolve];
    }
}

- (void)reportFailed:(CAPPluginCall *)call {
    NSDictionary* statusReportDict = [call.options objectForKey: @"statusReport"];
    if (statusReportDict) {
        [CodePushReportingManager saveFailedReport:[[StatusReport alloc] initWithDictionary:statusReportDict]];
    }
    [call resolve];
}

- (void)reportSucceeded:(CAPPluginCall *)call {
    NSDictionary* statusReportDict = [call.options objectForKey: @"statusReport"];
    if (statusReportDict) {
        [CodePushReportingManager saveSuccessfulReport:[[StatusReport alloc] initWithDictionary:statusReportDict]];
    }
    [call resolve];
}

- (void)restartApplication:(CAPPluginCall *)call {
    [call resolve];

    /* Callback before navigating */
    CodePushPackageMetadata* deployedPackageMetadata = [CodePushPackageManager getCurrentPackageMetadata];
    if (deployedPackageMetadata && deployedPackageMetadata.localPath && [self getStartPageURLForLocalPackage:deployedPackageMetadata.localPath]) {
        [self loadPackage: deployedPackageMetadata.localPath];
        InstallOptions* pendingInstall = [CodePushPackageManager getPendingInstall];
        if (pendingInstall) {
            [self markUpdate];
            [CodePushPackageManager clearPendingInstall];
        }
    }
    else {
        [self loadStoreVersion];
    }
}

- (void) markUpdate {
    didUpdate = YES;
    [CodePushPackageManager markInstallNeedsConfirmation];
}

- (void)preInstall:(CAPPluginCall *)call {
    NSString* location = [self getString:call field:@"startLocation" defaultValue:nil];
    if (nil == location) {
        [call reject: @"Cannot read the start URL.":nil:nil:@{}];
    }
    else {
        NSURL* URL = [self getStartPageURLForLocalPackage:location];
        if (URL) {
            [call resolve];
        }
        else {
            [call reject: @"Could not find start page in package.":nil:nil:@{}];
        }
    }
}

- (void)getServerURL:(CAPPluginCall *)call {
    [self sendResultForPreference:@"SERVER_URL" call:call];
}

- (void)getDeploymentKey:(CAPPluginCall *)call {
    [self sendResultForPreference:DeploymentKeyPreference call:call];
}

- (void)getNativeBuildTime:(CAPPluginCall *)call {
    NSString* timeStamp = [Utilities getApplicationTimestamp];
    [call resolve: @{@"value":timeStamp}];
}

- (void)sendResultForPreference:(NSString*)preferenceName call:(CAPPluginCall *)call {
    NSString* preferenceValue = [self getConfigValue:preferenceName];
    // length of NIL is zero
    if ([preferenceValue length] > 0) {
        [call resolve: @{@"value":preferenceValue}];
    } else {
        [call reject: [NSString stringWithFormat:@"Could not find preference %@", preferenceName]:nil:nil:@{}];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)clearDeploymentsIfBinaryUpdated {
    // check if we have a deployed package
    CodePushPackageMetadata* deployedPackageMetadata = [CodePushPackageManager getCurrentPackageMetadata];
    if (deployedPackageMetadata) {
        NSString* deployedPackageNativeBuildTime = deployedPackageMetadata.nativeBuildTime;
        NSString* applicationBuildTime = [Utilities getApplicationTimestamp];

        NSString* deployedPackageVersion = deployedPackageMetadata.appVersion;
        NSString* applicationVersion = [Utilities getApplicationVersion];

        if (deployedPackageNativeBuildTime != nil && applicationBuildTime != nil &&
            deployedPackageVersion != nil && applicationVersion != nil) {
            if (![deployedPackageNativeBuildTime isEqualToString: applicationBuildTime] ||
                ![deployedPackageVersion isEqualToString: applicationVersion]) {
                // package version is incompatible with installed native version
                [CodePushPackageManager cleanDeployments];
                [CodePushPackageManager clearFailedUpdates];
                [CodePushPackageManager clearPendingInstall];
                [CodePushPackageManager clearInstallNeedsConfirmation];
                [CodePushPackageManager clearBinaryFirstRunFlag];
            }
        }
    }
}

- (void)navigateToLocalDeploymentIfExists {
    CodePushPackageMetadata* deployedPackageMetadata = [CodePushPackageManager getCurrentPackageMetadata];
    if (deployedPackageMetadata && deployedPackageMetadata.localPath) {
        [self redirectStartPageToURL: deployedPackageMetadata.localPath];
    }
}

- (void)load {
    // register for "on resume", "on pause" notifications
    [self clearDeploymentsIfBinaryUpdated];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillEnterForeground) name:UIApplicationWillEnterForegroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillResignActive) name:UIApplicationWillResignActiveNotification object:nil];
    InstallOptions* pendingInstall = [CodePushPackageManager getPendingInstall];
    if (!pendingInstall) {
        [self handleUnconfirmedInstall:NO];
    }

    [self navigateToLocalDeploymentIfExists];
    // handle both ON_NEXT_RESUME and ON_NEXT_RESTART - the application might have been killed after transitioning to the background
    if (pendingInstall && (pendingInstall.installMode == ON_NEXT_RESTART || pendingInstall.installMode == ON_NEXT_RESUME)) {
        [self markUpdate];
        [CodePushPackageManager clearPendingInstall];
    }
}

- (void)applicationWillEnterForeground {
    InstallOptions* pendingInstall = [CodePushPackageManager getPendingInstall];
    // calculate the duration that the app was in the background
    long durationInBackground = lastResignedDate ? [[NSDate date] timeIntervalSinceDate:lastResignedDate] : 0;
    if (pendingInstall && pendingInstall.installMode == ON_NEXT_RESUME && durationInBackground >= pendingInstall.minimumBackgroundDuration) {
        CodePushPackageMetadata* deployedPackageMetadata = [CodePushPackageManager getCurrentPackageMetadata];
        if (deployedPackageMetadata && deployedPackageMetadata.localPath) {
            bool applied = [self loadPackage: deployedPackageMetadata.localPath];
            if (applied) {
                [self markUpdate];
                [CodePushPackageManager clearPendingInstall];
            }
        }
    } else if ([CodePushReportingManager hasFailedReport]) {
        [CodePushReportingManager reportStatus:[CodePushReportingManager getAndClearFailedReport] withWebView:self.webView];
    }
}

- (void)applicationWillResignActive {
    // Save the current time so that when the app is later resumed, we can detect how long it was in the background
    lastResignedDate = [NSDate date];
}

- (BOOL)loadPackage:(NSString*)packageLocation {
    NSURL* URL = [self getStartPageURLForLocalPackage:packageLocation];
    if (URL) {
        [self setServerBasePath:URL.path];
        return YES;
    }

    return NO;
}

- (void)loadURL:(NSURL*)url {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
    });
}

+ (NSString*) getCurrentServerBasePath {
    return specifiedServerPath;
}

- (void) setServerBasePath:(NSString*)serverPath {
    specifiedServerPath = serverPath;
    NSMutableArray * urlPathComponents = [serverPath pathComponents].mutableCopy;
    [urlPathComponents removeLastObject];
    NSString * serverBasePath = [urlPathComponents componentsJoinedByString:@"/"];

    dispatch_async(dispatch_get_main_queue(), ^{
        [(CAPBridgeViewController *) self.bridge.viewController setServerBasePathWithPath:serverBasePath];
    });
}

- (void)loadStoreVersion {
    NSString* mainBundlePath = [[NSBundle mainBundle] bundlePath];
    NSString* configStartPage = [self getConfigLaunchUrl];
    NSArray* realLocationArray = @[mainBundlePath, @"public", configStartPage];
    NSString* mainPageLocation = [NSString pathWithComponents:realLocationArray];
    if ([[NSFileManager defaultManager] fileExistsAtPath:mainPageLocation]) {
        NSURL* mainPagePath = [NSURL fileURLWithPath:mainPageLocation];
        [self loadURL:mainPagePath];
    }
}

- (NSString*)getConfigLaunchUrl
{
//    CDVConfigParser* delegate = [[CDVConfigParser alloc] init];
//    NSString* configPath = [[NSBundle mainBundle] pathForResource:@"config" ofType:@"xml"];
//    NSURL* configUrl = [NSURL fileURLWithPath:configPath];
//
//    NSXMLParser* configParser = [[NSXMLParser alloc] initWithContentsOfURL:configUrl];
//    [configParser setDelegate:((id < NSXMLParserDelegate >)delegate)];
//    [configParser parse];
    // TODO: implement me
    return @"http://localhost";
}

- (NSURL *)getStartPageURLForLocalPackage:(NSString*)packageLocation {
    if (packageLocation) {
        NSString* libraryLocation = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
        NSArray* realLocationArray = @[libraryLocation, packageLocation, @"public/index.html"];
        NSString* realStartPageLocation = [NSString pathWithComponents:realLocationArray];
        if ([[NSFileManager defaultManager] fileExistsAtPath:realStartPageLocation]) {
            // Fixes WKWebView unable to load start page from CodePush update directory
            NSString* scheme = [self getAppScheme];
            if ([Utilities CDVWebViewEngineAvailable] && ([realStartPageLocation hasPrefix:@"/_app_file_"] == NO) && !([scheme isEqualToString: @"file"] || scheme == nil)) {
                realStartPageLocation = [@"/_app_file_" stringByAppendingString:realStartPageLocation];
            }
            return [NSURL fileURLWithPath:realStartPageLocation];
        }
    }

    return nil;
}

- (void)redirectStartPageToURL:(NSString*)packageLocation{
    NSURL* URL = [self getStartPageURLForLocalPackage:packageLocation];
    if (URL) {
        [self setServerBasePath:URL.path];
    }
}

- (void)isFailedUpdate:(CAPPluginCall *)call {
    NSString* packageHash = [self getString:call field:@"packageHash" defaultValue:nil];
    if (nil == packageHash) {
        [call reject: @"Invalid package hash parameter.": nil:nil: @{}];
    }
    else {
        BOOL failedHash = [CodePushPackageManager isFailedHash:packageHash];
        [call resolve:@{@"value": failedHash ? @1 : @0}];
    }
}

- (void)isFirstRun:(CAPPluginCall *)call {
    BOOL isFirstRun = NO;

    NSString* packageHash = [self getString:call field:@"packageHash" defaultValue:nil];
    CodePushPackageMetadata* currentPackageMetadata = [CodePushPackageManager getCurrentPackageMetadata];
    if (currentPackageMetadata) {
        isFirstRun = (nil != packageHash
                        && [packageHash length] > 0
                        && [packageHash isEqualToString:currentPackageMetadata.packageHash]
                        && didUpdate);
    }

    [call resolve:@{@"value": isFirstRun ? @1 : @0}];
}

- (void)isPendingUpdate:(CAPPluginCall *)call {
    InstallOptions* pendingInstall = [CodePushPackageManager getPendingInstall];
    [call resolve:@{@"value": pendingInstall ? @1 : @0}];
}

- (void)getAppVersion:(CAPPluginCall *)call {
    NSString* version = [Utilities getApplicationVersion];
    [call resolve: @{@"value":version}];
}

- (NSString*)getAppScheme {
    NSString *scheme = [self getConfigValue:@"scheme"];
    return scheme;
}

- (void)unzip:(CAPPluginCall *)call {
    NSString * zipFile = [self getString:call field:@"zipFile" defaultValue:nil];
    NSURL * zipURL =  [NSURL URLWithString:zipFile];
    NSString * unzipPath = [self getString:call field:@"targetDirectory" defaultValue:nil];
    NSURL * unzipURL =  [NSURL URLWithString:unzipPath];
    // https://stackoverflow.com/questions/37564303/unzip-a-file-using-ssziparchive-not-extracting-the-contents-of-the-file
    // It require NSURL path (not absoluteString - start with file://)
    BOOL result = [SSZipArchive unzipFileAtPath:zipURL.path toDestination:unzipURL.path overwrite:YES password:nil error:nil];
    if (result) {
        [call resolve];
    } else {
        [call reject:@"Failed to unzip": nil : nil : @{}];
    }
}

@end

