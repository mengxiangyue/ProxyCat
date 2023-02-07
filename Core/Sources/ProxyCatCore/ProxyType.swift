//
//  File.swift
//  
//
//  Created by xiangyue on 2023/1/1.
//

import Foundation

public let PROXY_CAT_HEADER_NAME = "ProxyCat-Proxy-Type"
public enum ProxyType: String {
    case unknown
    case http
    case https
}
