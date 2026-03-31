//
//  AppDelegate.swift
//  Rapport Challenge
//
//  Created by Stanley Pratama Teguh on 13/03/26.
//

import UIKit
import SwiftUI
<<<<<<< HEAD
import AVFoundation
=======
>>>>>>> dcc6b560f94e1f92c12f88df0e8fa30c045fcabf

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?


    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        // Create the SwiftUI view that provides the window contents.
        let contentView = ContentView()

        // Use a UIHostingController as window root view controller.
<<<<<<< HEAD
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return false
        }
        
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: contentView)
        self.window = window
        window.makeKeyAndVisible()
        AudioManager.shared.startIfNeeded()
=======
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIHostingController(rootView: contentView)
        self.window = window
        window.makeKeyAndVisible()
>>>>>>> dcc6b560f94e1f92c12f88df0e8fa30c045fcabf
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
<<<<<<< HEAD
        AudioManager.shared.pause()
=======
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
>>>>>>> dcc6b560f94e1f92c12f88df0e8fa30c045fcabf
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
<<<<<<< HEAD
        AudioManager.shared.startIfNeeded()
=======
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
>>>>>>> dcc6b560f94e1f92c12f88df0e8fa30c045fcabf
    }


}

