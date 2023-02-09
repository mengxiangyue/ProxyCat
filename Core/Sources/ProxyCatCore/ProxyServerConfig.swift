//
//  File.swift
//  
//
//  Created by xiangyue on 2023/1/1.
//

import Foundation

class ProxyServerConfig {
    private let DUMMY_VALUE = "TRANSPARENT"
    
    static let shared = ProxyServerConfig()
    
    private(set) weak var proxyEventListener: ProxyEventListener?
    
    
    // TODO: update, can't get the https port after CONNECT
    var proxyHostPortMap: [String: Int] = [:]
    private var transparentHttpsHosts: [String: String] = [:]
    
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
