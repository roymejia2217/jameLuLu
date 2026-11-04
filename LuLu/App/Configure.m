//
//  Configure.m
//  LuLu
//
//  Created by Patrick Wardle on 2/6/24.
//  Copyright © 2024 Objective-See. All rights reserved.
//

#import "consts.h"
#import "../Shared/JameIdentityPolicy.h"
#import "utilities.h"

#import "Configure.h"
#import "Extension.h"
#import "XPCDaemonClient.h"

/* GLOBALS */

//log handle
extern os_log_t logHandle;

//xpc for daemon comms
extern XPCDaemonClient* xpcDaemonClient;

@implementation Configure

//init
-(id)init
{
    //init
    if(self = [super init])
    {
        //if needed, in extension comms
        if(nil == xpcDaemonClient)
        {
            //init
            xpcDaemonClient = [[XPCDaemonClient alloc] init];
        }
    }
    
    return self;
}

//install
-(BOOL)install
{
    //flag
    BOOL installed = NO;
    
    //error
    NSError* error = nil;
    
    //source
    NSString* source = nil;
    
    //destination
    NSString* destination = nil;
    
    //dbg msg
    os_log_debug(logHandle, "function '%s' invoked", __PRETTY_FUNCTION__);
    
    // Refuse to overwrite any unrelated app already occupying the fork path.
    // Validate before touching the existing network filter or running peers.
    source = NSBundle.mainBundle.bundlePath;
    destination = [@"/Applications" stringByAppendingPathComponent:APP_NAME];
    if([NSFileManager.defaultManager fileExistsAtPath:destination] &&
       YES != JameIsOwnedBundle([NSBundle bundleWithPath:destination].bundleIdentifier,
                                destination, APP_ID, APP_NAME))
    {
        os_log_error(logHandle, "ERROR: refusing to replace a foreign app at %{public}@",
                     destination);
        goto bail;
    }
    // A repeated -install/-upgrade command from the installed bundle is a
    // no-op. Disabling the filter and copying the app onto itself fails and
    // could leave a previously active firewall disabled.
    if(YES == JameBundleLocationsEqual(source, destination))
    {
        os_log(logHandle, "jameLuLu already installed at %{public}@; no replacement needed",
               destination);
        installed = YES;
        goto bail;
    }
    //disable network filter
    // ensures the provider stops before replacing the app/extension bundle
    if(YES != [[[Extension alloc] init] toggleNetworkExtension:ACTION_DEACTIVATE])
    {
        //dbg msg
        os_log_debug(logHandle, "network filter was not deactivated before install/upgrade");
    }
    
    //quit other running jameLuLu instances
    // leave the system extension registered (this is an install/upgrade)
    [self quit:NO];

    //remove only a previous jameLuLu.app; never touch upstream LuLu.app
    if(YES == [NSFileManager.defaultManager fileExistsAtPath:destination])
    {
        //not us?
        // remove
        if(YES != [source isEqualToString:destination])
        {
            //remove
            if(YES != [NSFileManager.defaultManager removeItemAtPath:destination error:&error])
            {
                //err msg
                os_log_error(logHandle, "ERROR: failed to remove %{public}@ (error: %{public}@)", destination, error);
                goto bail;
            }
        }
    }
    
    //copy self into /Applications
    if(YES != [NSFileManager.defaultManager copyItemAtPath:source toPath:destination error:&error])
    {
        //err msg
        os_log_error(logHandle, "ERROR: failed to move %{public}@ to %{public}@ (error: %{public}@)", source, destination, error);
        goto bail;
    }
    
    //dbg msg
    os_log_debug(logHandle, "moved self into /Applications and will launch...");
    
    //now launch
    if(nil == [NSWorkspace.sharedWorkspace launchApplicationAtURL:[NSURL fileURLWithPath:destination] options:0 configuration:@{} error:&error])
    {
        //err msg
        os_log_error(logHandle, "ERROR: failed to launch  %{public}@, (error: %{public}@)", destination, error);
        goto bail;
    }
    
    //happy
    installed = YES;
    
bail:
    
    return installed;
    
}

