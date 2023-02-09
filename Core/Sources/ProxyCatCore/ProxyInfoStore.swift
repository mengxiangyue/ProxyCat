//
//  File.swift
//  
//
//  Created by xiangyue on 2023/1/1.
//

import Foundation

//// store some information used by Core internally
//class ProxyInfoStore {
//    private let dummyValue = "TRANSPARENT"
//    // TODO: update, can't get the https port after CONNECT
//    var proxyHostPortMap: [String: Int] = [:]
//    private var transparentHttpsHosts: [String: String] = [:]
//    
//    func addTransparentHttpHost(_ host: String) {
//        transparentHttpsHosts[host] = dummyValue
//    }
//    
//    func removeTransparentHttpHost(_ host: String) {
//        transparentHttpsHosts.removeValue(forKey: host)
//    }
//    
//    func checkTransparentForHost(_ host: String) -> Bool {
//        return transparentHttpsHosts[host] == dummyValue
//    }
//}
