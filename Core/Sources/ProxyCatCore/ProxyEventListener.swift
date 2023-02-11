//
//  File.swift
//  
//
//  Created by xiangyue on 2023/2/8.
//

import Foundation

public protocol ProxyEventListener: AnyObject {
    func didReceive(error: Error)
    func didReceive(record: RequestRecord)
    func didReceive(websocketRecord: WebsocketRecord) 
}
