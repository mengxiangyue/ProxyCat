//
//  File.swift
//  
//
//  Created by xiangyue on 2023/1/4.
//

import Foundation
import NIO
import NIOHTTP1
import Logging
import NIOTLS
import NIOSSL

final class HTTPSUnwrapChannelCallbackHandler<ChannelHandler: ChannelInboundHandler & RemovableChannelHandler>
where ChannelHandler.InboundIn == HTTPServerRequestPart, ChannelHandler.OutboundOut == HTTPServerResponsePart {
    private weak var channelHandler: ChannelHandler?
    private var logger: Logger
    
    init(
        channelHandler: ChannelHandler,
        logger: Logger = .init(label: "tls")
    ) throws {
        self.logger = logger
        self.channelHandler = channelHandler
    }
}

extension HTTPSUnwrapChannelCallbackHandler: HTTPHeadChannelCallbackHandler {
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard let channelHandler = channelHandler else { return }
        
        guard case .head = channelHandler.unwrapInboundIn(data) else {
            self.logger.error("Invalid HTTP message type \(data)")
//            self.httpErrorAndClose(context: context) // mxy
            return
        }
        
        let headers = HTTPHeaders([("Content-Length", "0")])
        let head = HTTPResponseHead(version: .init(major: 1, minor: 1), status: .ok, headers: headers)
        context.write(channelHandler.wrapOutboundOut(.head(head)), promise: nil)
        context.writeAndFlush(channelHandler.wrapOutboundOut(.end(nil)), promise: nil)
        
        let sslContext: NIOSSLContext
        do {
            let certificateChain = try NIOSSLCertificate.fromPEMFile("/Users/xiangyue/Documents/github-repo/swift-nio-ssl/ssl/4/server.pem")
            sslContext = try NIOSSLContext(configuration: TLSConfiguration.makeServerConfiguration(
                certificateChain: certificateChain.map { .certificate($0) },
                privateKey: .file("/Users/xiangyue/Documents/github-repo/swift-nio-ssl/ssl/4/server.key.pem"))
            )
        } catch {
            self.logger.info("error \(error)")
            return
        }
            
        let sslServerHandler = NIOSSLServerHandler(context: sslContext)
        context.channel.pipeline.addHandler(sslServerHandler, name: HandlerName.SSLServerHandler.rawValue, position: .first)
            .flatMap {
                context.channel.pipeline.removeHandler(name: HandlerName.HTTPRequestDecoder.rawValue)
            }
            .flatMap {
                context.channel.pipeline.removeHandler(name: HandlerName.HTTPResponseEncoder.rawValue)
            }
            .flatMap {
                print(context.pipeline.debugDescription)
                return context.channel.pipeline.removeHandler(name: HandlerName.HTTPHeadHandler.rawValue)
            }
            .flatMap {
                context.channel.pipeline.configureHTTPServerPipeline(withErrorHandling: true)
            }
            .flatMap {
                context.channel.pipeline.addHandler(HTTPProxyHandler())
            }
            .whenComplete { result in
                switch result {
                case .success:
                    self.logger.info("success")
                case .failure(let error):
                    self.logger.info("error \(error)")
                }
            }
    }
}
