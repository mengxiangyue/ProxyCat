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
import WebSocketKit

final class WebSocketChannelCallbackHandler<ChannelHandler: ChannelInboundHandler & RemovableChannelHandler & HTTPHeadResponseSender>
where ChannelHandler.InboundIn == HTTPServerRequestPart, ChannelHandler.OutboundOut == HTTPServerResponsePart {
    
    private var receivedMessages: CircularBuffer<NIOAny> = CircularBuffer()
    
    private weak var channelHandler: ChannelHandler?
    private var logger: Logger
    private var isSetHttpHandler = false
    private var remoteServerChannel: Channel?
    private var webSocketClient: WebSocket?
    
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
        
//        connectTo(host: "121.40.165.18", port: 8800, context: context)
//        self.webSocketMessageForwardHandler.connectTo(host: "121.40.165.18", port: 8800, context: context)
        
        self.isSetHttpHandler = true
        self.receivedMessages.append(data)
        let websocketRecord = WebsocketRecord()
        // TODO: // add logic
        websocketRecord.requestHeaders = head.headers
        let promise: EventLoopPromise<Void>? = context.eventLoop.makePromise()
        self.setupUnwrapHTTPHandlers(context: context, websocketRecord: websocketRecord, promise: promise)
        
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
    
    private func setupUnwrapHTTPHandlers(context: ChannelHandlerContext, websocketRecord: WebsocketRecord, promise: EventLoopPromise<Void>? = nil) {
        let upgrader = NIOWebSocketServerUpgrader(
            shouldUpgrade: { (channel: Channel, head: HTTPRequestHead) in channel.eventLoop.makeSucceededFuture(HTTPHeaders()) },
            upgradePipelineHandler: { [unowned self] (channel: Channel, _: HTTPRequestHead) in
                channel.pipeline.addHandler(WebSocketMessageForwardHandler(websocketRecord: websocketRecord))
            })
        let upgradeConfiguration: NIOHTTPServerUpgradeConfiguration = (
                        upgraders: [ upgrader ],
                        completionHandler: { context in
//                            print("aaaaaaaaa", Unmanaged.passUnretained(context).toOpaque())
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
    
    
}

private final class WebSocketMessageForwardHandler: ChannelInboundHandler {
    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame

    private var awaitingClose: Bool = false
    
    private var proxy2ServerWebSocketClient: WebSocket?
    private weak var client2ProxyContext: ChannelHandlerContext?
    
    private let websocketRecord: WebsocketRecord
    init(websocketRecord: WebsocketRecord) {
        self.websocketRecord = websocketRecord
    }
    
    func handlerAdded(context: ChannelHandlerContext) {
        self.client2ProxyContext = context
//        connectTo(host: "121.40.165.18", port: 8800, context: context)
        connectTo(host: "127.0.0.1", port: 9999, context: context)
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
            let text = data.readString(length: data.readableBytes) ?? ""
            websocketRecord.messages.append(WebsocketMessageContent(type: .up, data: text))
            ProxyServerConfig.shared.proxyEventListener?.didReceive(websocketRecord: self.websocketRecord)
            proxy2ServerWebSocketClient?.send(text)
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
        print("mxy ---- \(#function)")
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
        print("mxy ---- \(#function)")
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
    
    deinit {
        self.proxy2ServerWebSocketClient?.close(promise: nil)
        self.proxy2ServerWebSocketClient = nil
    }
}

extension WebSocketMessageForwardHandler {
    func connectTo(host: String, port: Int, context: ChannelHandlerContext) {
        WebSocket.connect(to: "ws://\(host):\(port)", on: client2ProxyContext!.eventLoop) { [unowned self] ws in
            self.proxy2ServerWebSocketClient = ws
            ws.send("hello")
            ws.onText { [weak self] ws, string in
                print("receive the msg: ", string)
                guard let `self` = self else {
                    ws.close(promise: nil)
                    return
                }
                self.websocketRecord.messages.append(WebsocketMessageContent(type: .down, data: string))
                ProxyServerConfig.shared.proxyEventListener?.didReceive(websocketRecord: self.websocketRecord)
                var buffer = ByteBuffer()
                buffer.writeString(string)
                let frame = WebSocketFrame(fin: true, opcode: .text, data: buffer)
                self.client2ProxyContext?.eventLoop.submit { [unowned self] in
                    self.client2ProxyContext?.writeAndFlush(NIOAny(frame)).whenFailure { error in
                        print("erroor", error)
                        self.client2ProxyContext?.close(promise: nil)
                        ws.close(promise: nil)
                    }
                }
            }
            ws.onClose.whenComplete { [weak self] result in
                self?.client2ProxyContext?.close(promise: nil)
                switch result {
                case .success(let success):
                    print("111", success)
                case .failure(let failure):
                    print("111", failure)
                }
            }
        }
        .whenComplete { result in
            switch result {
            case .success(let success):
                print("success connect")
            case .failure(let failure):
                print("failed connect", failure)
            }
        }
    }
}
