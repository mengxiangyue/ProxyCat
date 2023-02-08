//
//  File.swift
//  
//
//  Created by xiangyue on 2023/2/8.
//

import Foundation
import NIOHTTP1

class RequestRecord {
    var requestHeaders: HTTPHeaders?
    var responseHeaders: HTTPHeaders?
    var responseStatus: Int?
    var requestBody: Data?
    var responseBody: Data?
}
