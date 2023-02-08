//
//  AppDelegate.swift
//  ProxyCat
//
//  Created by xiangyue on 2023/2/8.
//

import Cocoa
import SwiftUI
import ProxyCatCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var shared: AppDelegate?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
                
//        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == nil {
//            if RemoteLoggerServer.shared.isEnabled {
//                RemoteLoggerServer.shared.enable()
//            }
//        }
        Task {
            let proxyServer = ProxyServer()
            await proxyServer.start()
        }
    }
}