//upgrade
// same as install
-(BOOL)upgrade
{
    //dbg msg
    os_log_debug(logHandle, "function '%s' invoked", __PRETTY_FUNCTION__);
    
    return [self install];
}

//unistall
-(BOOL)uninstall
{
    //flag
    BOOL errors = NO;
    
    //error
    NSError* error = nil;
    
    //app
    NSString* app = [@"/Applications" stringByAppendingPathComponent:APP_NAME];
    
    //dbg msg
    os_log_debug(logHandle, "function '%s' invoked", __PRETTY_FUNCTION__);
    
    // An unrelated bundle must never be removed by our uninstall action.
    if([NSFileManager.defaultManager fileExistsAtPath:app] &&
       YES != JameIsOwnedBundle([NSBundle bundleWithPath:app].bundleIdentifier,
                                app, APP_ID, APP_NAME))
    {
        os_log_error(logHandle, "ERROR: refusing to uninstall a foreign app at %{public}@", app);
        return NO;
    }

    //tell ext. to uninstall
    // remove rules, etc, etc
    if(YES != [xpcDaemonClient uninstall])
    {
        //err msg
        os_log_error(logHandle, "ERROR: daemon's XPC uninstall logic");
        
        //set flag
        errors = YES;
        
        //but continue onwards
    }
    
    //first, remove login item
    toggleLoginItem([NSURL fileURLWithPath:app], ACTION_UNINSTALL_FLAG);

    //quit other jameLuLu instances and deactivate only its system extension
    [self quit:YES];
    
    //app found in /Apps?
    if(YES == [NSFileManager.defaultManager fileExistsAtPath:app])
    {
        //remove
        if(YES != [NSFileManager.defaultManager removeItemAtPath:app error:&error])
        {
            //set flag
            errors = YES;
            
            //err msg
            os_log_error(logHandle, "ERROR: failed to remove %{public}@ (error: %{public}@)", app, error);
            
            //but continue onwards
            
        } 
        //dbg msg
        else
        {
            os_log_debug(logHandle, "removed %{public}@", app);
        }
    }
    
    //dbg msg
    os_log_debug(logHandle, "uninstalling completed (with any errors? %d)", errors);
    
    return !errors;
}

