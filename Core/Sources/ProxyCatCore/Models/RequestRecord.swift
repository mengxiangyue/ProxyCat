//
//  File.swift
//  
//
//  Created by xiangyue on 2023/2/8.
//

import Foundation
import NIO
import NIOHTTP1

public class RequestRecord {
    var version: HTTPVersion?
    var requestHeaders: HTTPHeaders?
    var responseHeaders: HTTPHeaders?
    var responseStatus: Int?
    var requestBody = ByteBuffer()
    var responseBody = ByteBuffer()
}
