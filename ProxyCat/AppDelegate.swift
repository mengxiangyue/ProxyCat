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
    
    let appDIContainer = DIContainer(appState: AppState(), interactors: .stub)
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
                
//        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == nil {
//            if RemoteLoggerServer.shared.isEnabled {
//                RemoteLoggerServer.shared.enable()
//            }
//        }
        Task {
            let proxyServer = ProxyServer()
            proxyServer.update(proxyEventListener: self)
            proxyServer.addTransparentHttpHost("www.baidu.com")
            await proxyServer.start()
        }
    }
}

extension AppDelegate: ProxyEventListener {
    func didReceive(error: Error) {
        
    }
    
    func didReceive(record: RequestRecord) {
        print(record.responseStatus?.code)
        var str = String(buffer: record.responseBody)
        print(str)
        
        str = String(buffer: record.requestBody)
        print(str)
    }
    
    func didReceive(websocketRecord: WebsocketRecord) {
        print("websocket msg")
        print(websocketRecord.messages)
    }
}
