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

final class HTTPChannelCallbackHandler<ChannelHandler: ChannelInboundHandler & RemovableChannelHandler & HTTPHeadResponseSender>
where ChannelHandler.InboundIn == HTTPServerRequestPart, ChannelHandler.OutboundOut == HTTPServerResponsePart {
    
    private var receivedMessages: CircularBuffer<NIOAny> = CircularBuffer()
    
    private weak var channelHandler: ChannelHandler?
    private var logger: Logger
    private var isSetHttpHandler = false
    
    init(
        channelHandler: ChannelHandler,
        logger: Logger = .init(label: "http-channel-callback")
    ) throws {
        self.logger = logger
        self.channelHandler = channelHandler
    }
}

extension HTTPChannelCallbackHandler: HTTPHeadChannelCallbackHandler {
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        if isSetHttpHandler {
            receivedMessages.append(data)
            return
        }
        guard let channelHandler = channelHandler else { return }
        let reqPart = self.channelHandler?.unwrapInboundIn(data)
        guard case .head(let head) = reqPart else {
            self.logger.error("Invalid HTTP message type \(data)")
            channelHandler.httpErrorAndClose(context: context)
            return
        }
        
        self.logger.info("\(head.method) \(head.uri) \(head.version)")
        
        self.isSetHttpHandler = true
        self.receivedMessages.append(data)
        let promise: EventLoopPromise<Void>? = context.eventLoop.makePromise()
        self.setupUnwrapHTTPHandlers(context: context, promise: promise)
        promise?.futureResult.whenComplete { [weak self] result in
            guard let `self` = self else { return }
            switch result {
            case .success:
                while !self.receivedMessages.isEmpty {
                    context.fireChannelRead(self.receivedMessages.removeFirst())
                }
                _ = context.pipeline.removeHandler(channelHandler)
            case .failure(let error):
                self.logger.info("error \(error)")
                channelHandler.httpErrorAndClose(context: context)
            }
        }
    }
    
    private func setupUnwrapHTTPHandlers(context: ChannelHandlerContext, promise: EventLoopPromise<Void>? = nil) {
        let future = context.pipeline.removeHandler(name: HandlerName.HTTPRequestDecoder.rawValue)
            .flatMap {
                context.pipeline.removeHandler(name: HandlerName.HTTPResponseEncoder.rawValue)
            }
            .flatMap {
                self._configureHTTPServerPipeline(context: context)
            }
            .flatMap {
                context.channel.pipeline.addHandler(HTTPProxyHandler(isHttpsProxy: false), name: HandlerName.HTTPProxyHandler.rawValue)
            }
        future
            .whenComplete { [weak self] result in
                switch result {
                case .success():
                    self?.logger.info("setup unwrap https handler successfully")
                    promise?.succeed(())
                case .failure(let error):
                    self?.logger.error("setup unwrap https handler failed: \(error)")
                    self?.channelHandler?.httpErrorAndClose(context: context)
                    promise?.fail(error)
                }
            }
    }
    
    // copy from NIOHTTP1/HTTPPipelineSetup and do some modification
    private func _configureHTTPServerPipeline(context: ChannelHandlerContext,
                                              position: ChannelPipeline.Position = .last,
                                              withPipeliningAssistance pipelining: Bool = true,
                                              withServerUpgrade upgrade: NIOHTTPServerUpgradeConfiguration? = nil,
                                              withErrorHandling errorHandling: Bool = true,
                                              withOutboundHeaderValidation headerValidation: Bool = true) ->  EventLoopFuture<Void> {
        
        let responseEncoder = HTTPResponseEncoder()
        let requestDecoder = HTTPRequestDecoder(leftOverBytesStrategy: upgrade == nil ? .dropBytes : .forwardBytes)
        
        var handlers: [RemovableChannelHandler] = [responseEncoder, ByteToMessageHandler(requestDecoder)]
        //              [I] ↓↑ [O]
        //  HTTPHeadHandler ↓↑ HTTPHeadHandler [HTTPHeadHandler]
        // right now handlers likes this, need to add two handlers before it and some handlers after it,
        return context.pipeline.addHandlers(handlers, position: .first).flatMap {
            handlers.removeAll()
            
            if pipelining {
                handlers.append(HTTPServerPipelineHandler())
            }
            
            if headerValidation {
                handlers.append(NIOHTTPResponseHeadersValidator())
            }
            
            if errorHandling {
                handlers.append(HTTPServerProtocolErrorHandler())
            }
            
            if let (upgraders, completionHandler) = upgrade {
                let upgrader = HTTPServerUpgradeHandler(upgraders: upgraders,
                                                        httpEncoder: responseEncoder,
                                                        extraHTTPHandlers: Array(handlers.dropFirst()),
                                                        upgradeCompletionHandler: completionHandler)
                handlers.append(upgrader)
            }
            return context.pipeline.addHandlers(handlers)
        }
    }
}
