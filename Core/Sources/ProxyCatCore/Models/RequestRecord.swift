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
    public var version: HTTPVersion?
    public var requestHeaders: HTTPHeaders?
    public var responseHeaders: HTTPHeaders?
    public var responseStatus: HTTPResponseStatus?
    public var requestBody = ByteBuffer()
    public var responseBody = ByteBuffer()
}
