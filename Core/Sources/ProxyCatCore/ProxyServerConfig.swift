//
//  File.swift
//  
//
//  Created by xiangyue on 2023/1/1.
//

import Foundation

public class ProxyServerConfig {
    public static let shared = ProxyServerConfig()
    
    private(set) weak var proxyEventListener: ProxyEventListener?
    
    let proxyInfoStore = ProxyInfoStore()
    
    private init() {}
    
    public func update(proxyEventListener: ProxyEventListener?) {
        self.proxyEventListener = proxyEventListener
    }
}
