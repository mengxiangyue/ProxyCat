//
//  File.swift
//  
//
//  Created by xiangyue on 2023/1/1.
//

import Foundation

public enum ProxyType {
    case unknown
    case http
    case https(isTransparent: Bool)
}
