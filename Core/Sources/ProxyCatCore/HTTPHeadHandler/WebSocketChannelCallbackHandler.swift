//
//  WebSocketChannelCallbackHandler.swift
//  
//
//  Created by xiangyue on 2023/2/10.
//

import Foundation
import NIO
import NIOHTTP1
import Logging
import NIOWebSocket

final class WebSocketChannelCallbackHandler<ChannelHandler: ChannelInboundHandler & RemovableChannelHandler & HTTPHeadResponseSender>
where ChannelHandler.InboundIn == HTTPServerRequestPart, ChannelHandler.OutboundOut == HTTPServerResponsePart {
    
    private var receivedMessages: CircularBuffer<NIOAny> = CircularBuffer()
    
    private weak var channelHandler: ChannelHandler?
    private var logger: Logger
    private var isSetHttpHandler = false
    private var remoteServerChannel: Channel?
    private var client2ProxyContext: ChannelHandlerContext?
    
    private lazy var webSocketTimeHandler: WebSocketTimeHandler = WebSocketTimeHandler(contextDidCreate: { context in
        self.client2ProxyContext = context
    })
    
    private lazy var webSocketPingPongHandler: WebSocketPingPongHandler =  WebSocketPingPongHandler(client2ProxyContext: self.client2ProxyContext, contextDidCreate: { context in
        self.webSocketTimeHandler.proxy2ServerContext = context
    })
    
    init(
        channelHandler: ChannelHandler,
        logger: Logger = .init(label: "websocket")
    ) throws {
        self.logger = logger
        self.channelHandler = channelHandler
    }
}

extension WebSocketChannelCallbackHandler: HTTPHeadChannelCallbackHandler {
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        print("WebSocketChannelCallbackHandler", data)
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
        
        connectTo(host: "121.40.165.18", port: 8800, context: context)
        
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
        let upgrader = NIOWebSocketServerUpgrader(shouldUpgrade: { (channel: Channel, head: HTTPRequestHead) in channel.eventLoop.makeSucceededFuture(HTTPHeaders()) },
                                         upgradePipelineHandler: { (channel: Channel, _: HTTPRequestHead) in
            channel.pipeline.addHandler(self.webSocketTimeHandler)
                                         })
        let upgradeConfiguration: NIOHTTPServerUpgradeConfiguration = (
                        upgraders: [ upgrader ],
                        completionHandler: { context in
                            print("aaaaaaaaa", Unmanaged.passUnretained(context).toOpaque())
                            context.pipeline.removeHandler(name: HandlerName.HTTPHeadHandler.rawValue)
                                .whenFailure { error in
                                    // TODO:
                                }
                        }
                    )
        
        let future = context.pipeline.removeHandler(name: HandlerName.HTTPRequestDecoder.rawValue)
            .flatMap {
                context.pipeline.removeHandler(name: HandlerName.HTTPResponseEncoder.rawValue)
            }
            .flatMap {
                self._configureHTTPServerPipeline(context: context, withServerUpgrade: upgradeConfiguration)
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
        let byteToMessageHandler = ByteToMessageHandler(requestDecoder)
        
        var handlers: [RemovableChannelHandler] = [responseEncoder, byteToMessageHandler]
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
                var removedHandler = handlers
                removedHandler.append(byteToMessageHandler)
                let upgrader = HTTPServerUpgradeHandler(upgraders: upgraders,
                                                        httpEncoder: responseEncoder,
                                                        extraHTTPHandlers: removedHandler,
                                                        upgradeCompletionHandler: completionHandler)
                handlers.append(upgrader)
            }
            return context.pipeline.addHandlers(handlers)
        }
    }
    
    private func connectTo(host: String, port: Int, context: ChannelHandlerContext) {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let channelFuture = ClientBootstrap(group: group)
            // Enable SO_REUSEADDR.
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelInitializer { channel in
                
                let httpHandler = HTTPInitialRequestHandler(host: host, port: port)

                let websocketUpgrader = NIOWebSocketClientUpgrader(requestKey: "OfS0wDaT5NoxF2gqm7Zj2YtetzM=",
                                                                   upgradePipelineHandler: { (channel: Channel, _: HTTPResponseHead) in
                    channel.pipeline.addHandler(self.webSocketPingPongHandler)
                })

                let config: NIOHTTPClientUpgradeConfiguration = (
                    upgraders: [ websocketUpgrader ],
                    completionHandler: { _ in
                        channel.pipeline.removeHandler(httpHandler, promise: nil)
                })

                return channel.pipeline.addHTTPClientHandlers(withClientUpgrade: config).flatMap {
                    channel.pipeline.addHandler(httpHandler)
                }
            }
            .connect(host: host, port: port)
        
        channelFuture.whenSuccess { [unowned self] channel in
            self.logger.info("Connected to \(String(describing: channel.remoteAddress?.ipAddress ?? "unknown"))")
            self.remoteServerChannel = channel
//            while !self.receivedMessagesFromClient.isEmpty {
//                self.remoteServerChannel?.writeAndFlush(self.receivedMessagesFromClient.removeFirst()).whenFailure { error in
//                    // TODO: should log the error
//                }
//            }
        }
        channelFuture.whenFailure { error in
            self.logger.info("error: \(error)")
//            self.connectFailed(error: error, context: context)
        }
        
    }
}

