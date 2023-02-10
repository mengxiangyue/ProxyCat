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
import NIOTLS
import NIOSSL
import Foundation

// TODO: update
extension HTTPRequestHead {
    var host: String? {
        let components = uri.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard let host = components.first else {
            return nil
        }
        return String(host)
    }
}

enum HTTPHeadHandleError: Error {
    case invalidHTTPMessageOrdering
    case invalidHTTPMessage
}

protocol HTTPHeadChannelCallbackHandler {
    func channelRead(context: ChannelHandlerContext, data: NIOAny)
    func removeHandler(context: ChannelHandlerContext, removalToken: ChannelHandlerContext.RemovalToken)
}

protocol HTTPHeadResponseSender {
    func sendUpgradeSuccessResponse(context: ChannelHandlerContext)
    func httpErrorAndClose(context: ChannelHandlerContext)
}

extension HTTPHeadChannelCallbackHandler {
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        context.fireChannelRead(data)
    }

    public func removeHandler(context: ChannelHandlerContext, removalToken: ChannelHandlerContext.RemovalToken) {
        context.leavePipeline(removalToken: removalToken)
    }
}


final class HTTPHeadHandler {
    private var logger: Logger
    private var callBackHandler: HTTPHeadChannelCallbackHandler?
    
    init(logger: Logger) {
        self.logger = logger
    }
}

extension HTTPHeadHandler: ChannelDuplexHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias InboundOut = HTTPClientRequestPart
    typealias OutboundIn = HTTPClientResponsePart
    typealias OutboundOut = HTTPServerResponsePart
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        if callBackHandler == nil {
            do {
                try setupCallBackHandler(context: context, data: self.unwrapInboundIn(data))
            } catch {
                logger.error("\(error.localizedDescription)")
                httpErrorAndClose(context: context)
                return
            }
        }
        callBackHandler?.channelRead(context: context, data: data)
    }
    
    private func setupCallBackHandler(context: ChannelHandlerContext, data: InboundIn) throws {
        guard case .head(let head) = data else {
            throw HTTPHeadHandleError.invalidHTTPMessage
        }

        self.logger.info(">> \(head.method) \(head.uri) \(head.version)")

        if head.method == .CONNECT { // if request is https, will receive the CONNECT first
            let components = head.uri.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            let host = components.first!  // There will always be a first.
            let port = components.last ?? "443"
            if let p = Int(port) {
                ProxyServerConfig.shared.proxyHostPortMap[String(host)] = p
            }
            if ProxyServerConfig.shared.checkTransparentForHost(String(host)) { // transprent https
                callBackHandler = try HTTPSTransparentChannelCallbackHandler(channelHandler: self)
            } else { // unwrap https request
                callBackHandler = try HTTPSUnwrapChannelCallbackHandler(channelHandler: self)
            }
        } else {
            if head.method == .GET, head.headers.first(name: "Upgrade") == "websocket" {
                callBackHandler = try WebSocketChannelCallbackHandler(channelHandler: self)
            } else {
                callBackHandler = try HTTPChannelCallbackHandler(channelHandler: self)
            }
        }
    }
    
    internal func httpErrorAndClose(context: ChannelHandlerContext) {
        let headers = HTTPHeaders([("Content-Length", "0"), ("Connection", "close")])
        let head = HTTPResponseHead(version: .init(major: 1, minor: 1), status: .badRequest, headers: headers)
        context.write(self.wrapOutboundOut(.head(head)), promise: nil)
        context.writeAndFlush(self.wrapOutboundOut(.end(nil))).whenComplete { (_: Result<Void, Error>) in
            context.close(mode: .output, promise: nil)
        }
    }
    
    internal func sendUpgradeSuccessResponse(context: ChannelHandlerContext) {
        // Ok, upgrade has completed! We now need to begin the upgrade process.
        // First, send the 200 message.
        // This content-length header is MUST NOT, but we need to workaround NIO's insistence that we set one.
        let headers = HTTPHeaders([("Content-Length", "0")])
        let head = HTTPResponseHead(version: .init(major: 1, minor: 1), status: .ok, headers: headers)
        context.write(self.wrapOutboundOut(.head(head)), promise: nil)
        context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
    }
}


extension HTTPHeadHandler: RemovableChannelHandler, HTTPHeadResponseSender {}
