//
//  File.swift
//  
//
//  Created by xiangyue on 2023/1/1.
//

import Foundation

// store some information used by Core internally
class ProxyInfoStore {
    // TODO: update, can't get the https port after CONNECT
    var proxyHostPortMap: [String: Int] = [:]
}
