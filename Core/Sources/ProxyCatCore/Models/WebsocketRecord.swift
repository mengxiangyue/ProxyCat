//
//  File.swift
//  
//
//  Created by xiangyue on 2023/2/11.
//

import Foundation
import NIOHTTP1

public class WebsocketRecord {
    public let id = UUID().uuidString
    public var version: HTTPVersion?
    public var requestHeaders: HTTPHeaders?
    public var responseHeaders: HTTPHeaders?
    
    public var messages: [WebsocketMessageContent] = []
}

public enum WebsocketMessageType: String {
    case up
    case down
}

public struct WebsocketMessageContent: CustomStringConvertible {
    public let type: WebsocketMessageType
    public let data: String // TODO: update
    
    public var description: String {
        return "type: \(type), content: \(data)"
    }
}
