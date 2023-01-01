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

public struct ProxyServer {
    public init() {
        
    }
    
    public func start() {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.socket(SOL_SOCKET, SO_REUSEADDR), value: 1)
            .childChannelOption(ChannelOptions.socket(SOL_SOCKET, SO_REUSEADDR), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.addHandler(ByteToMessageHandler(HTTPRequestDecoder(leftOverBytesStrategy: .forwardBytes)), name: HandlerName.HTTPRequestDecoder.rawValue)
                    .flatMap { channel.pipeline.addHandler(HTTPResponseEncoder(), name: HandlerName.HTTPResponseEncoder.rawValue) }
                    .flatMap { channel.pipeline.addHandler(HTTPHeadHandler(logger: Logger(label: "com.apple.nio-connect-proxy.ConnectHandler")), name: HandlerName.HTTPHeadHandler.rawValue) }
            }
        
        bootstrap.bind(to: try! SocketAddress(ipAddress: "127.0.0.1", port: 8080)).whenComplete { result in
            // Need to create this here for thread-safety purposes
            let logger = Logger(label: "com.apple.nio-connect-proxy.main")
            
            switch result {
            case .success(let channel):
                logger.info("Listening on \(String(describing: channel.localAddress))")
            case .failure(let error):
                logger.error("Failed to bind 127.0.0.1:8080, \(error)")
            }
        }
        
    }
}
