//
//  CodePushPlugin.m
//  CapacitorCodepush
//
//  Created by 허상민 on 2021/02/04.
//

#import <Foundation/Foundation.h>
#import <Capacitor/Capacitor.h>

// Define the plugin using the CAP_PLUGIN Macro, and
// each method the plugin supports using the CAP_PLUGIN_METHOD macro.
CAP_PLUGIN(CodePushPlugin, "CodePush",
           CAP_PLUGIN_METHOD(getServerURL, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(getDeploymentKey, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(getNativeBuildTime, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(getAppVersion, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(install, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(preInstall, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(isFailedUpdate, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(isFirstRun, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(isPendingUpdate, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(notifyApplicationReady, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(reportFailed, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(reportSucceeded, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(restartApplication, CAPPluginReturnNone);
           CAP_PLUGIN_METHOD(getBinaryHash, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(getPackageHash, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(decodeSignature, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(getPublicKey, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(unzip, CAPPluginReturnPromise);
)
