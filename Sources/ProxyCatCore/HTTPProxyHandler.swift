//
//  File.swift
//  
//
//  Created by xiangyue on 2023/1/1.
//

import NIOCore
import NIOPosix
import NIOHTTP1
import Logging

final class HTTPProxyHandler: ChannelInboundHandler {
    enum State {
        case idle
        case pendingConnection(head: HTTPRequestHead)
        case connected
    }
    
    public typealias InboundIn = HTTPServerRequestPart
    public typealias OutboundOut = HTTPServerResponsePart
    
    private var buffer: ByteBuffer! = nil
    private var keepAlive = false
    private var isHttpsProxy: Bool
    private var state: State = .idle
    private var logger: Logger = .init(label: "HTTPProxyHandler")
    private var remoteServerChannel: Channel?
    private var remoteServerContext: ChannelHandlerContext?
    private var receivedMessagesFromClient: CircularBuffer<NIOAny> = CircularBuffer()
    
    init(isHttpsProxy: Bool) {
        self.isHttpsProxy = isHttpsProxy
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let reqPart = self.unwrapInboundIn(data)
        switch reqPart {
        case .head(let head):
            guard remoteServerContext == nil else {
                // there are some error
                return
            }
            let _data: HTTPClientRequestPart = .head(head)
            receivedMessagesFromClient.append(NIOAny(_data))
            connectTo(host: "www.gov.cn", port: 80, context: context)
        case .body(let body):
            let _data: HTTPClientRequestPart = .body(.byteBuffer(body))
            if let remoteServerContext = remoteServerContext {
                remoteServerContext.writeAndFlush(NIOAny(_data))
            } else {
                receivedMessagesFromClient.append(NIOAny(_data))
            }
        case .end(let headers):
            let _data: HTTPClientRequestPart = .end(headers)
            if let remoteServerContext = remoteServerContext {
                remoteServerContext.writeAndFlush(NIOAny(_data))
            } else {
                receivedMessagesFromClient.append(NIOAny(_data))
            }
        }
        return
        switch reqPart {
        case .head(let head):
            
//            print("HTTPProxyHandler http request: \(request.headers["Host"])")
            print("--------HTTPProxyHandler--------- \(head)")
            
            self.keepAlive = head.isKeepAlive
            
            var responseHead = httpResponseHead(request: head, status: HTTPResponseStatus.ok)
            if self.buffer == nil {
                self.buffer = context.channel.allocator.buffer(capacity: 0)
            }
            self.buffer.clear()
            self.buffer.writeString("hell world")
            responseHead.headers.add(name: "content-length", value: "\(self.buffer!.readableBytes)")
            let response = HTTPServerResponsePart.head(responseHead)
            context.write(self.wrapOutboundOut(response), promise: nil)
        case .body(var body):
            print("--------HTTPProxyHandler--------- body")
            let content = body.readString(length: body.readableBytes)
//            print("body-->\(content)")
            break
        case .end:
            print("--------HTTPProxyHandler--------- end")
            let content = HTTPServerResponsePart.body(.byteBuffer(buffer!.slice()))
            context.write(self.wrapOutboundOut(content), promise: nil)
            self.completeResponse(context, trailers: nil, promise: nil)
        }
    }
    
    private func completeResponse(_ context: ChannelHandlerContext, trailers: HTTPHeaders?, promise: EventLoopPromise<Void>?) {
        
        let promise = self.keepAlive ? promise : (promise ?? context.eventLoop.makePromise())
        if !self.keepAlive {
            promise!.futureResult.whenComplete { (_: Result<Void, Error>) in context.close(promise: nil) }
        }
        
        context.writeAndFlush(self.wrapOutboundOut(.end(trailers)), promise: promise)
    }
}

