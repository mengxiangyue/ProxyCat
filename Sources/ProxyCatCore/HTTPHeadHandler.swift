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

final class HTTPHeadHandler {
    private var upgradeState: State {
        didSet {
            print("upgradeState->\(self.upgradeState)")
        }
    }
    private var logger: Logger
    private var proxyType = ProxyType.unknown
    
    init(logger: Logger) {
        self.upgradeState = .idle
        self.logger = logger
    }
}

extension HTTPHeadHandler {
    fileprivate enum State {
        case idle
        case beganConnectingToTargetServer
        case awaitingReceiveSourceClientEnd(targetServerChannel: Channel?)
        case awaitingTargetServerConnection(pendingBytes: [NIOAny])
        case upgradeComplete(pendingBytes: [NIOAny])
        case upgradeFailed
    }
}

extension HTTPHeadHandler: ChannelDuplexHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias InboundOut = HTTPClientRequestPart
    typealias OutboundIn = HTTPClientResponsePart
    typealias OutboundOut = HTTPServerResponsePart
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        print("channelRead->\(context.channel.pipeline) \(self.unwrapInboundIn(data))")
        switch self.upgradeState {
        case .idle:
            self.handleInitialMessage(context: context, data: self.unwrapInboundIn(data), sourceData: data)

        case .beganConnectingToTargetServer:
            // We got .end, we're still waiting on the connection
            if case .end = self.unwrapInboundIn(data) {
                self.upgradeState = .awaitingTargetServerConnection(pendingBytes: [])
                self.removeDecoder(context: context)
            }

        case .awaitingReceiveSourceClientEnd(let targetServerChannel):
            if case .end = self.unwrapInboundIn(data), case .https(let isTransprent) = proxyType  {
                if isTransprent {
                    self.upgradeState = .upgradeComplete(pendingBytes: [])
                    self.removeDecoder(context: context)
                    if let targetServerChannel = targetServerChannel {
                        self.glue(targetServerChannel, context: context)
                    }
                } else {
                    self.setupUnwrapSSLHandler(context: context)
                }
            }
        case .awaitingTargetServerConnection(var pendingBytes):
            // We've seen end, this must not be HTTP anymore. Danger, Will Robinson! Do not unwrap.
            self.upgradeState = .awaitingTargetServerConnection(pendingBytes: [])
            pendingBytes.append(data)
            self.upgradeState = .awaitingTargetServerConnection(pendingBytes: pendingBytes)

        case .upgradeComplete(pendingBytes: var pendingBytes):
            // We're currently delivering data, keep doing so.
            self.upgradeState = .upgradeComplete(pendingBytes: [])
            pendingBytes.append(data)
            self.upgradeState = .upgradeComplete(pendingBytes: pendingBytes)

        case .upgradeFailed:
            break
        }
    }
    
    private func handleInitialMessage(context: ChannelHandlerContext, data: InboundIn, sourceData: NIOAny) {
        guard case .head(let head) = data else {
//            self.logger.error("Invalid HTTP message type \(data)")
//            self.httpErrorAndClose(context: context)
            return
        }

        self.logger.info("\(head.method) \(head.uri) \(head.version)")
        
        switch head.method {
        case .CONNECT: // https over http, in order to create a tunel
            self.logger.info("Receive CONNECT request")
            let components = head.uri.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            let host = components.first!  // There will always be a first.
            let port = components.last.flatMap { Int($0, radix: 10) } ?? 80  // Port 80 if not specified
            if ["www.baidu.com"].contains(host) { // transprent https
                self.upgradeState = .beganConnectingToTargetServer
                self.proxyType = .https(isTransparent: true)
                self.HTTPSTransprentConnectTo(host: String(host), port: port, context: context)
            } else { // unwrap https request
                self.proxyType = .https(isTransparent: false)
                self.upgradeState = .awaitingReceiveSourceClientEnd(targetServerChannel: nil)
            }
        default:
            self.proxyType = .http
            self.upgradeState = .awaitingReceiveSourceClientEnd(targetServerChannel: nil)
            guard let url = URL(string: head.uri), let host = url.host else {
                self.logger.error("url parse error: \(head.uri)")
                self.httpErrorAndClose(context: context)
                return
            }
            let port = url.port ?? 80
            self.upgradeState = .beganConnectingToTargetServer
//            self.connectTo(host: String(host), port: port, context: context)
            let promise: EventLoopPromise<Void>? = context.eventLoop.makePromise()
            self.setupUnwrapHTTPHandlers(context: context, promise: promise)
            print("------111111111-----------")
            promise?.futureResult.whenComplete { [weak self] result in
                guard let `self` = self else { return }
                switch result {
                case .success:
                    context.pipeline.handler(type: HTTPServerPipelineHandler.self).whenComplete { result in
                        switch result {
                        case .success(let handler):
                            context.channel.pipeline.addHandler(self, position: .before(handler)).map {
                                print(context.channel.pipeline.debugDescription)
                                print("----\(context.channel.pipeline)")
                                context.fireChannelRead(sourceData)
//                                context.pipeline.removeHandler(self)
//                                context.channel.pipeline.write(sourceData)
                            }
                        case .failure(let error):
                            self.logger.error("xxx")
                        }
                    }
                case .failure(let error):
                    self.httpErrorAndClose(context: context)
                }
            }
            
        }
    }
    
    private func HTTPSTransprentConnectTo(host: String, port: Int, context: ChannelHandlerContext) {
        let channelFuture = ClientBootstrap(group: context.eventLoop)
            .connect(host: String(host), port: port)

        channelFuture.whenSuccess { channel in
            self.connectSucceeded(channel: channel, context: context)
        }
        channelFuture.whenFailure { error in
            self.connectFailed(error: error, context: context)
        }
    }

    private func connectSucceeded(channel: Channel, context: ChannelHandlerContext) {
        self.logger.info("Connected to \(String(describing: channel.remoteAddress))")

        switch self.upgradeState {
        case .beganConnectingToTargetServer:
            // Ok, we have a channel, let's wait for end.
            self.upgradeState = .awaitingReceiveSourceClientEnd(targetServerChannel: channel)

        case .awaitingTargetServerConnection(pendingBytes: let pendingBytes):
            // Upgrade complete! Begin gluing the connection together.
            self.upgradeState = .upgradeComplete(pendingBytes: pendingBytes)
            self.glue(channel, context: context)

        case .awaitingReceiveSourceClientEnd(let targetServerChannel):
            // This case is a logic error, close already connected peer channel.
            targetServerChannel?.close(mode: .all, promise: nil)
            context.close(promise: nil)

        case .idle, .upgradeFailed, .upgradeComplete:
            // These cases are logic errors, but let's be careful and just shut the connection.
            context.close(promise: nil)
        }
    }

    private func connectFailed(error: Error, context: ChannelHandlerContext) {
        self.logger.error("Connect failed: \(error)")

        switch self.upgradeState {
        case .beganConnectingToTargetServer, .awaitingTargetServerConnection:
            // We still have a somewhat active connection here in HTTP mode, and can report failure.
            self.httpErrorAndClose(context: context)

        case .awaitingReceiveSourceClientEnd(let targetServerChannel):
            // This case is a logic error, close already connected peer channel.
            targetServerChannel?.close(mode: .all, promise: nil)
            context.close(promise: nil)

        case .idle, .upgradeFailed, .upgradeComplete:
            // Most of these cases are logic errors, but let's be careful and just shut the connection.
            context.close(promise: nil)
        }

        context.fireErrorCaught(error)
    }
    
    private func httpErrorAndClose(context: ChannelHandlerContext) {
        self.upgradeState = .upgradeFailed

        let headers = HTTPHeaders([("Content-Length", "0"), ("Connection", "close")])
        let head = HTTPResponseHead(version: .init(major: 1, minor: 1), status: .badRequest, headers: headers)
        context.write(self.wrapOutboundOut(.head(head)), promise: nil)
        context.writeAndFlush(self.wrapOutboundOut(.end(nil))).whenComplete { (_: Result<Void, Error>) in
            context.close(mode: .output, promise: nil)
        }
    }
    
    private func glue(_ peerChannel: Channel, context: ChannelHandlerContext) {
        self.logger.debug("Gluing together \(ObjectIdentifier(context.channel)) and \(ObjectIdentifier(peerChannel))")

        sendUpgradeSuccessResponse(context: context)

        // Now remove the HTTP encoder.
        self.removeEncoder(context: context)

        // Now we need to glue our channel and the peer channel together.
        let (localGlue, peerGlue) = HTTPTransparentHandler.matchedPair()
        context.channel.pipeline.addHandler(localGlue).and(peerChannel.pipeline.addHandler(peerGlue)).whenComplete { result in
            switch result {
            case .success(_):
                context.pipeline.removeHandler(self, promise: nil)
            case .failure(_):
                // Close connected peer channel before closing our channel.
                peerChannel.close(mode: .all, promise: nil)
                context.close(promise: nil)
            }
        }
    }
    
    private func setupUnwrapSSLHandler(context: ChannelHandlerContext) {
        self.sendUpgradeSuccessResponse(context: context)
        self.logger.debug("setup unwrap https handler")
        let certificateChain: [NIOSSLCertificate]
        let sslContext: NIOSSLContext
        do {
            certificateChain = try NIOSSLCertificate.fromPEMFile("/Users/xiangyue/Documents/github-repo/swift-nio-ssl/ssl/4/server.pem")
            sslContext = try NIOSSLContext(configuration: TLSConfiguration.makeServerConfiguration(
                certificateChain: certificateChain.map { .certificate($0) },
                privateKey: .file("/Users/xiangyue/Documents/github-repo/swift-nio-ssl/ssl/4/server.key.pem")))
        } catch (let error) {
            self.logger.error("setup ssl context failed \(error)")
            self.httpErrorAndClose(context: context)
            return
        }
        
        let sslServerHandler = NIOSSLServerHandler(context: sslContext)
        context.channel.pipeline.addHandler(sslServerHandler, name: "ssl-handler", position: .first)
            .whenComplete { [weak self] result in
                switch result {
                case .success():
                    self?.logger.info("setup unwrap https handler successfully")
                    self?.setupUnwrapHTTPHandlers(context: context)
                case .failure(let error):
                    self?.logger.error("setup unwrap https handler failed: \(error)")
                    self?.httpErrorAndClose(context: context)
                }
            }
    }
    
    private func setupUnwrapHTTPHandlers(context: ChannelHandlerContext, promise: EventLoopPromise<Void>? = nil) {
        print("-------\n\(context.channel.pipeline.debugDescription)")
        context.channel.pipeline.removeHandler(name: HandlerName.HTTPRequestDecoder.rawValue).flatMap {
            context.pipeline.removeHandler(name: HandlerName.HTTPResponseEncoder.rawValue)
        }
//        .flatMap {
//            context.pipeline.removeHandler(name: HandlerName.HTTPHeadHandler.rawValue)
//        }
        .flatMap {
            context.channel.pipeline.configureHTTPServerPipeline(withErrorHandling: true)
        }
        .flatMap {
            context.channel.pipeline.addHandler(HTTPProxyHandler(), name: HandlerName.HTTPProxyHandler.rawValue)
        }
        .whenComplete { [weak self] result in
            switch result {
            case .success():
                print("------22222222-----------")
                self?.logger.info("setup unwrap https handler successfully")
                promise?.succeed(())
            case .failure(let error):
                self?.logger.error("setup unwrap https handler failed: \(error)")
                self?.httpErrorAndClose(context: context)
                promise?.fail(error)
            }
        }
    }
    
    private func sendUpgradeSuccessResponse(context: ChannelHandlerContext) {
        // Ok, upgrade has completed! We now need to begin the upgrade process.
        // First, send the 200 message.
        // This content-length header is MUST NOT, but we need to workaround NIO's insistence that we set one.
        let headers = HTTPHeaders([("Content-Length", "0")])
        let head = HTTPResponseHead(version: .init(major: 1, minor: 1), status: .ok, headers: headers)
        context.write(self.wrapOutboundOut(.head(head)), promise: nil)
        context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
    }
    
    private func removeDecoder(context: ChannelHandlerContext) {
        // We drop the future on the floor here as these handlers must all be in our own pipeline, and this should
        // therefore succeed fast.
        context.channel.pipeline.removeHandler(name: HandlerName.HTTPRequestDecoder.rawValue)
//        context.pipeline.context(handlerType: ByteToMessageHandler<HTTPRequestDecoder>.self).whenSuccess {
//            context.pipeline.removeHandler(context: $0, promise: nil)
//        }
    }

    private func removeEncoder(context: ChannelHandlerContext) {
        context.channel.pipeline.removeHandler(name: HandlerName.HTTPResponseEncoder.rawValue)
//        context.pipeline.context(handlerType: HTTPResponseEncoder.self).whenSuccess {
//            context.pipeline.removeHandler(context: $0, promise: nil)
//        }
    }
}


extension HTTPHeadHandler: RemovableChannelHandler {
    func removeHandler(context: ChannelHandlerContext, removalToken: ChannelHandlerContext.RemovalToken) {
        var didRead = false

        // We are being removed, and need to deliver any pending bytes we may have if we're upgrading.
        while case .upgradeComplete(var pendingBytes) = self.upgradeState, pendingBytes.count > 0 {
            // Avoid a CoW while we pull some data out.
            self.upgradeState = .upgradeComplete(pendingBytes: [])
            let nextRead = pendingBytes.removeFirst()
            self.upgradeState = .upgradeComplete(pendingBytes: pendingBytes)

            context.fireChannelRead(nextRead)
            didRead = true
        }

        if didRead {
            context.fireChannelReadComplete()
        }

        self.logger.debug("Removing \(self) from pipeline")
        context.leavePipeline(removalToken: removalToken)
    }
}
