//
//  File.swift
//  
//
//  Created by xiangyue on 2023/1/1.
//

import Foundation

class ProxyServerConfig {
    private let DUMMY_VALUE = "TRANSPARENT"
    private(set) weak var proxyEventListener: ProxyEventListener?
    
    // can't get the https port after CONNECT, so store it here for future use
    var proxyHostPortMap: [String: Int] = [:]
    private var transparentHttpsHosts: [String: String] = [:]
    
    static let shared = ProxyServerConfig()
    
    private init() {}
    
    func update(proxyEventListener: ProxyEventListener?) {
        self.proxyEventListener = proxyEventListener
    }
    
    func addTransparentHttpHost(_ host: String) {
        transparentHttpsHosts[host] = DUMMY_VALUE
    }
    
    func removeTransparentHttpHost(_ host: String) {
        transparentHttpsHosts.removeValue(forKey: host)
    }
    
    func checkTransparentForHost(_ host: String) -> Bool {
        return transparentHttpsHosts[host] == DUMMY_VALUE
    }
}
