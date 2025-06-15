//
//  NovarinLauncherApp.swift
//  NovarinLauncher
//
//  Created by bruhdude on 6/15/25.
//

import SwiftUI

@main
struct NovarinLauncherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

        var body: some Scene {
            WindowGroup {
                ContentView()
                    .environmentObject(appDelegate.launchState)
            }.windowStyle(HiddenTitleBarWindowStyle())
        }
}

