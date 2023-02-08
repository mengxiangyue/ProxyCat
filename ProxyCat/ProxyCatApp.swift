//
//  ProxyCatApp.swift
//  ProxyCat
//
//  Created by xiangyue on 2023/2/7.
//

import SwiftUI
import ProxyCatCore

@main
struct ProxyCatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