private final class WebSocketTimeHandler: ChannelInboundHandler {
    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame

    private var awaitingClose: Bool = false
    
    private var contextDidCreate: (ChannelHandlerContext) -> Void
    var proxy2ServerContext: ChannelHandlerContext?
    
    init(contextDidCreate: @escaping (ChannelHandlerContext) -> Void) {
        self.contextDidCreate = contextDidCreate
    }
    
    func handlerAdded(context: ChannelHandlerContext) {
        print("aaaaaaaaa", Unmanaged.passUnretained(context).toOpaque())
        contextDidCreate(context)
    }
    
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = self.unwrapInboundIn(data)

        switch frame.opcode {
        case .connectionClose:
            self.receivedClose(context: context, frame: frame)
        case .ping:
            self.pong(context: context, frame: frame)
        case .text:
            var data = frame.unmaskedData
//            let text = data.readString(length: data.readableBytes) ?? ""
//            var buffer = context.channel.allocator.buffer(capacity: 12)
//            buffer.writeString(text)
//            print("mxy====", text)

//            let frame = WebSocketFrame(fin: true, opcode: .text, data: buffer)
//            context.writeAndFlush(self.wrapOutboundOut(frame)).whenFailure { (_: Error) in
//                context.close(promise: nil)
//            }
            proxy2ServerContext?.eventLoop.submit {
                self.proxy2ServerContext?.writeAndFlush(self.wrapOutboundOut(frame)).whenFailure({ error in
                    print("error111", error)
                })
            }
//            print("BBBBBBBB1", Unmanaged.passUnretained(proxy2ServerContext!).toOpaque())
//            let buffer1 = context.channel.allocator.buffer(string: "xxxxxxxxxxxxx")
//            let frame = WebSocketFrame(fin: true, opcode: .text, data: buffer1)
//            proxy2ServerContext?.writeAndFlush(self.wrapOutboundOut(frame)).whenFailure({ error in
//                print("error111", error)
//            })
        case .binary, .continuation, .pong:
            // We ignore these frames.
            break
        default:
            // Unknown frames are errors.
            self.closeOnError(context: context)
        }
    }

    public func channelReadComplete(context: ChannelHandlerContext) {
        context.flush()
    }

    private func receivedClose(context: ChannelHandlerContext, frame: WebSocketFrame) {
        // Handle a received close frame. In websockets, we're just going to send the close
        // frame and then close, unless we already sent our own close frame.
        if awaitingClose {
            // Cool, we started the close and were waiting for the user. We're done.
            context.close(promise: nil)
        } else {
            // This is an unsolicited close. We're going to send a response frame and
            // then, when we've sent it, close up shop. We should send back the close code the remote
            // peer sent us, unless they didn't send one at all.
            var data = frame.unmaskedData
            let closeDataCode = data.readSlice(length: 2) ?? ByteBuffer()
            let closeFrame = WebSocketFrame(fin: true, opcode: .connectionClose, data: closeDataCode)
            _ = context.write(self.wrapOutboundOut(closeFrame)).map { () in
                context.close(promise: nil)
            }
        }
    }

    private func pong(context: ChannelHandlerContext, frame: WebSocketFrame) {
        var frameData = frame.data
        let maskingKey = frame.maskKey

        if let maskingKey = maskingKey {
            frameData.webSocketUnmask(maskingKey)
        }

        let responseFrame = WebSocketFrame(fin: true, opcode: .pong, data: frameData)
        context.write(self.wrapOutboundOut(responseFrame), promise: nil)
    }

    private func closeOnError(context: ChannelHandlerContext) {
        // We have hit an error, we want to close. We do that by sending a close frame and then
        // shutting down the write side of the connection.
        var data = context.channel.allocator.buffer(capacity: 2)
        data.write(webSocketErrorCode: .protocolError)
        let frame = WebSocketFrame(fin: true, opcode: .connectionClose, data: data)
        context.write(self.wrapOutboundOut(frame)).whenComplete { (_: Result<Void, Error>) in
            context.close(mode: .output, promise: nil)
        }
        awaitingClose = true
    }
}

private final class WebSocketPingPongHandler: ChannelInboundHandler {
    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame
    
    let testFrameData: String = "Hello World"
    
    // the context between the source client and proxy
    private let client2ProxyContext: ChannelHandlerContext?
    private var contextDidCreate: (ChannelHandlerContext) -> Void
    