private func httpResponseHead(request: HTTPRequestHead, status: HTTPResponseStatus, headers: HTTPHeaders = HTTPHeaders()) -> HTTPResponseHead {
    var head = HTTPResponseHead(version: request.version, status: status, headers: headers)
    let connectionHeaders: [String] = head.headers[canonicalForm: "connection"].map { $0.lowercased() }
    
    if !connectionHeaders.contains("keep-alive") && !connectionHeaders.contains("close") {
        // the user hasn't pre-set either 'keep-alive' or 'close', so we might need to add headers
        
        switch (request.isKeepAlive, request.version.major, request.version.minor) {
        case (true, 1, 0):
            // HTTP/1.0 and the request has 'Connection: keep-alive', we should mirror that
            head.headers.add(name: "Connection", value: "keep-alive")
        case (false, 1, let n) where n >= 1:
            // HTTP/1.1 (or treated as such) and the request has 'Connection: close', we should mirror that
            head.headers.add(name: "Connection", value: "close")
        default:
            // we should match the default or are dealing with some HTTP that we don't support, let's leave as is
            ()
        }
    }
    return head
}

private extension HTTPProxyHandler {
    private func connectTo(host: String, port: Int, context: ChannelHandlerContext) {
        self.logger.info("Connecting to \(host):\(port)")
        let channelFuture = ClientBootstrap(group: context.eventLoop)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelInitializer { channel in
                channel.pipeline.addHTTPClientHandlers(position: .first, leftOverBytesStrategy: .fireError).flatMap {
                    channel.pipeline.addHandler(HTTPEchoHandler(contextReadyClosure: { context in self.remoteServerContext = context}))
                }
//                channel.pipeline.addHandler(HTTPRequestEncoder()).flatMap {
//                    channel.pipeline.addHandler(ByteToMessageHandler(HTTPResponseDecoder(leftOverBytesStrategy: .forwardBytes)))
//                }
            }
            .connect(host: host, port: port)

        channelFuture.whenSuccess { channel in
            self.logger.info("Connected to \(String(describing: channel.remoteAddress?.ipAddress ?? "unknown"))")
            self.remoteServerChannel = channel
            while !self.receivedMessagesFromClient.isEmpty {
                self.remoteServerContext?.writeAndFlush(self.receivedMessagesFromClient.removeFirst()).whenComplete({ result in
                    print("result ---- \(result)")
                })
            }
        }
        channelFuture.whenFailure { error in
            self.connectFailed(error: error, context: context)
        }
    }

    private func connectFailed(error: Error, context: ChannelHandlerContext) {
        self.logger.error("Connect failed: \(error)")
        if case .idle = state {
            httpErrorAndClose(context: context)
        }
        context.close(promise: nil)
        context.fireErrorCaught(error)
    }
    
    private func httpErrorAndClose(context: ChannelHandlerContext) {
        let headers = HTTPHeaders([("Content-Length", "0"), ("Connection", "close")])
        let head = HTTPResponseHead(version: .init(major: 1, minor: 1), status: .badRequest, headers: headers)
        context.write(self.wrapOutboundOut(.head(head)), promise: nil)
        context.writeAndFlush(self.wrapOutboundOut(.end(nil))).whenComplete { (_: Result<Void, Error>) in
            context.close(mode: .output, promise: nil)
        }
    }
}


private final class HTTPEchoHandler: ChannelInboundHandler {
    public typealias InboundIn = HTTPClientResponsePart
    public typealias OutboundOut = HTTPClientRequestPart
    
    var contextReadyClosure: (ChannelHandlerContext) -> Void
    
    init(contextReadyClosure: @escaping (ChannelHandlerContext) -> Void) {
        self.contextReadyClosure = contextReadyClosure
    }
    func channelRegistered(context: ChannelHandlerContext) {
        self.contextReadyClosure(context)
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {

        let clientResponse = self.unwrapInboundIn(data)
        
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

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("error: ", error)

        // As we are not really interested getting notified on success or failure we just pass nil as promise to
        // reduce allocations.
        context.close(promise: nil)
    }
}
