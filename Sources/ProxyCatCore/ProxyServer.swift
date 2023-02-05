//
//  File.swift
//  
//
//  Created by xiangyue on 2022/12/31.
//

import NIOCore
import NIOPosix
import NIOHTTP1
import Logging

// TODO: update, can't get the https port after CONNECT
var proxyHostPortMap: [String: Int] = [:]

public struct ProxyServer {
    public init() {
        
    }
    
    public func start() async  {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.socket(SOL_SOCKET, SO_REUSEADDR), value: 1)
            .childChannelOption(ChannelOptions.socket(SOL_SOCKET, SO_REUSEADDR), value: 1)
            .childChannelInitializer { channel in
                let promise = channel.eventLoop.makePromise(of: Void.self)
                promise.completeWithTask {
                    try await channel.pipeline.addHandler(ByteToMessageHandler(HTTPRequestDecoder(leftOverBytesStrategy: .forwardBytes)), name: HandlerName.HTTPRequestDecoder.rawValue)
                    try await channel.pipeline.addHandler(HTTPResponseEncoder(), name: HandlerName.HTTPResponseEncoder.rawValue)
                    try await channel.pipeline.addHandler(HTTPHeadHandler(logger: Logger(label: "com.apple.nio-connect-proxy.ConnectHandler")), name: HandlerName.HTTPHeadHandler.rawValue)
                }
                return promise.futureResult
            }
        let logger = Logger(label: "com.apple.nio-connect-proxy.main")
        do {
            let address = try SocketAddress(ipAddress: "127.0.0.1", port: 8080)
            let channel = try await bootstrap.bind(to: address).get()
            logger.info("Listening on \(String(describing: channel.localAddress))")
        } catch {
            logger.error("Failed to bind 127.0.0.1:8080, \(error)")
        }
        
        
    }
}