//quit
// 'deactivateExtension': YES to also deactivate/unregister the system extension (uninstall);
//  NO to leave it registered/approved (quit & upgrade) so updates don't require re-approval
-(void)quit:(BOOL)deactivateExtension
{
    //extension
    Extension* extension = nil;
    
    //source
    NSString* source = nil;
    
    //copy in /Apps
    NSString* copy = nil;
    
    //running copy
    NSRunningApplication* runningCopy = nil;
    
    //error
    NSError* error = nil;
    
    //wait semaphore
    dispatch_semaphore_t semaphore = 0;
    
    //dbg msg
    os_log_debug(logHandle, "function '%s' invoked", __PRETTY_FUNCTION__);
    
    //init extension object
    extension = [[Extension alloc] init];
    
    //init source
    source = NSBundle.mainBundle.bundlePath;
    
    //init copy
    copy = [@"/Applications" stringByAppendingPathComponent:APP_NAME];
    
    // Only stop other instances of the fork. The original Objective-See LuLu
    // must remain running; its executable name is not a safe identity check.
    for(NSRunningApplication* peer in
        [NSRunningApplication runningApplicationsWithBundleIdentifier:APP_ID])
    {
        if(YES != JameMayTerminateOwnedPeer(peer.bundleIdentifier,
                                            peer.bundleURL.path,
                                            peer.processIdentifier, getpid(),
                                            APP_ID, APP_NAME))
            continue;

        os_log(logHandle, "stopping other jameLuLu instance: %{public}@ (pid: %d)",
               peer.bundleURL.path, peer.processIdentifier);

        if(YES != [peer forceTerminate])
            os_log_error(logHandle, "ERROR: could not terminate jameLuLu pid: %d",
                         peer.processIdentifier);
    }
    //need to deactivate the system extension?
    // only on uninstall — quit/upgrade leave it registered (so updates don't re-prompt)
    if(YES == deactivateExtension && YES == [extension isExtensionRunning])
    {
        //dbg msg
        os_log_debug(logHandle, "extension running, will deactivate...");
        
        //have to be running from /Applications for this to work
        // so if we're not there, spawn a copy to exectute this logic
        if(YES != [source isEqualToString:copy])
        {
            //dbg msg
            os_log_debug(logHandle, "will spawn copy from /Applications");
            
            // Never delete another app occupying our temporary activation path.
            if([NSFileManager.defaultManager fileExistsAtPath:copy] &&
               YES != JameIsOwnedBundle([NSBundle bundleWithPath:copy].bundleIdentifier,
                                        copy, APP_ID, APP_NAME))
            {
                os_log_error(logHandle,
                             "ERROR: refusing to replace a foreign app during deactivation: %{public}@",
                             copy);
                goto bail;
            }

            //any existing?
            if(YES == [NSFileManager.defaultManager fileExistsAtPath:copy])
            {
                //remove
                if(YES != [NSFileManager.defaultManager removeItemAtPath:copy error:&error])
                {
                    //err msg
                    os_log_error(logHandle, "ERROR: failed to remove %{public}@ (error: %{public}@)", copy, error);
                    goto bail;
                }
            }
            
            //copy self into /Applications
            if(YES != [NSFileManager.defaultManager copyItemAtPath:source toPath:copy error:&error])
            {
                //err msg
                os_log_error(logHandle, "ERROR: failed to move %{public}@ to %{public}@ (error: %{public}@)", source, copy, error);
                goto bail;
            }
            
            //dbg msg
            os_log_debug(logHandle, "launching copy %{public}@, to deactivate extension", copy);
            
            //launch copy
            runningCopy = [NSWorkspace.sharedWorkspace launchApplicationAtURL:[NSURL fileURLWithPath:copy] options:0 configuration:[NSDictionary dictionaryWithObject:@[@"-quit"] forKey:NSWorkspaceLaunchConfigurationArguments] error:&error];
            if(nil == runningCopy)
            {
                //err msg
                os_log_error(logHandle, "ERROR: failed to launch copy, %{public}@, (error: %{public}@)", copy, error);
                goto bail;
            }
            
            //wait till copy exits
            while(YES != runningCopy.isTerminated)
            {
                [NSThread sleepForTimeInterval:0.1];
            }
            
            //dbg msg
            os_log_debug(logHandle, "copy terminated, will delete");
            
            //delete copy
            if(YES != [NSFileManager.defaultManager removeItemAtPath:copy error:&error])
            {
                //err msg
                os_log_error(logHandle, "ERROR: failed to remove %{public}@ (error: %{public}@)", copy, error);
                goto bail;
                
            } 
            
            //dbg msg
            os_log_debug(logHandle, "removed copy %{public}@", copy);
        }
        
        //(now) running from /Apps
        // go ahead and remove extension
        else
        {
            //init wait semaphore
            semaphore = dispatch_semaphore_create(0);
            
            //kick off extension activation request
            [extension toggleExtension:ACTION_DEACTIVATE reply:^(NSError* error)
            {
                //toggled ok?
                if(!error)
                {
                    //dbg msg
                    os_log_debug(logHandle, "extension deactivated");
                }
                //failed?
                else
                {
                    //err msg
                    os_log_error(logHandle, "ERROR: failed to deactivate extension");
                }
                
                //signal semaphore
                dispatch_semaphore_signal(semaphore);
            }];
                
            //dbg msg
            os_log_debug(logHandle, "waiting system extension deactivation...");
            
            //wait for extension semaphore
            dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
            
            //dbg msg
            os_log_debug(logHandle, "extension event triggered");
            
        }
    }
    
bail:
    
    return;
}

@end