    init(client2ProxyContext: ChannelHandlerContext?, contextDidCreate: @escaping (ChannelHandlerContext) -> Void) {
        self.client2ProxyContext = client2ProxyContext
        self.contextDidCreate = contextDidCreate
    }
    
    // This is being hit, channel active won't be called as it is already added.
    public func handlerAdded(context: ChannelHandlerContext) {
        print("WebSocket handler added.")
        self.pingTestFrameData(context: context)
        print("BBBBBBBB", Unmanaged.passUnretained(context).toOpaque())
        contextDidCreate(context)
    }

    public func handlerRemoved(context: ChannelHandlerContext) {
        print("WebSocket handler removed.")
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = self.unwrapInboundIn(data)
        
        switch frame.opcode {
        case .pong:
            self.pong(context: context, frame: frame)
        case .text:
            var data = frame.unmaskedData
            let text = data.readString(length: data.readableBytes) ?? ""
            print("Websocket: Received \(text)")
            print("xxxx context", context)
            client2ProxyContext?.eventLoop.submit { [unowned self] in
                self.client2ProxyContext?.writeAndFlush(self.wrapOutboundOut(frame)).whenFailure { (_: Error) in
                    context.close(promise: nil)
                }
            }
        case .connectionClose:
            self.receivedClose(context: context, frame: frame)
        case .binary, .continuation, .ping:
            // We ignore these frames.
            break
        default:
            // Unknown frames are errors.
            self.closeOnError(context: context)
        }
    }
    
//    public func channelReadComplete(context: ChannelHandlerContext) {
//        context.flush()
//    }

    private func receivedClose(context: ChannelHandlerContext, frame: WebSocketFrame) {
        // Handle a received close frame. We're just going to close.
        print("Received Close instruction from server")
        context.close(promise: nil)
    }
    
    private func pingTestFrameData(context: ChannelHandlerContext) {
        let buffer = context.channel.allocator.buffer(string: self.testFrameData)
        let frame = WebSocketFrame(fin: true, opcode: .ping, data: buffer)
        context.write(self.wrapOutboundOut(frame), promise: nil)
    }
    
    private func pong(context: ChannelHandlerContext, frame: WebSocketFrame) {
        var frameData = frame.data
        if let frameDataString = frameData.readString(length: self.testFrameData.count) {
            print("Websocket: Received: \(frameDataString)")
        }
    }
    
    private func closeOnError(context: ChannelHandlerContext) {
        // We have hit an error, we want to close. We do that by sending a close frame and then
        // shutting down the write side of the connection. The server will respond with a close of its own.
        var data = context.channel.allocator.buffer(capacity: 2)
        data.write(webSocketErrorCode: .protocolError)
        let frame = WebSocketFrame(fin: true, opcode: .connectionClose, data: data)
        context.write(self.wrapOutboundOut(frame)).whenComplete { (_: Result<Void, Error>) in
            context.close(mode: .output, promise: nil)
        }
    }
}


// The HTTP handler to be used to initiate the request.
// This initial request will be adapted by the WebSocket upgrader to contain the upgrade header parameters.
// Channel read will only be called if the upgrade fails.

private final class HTTPInitialRequestHandler: ChannelInboundHandler, RemovableChannelHandler {
    public typealias InboundIn = HTTPClientResponsePart
    public typealias OutboundOut = HTTPClientRequestPart

    let host: String
    let port: Int
    
    public init(host: String, port: Int) {
        self.host = host
        self.port = port
    }
    
    public func channelActive(context: ChannelHandlerContext) {
        print("Client connected to \(context.remoteAddress!)")

        // We are connected. It's time to send the message to the server to initialize the upgrade dance.
        var headers = HTTPHeaders()
        headers.add(name: "Host", value: "\(host):\(port)")
        headers.add(name: "Content-Type", value: "text/plain; charset=utf-8")
        headers.add(name: "Content-Length", value: "\(0)")
        
        let requestHead = HTTPRequestHead(version: .http1_1,
                                          method: .GET,
                                          uri: "/",
                                          headers: headers)
        
        context.write(self.wrapOutboundOut(.head(requestHead)), promise: nil)
        
        let body = HTTPClientRequestPart.body(.byteBuffer(ByteBuffer()))
        context.write(self.wrapOutboundOut(body), promise: nil)
        
        context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
    }
    
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        
        let clientResponse = self.unwrapInboundIn(data)
        
        print("Upgrade failed")
        
        switch clientResponse {
        case .head(let responseHead):
            print("Received status: \(responseHead.status)")
        case .body(let byteBuffer):
            let string = String(buffer: byteBuffer)
            print("Received: '\(string)' back from the server.")
        case .end:
            print("Closing channel.")
            context.close(promise: nil)
        }
    }
    
    public func handlerRemoved(context: ChannelHandlerContext) {
        print("HTTP handler removed.")
    }
    
    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("error: ", error)
        
        // As we are not really interested getting notified on success or failure
        // we just pass nil as promise to reduce allocations.
        context.close(promise: nil)
    }
}
