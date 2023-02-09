//
//  HTTPProxyHandler.swift
//  
//
//  Created by xiangyue on 2023/1/1.
//

import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import Logging
import NIOSSL

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
    // the channel between the proxy and the real server
    private var remoteServerChannel: Channel?
    private var receivedMessagesFromClient: CircularBuffer<NIOAny> = CircularBuffer()
    
    let requestRecord = RequestRecord()
    
    init(isHttpsProxy: Bool) {
        self.isHttpsProxy = isHttpsProxy
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let reqPart = self.unwrapInboundIn(data)
        switch reqPart {
        case .head(let head):
            let components = head.headers["Host"].first?.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard let first = components?.first else {
                // TODO: throw error
                httpErrorAndClose(context: context)
                return
            }
            let host: String = String(first)
            let port: Int
            if let second = components?.last, let p = Int(second) {
                port = p
            } else {
                port = ProxyServerConfig.shared.proxyHostPortMap[host] ?? 80
            }
            requestRecord.requestHeaders = head.headers
            
            if false { // TODO: map local
                return
            }
            guard remoteServerChannel == nil else {
                // TODO: throw error
                httpErrorAndClose(context: context)
                return
            }
            
            let _data: HTTPClientRequestPart = .head(head)
            receivedMessagesFromClient.append(NIOAny(_data))
            
            self.logger.info("req >> \(host) \(port)")
            connectTo(host: host, port: port, context: context)
        case .body(let body):
            let _data: HTTPClientRequestPart = .body(.byteBuffer(body))
            if let remoteServerChannel = remoteServerChannel {
                remoteServerChannel.write(NIOAny(_data)).whenFailure { error in
                    // TODO: should log the error
                }
            } else {
                receivedMessagesFromClient.append(NIOAny(_data))
            }
        case .end(let headers):
            // TODO: if map local, just return the fake response data and return.
            let _data: HTTPClientRequestPart = .end(headers)
            if let remoteServerChannel = remoteServerChannel {
                remoteServerChannel.writeAndFlush(NIOAny(_data)).whenFailure { error in
                    // TODO: should log the error
                }
            } else {
                receivedMessagesFromClient.append(NIOAny(_data))
            }
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
            .channelInitializer { [unowned self] channel in
                let messageForwardHandler = MessageForwardHandler(proxyContext: context, requestRecord: self.requestRecord)
                if self.isHttpsProxy {
                    let tlsConfiguration = TLSConfiguration.makeClientConfiguration()
                    let sslContext = try! NIOSSLContext(configuration: tlsConfiguration)
                    let openSslHandler = try! NIOSSLClientHandler(context: sslContext, serverHostname: host)
                    return channel.pipeline.addHandler(openSslHandler).flatMap {
                        channel.pipeline.addHTTPClientHandlers()
                    }.flatMap {
                        channel.pipeline.addHandler(messageForwardHandler)
                    }
                } else {
                    return channel.pipeline.addHTTPClientHandlers(position: .first, leftOverBytesStrategy: .fireError).flatMap {
                        channel.pipeline.addHandler(messageForwardHandler)
                    }
                }
            }
            .connect(host: host, port: port)

        channelFuture.whenSuccess { [unowned self]channel in
            self.logger.info("Connected to \(String(describing: channel.remoteAddress?.ipAddress ?? "unknown"))")
            self.remoteServerChannel = channel
            while !self.receivedMessagesFromClient.isEmpty {
                self.remoteServerChannel?.writeAndFlush(self.receivedMessagesFromClient.removeFirst()).whenFailure { error in
                    // TODO: should log the error
                }
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
        
        remoteServerChannel?.close(mode: .all, promise: nil)
    }
}


private final class MessageForwardHandler: ChannelInboundHandler {
    public typealias InboundIn = HTTPClientResponsePart
    public typealias OutboundOut = HTTPClientRequestPart
    
    // the context between the source client and proxy
    private let proxyContext: ChannelHandlerContext
    private let requestRecord: RequestRecord
    
    init(proxyContext: ChannelHandlerContext, requestRecord: RequestRecord) {
        self.proxyContext = proxyContext
        self.requestRecord = requestRecord
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let clientResponse = self.unwrapInboundIn(data)
        switch clientResponse {
        case .head(let responseHead):
            print("Received status: \(responseHead.status)")
            requestRecord.responseHeaders = responseHead.headers
            requestRecord.version = responseHead.version
            let _data: HTTPServerResponsePart = .head(responseHead)
            proxyContext.write(NIOAny(_data)).whenFailure { error in
                // TODO: should log the error
            }
        case .body(let byteBuffer):
            let string = String(buffer: byteBuffer)
            print("Received: '\(string)' back from the server.")
            var tempBuffer = byteBuffer
            requestRecord.responseBody.writeBuffer(&tempBuffer)
            let _data: HTTPServerResponsePart = .body(.byteBuffer(byteBuffer))
            proxyContext.write(NIOAny(_data)).whenFailure { error in
                // TODO: should log the error
            }
        case .end(let headers):
            print("Closing channel.")
            context.close(promise: nil)
            ProxyServerConfig.shared.proxyEventListener?.didReceive(record: requestRecord)
            let _data: HTTPServerResponsePart = .end(headers)
            proxyContext.writeAndFlush(NIOAny(_data))
                .whenComplete({ [unowned self] result in
                    switch result {
                    case .success:
                        proxyContext.close(promise: nil)
                    case .failure(let error):
                        // TODO: should log the error
                        break
                    }
                })
        }
    }

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("error: ", error)

        // As we are not really interested getting notified on success or failure we just pass nil as promise to
        // reduce allocations.
        context.close(promise: nil)
        proxyContext.close(promise: nil)
    }
}
