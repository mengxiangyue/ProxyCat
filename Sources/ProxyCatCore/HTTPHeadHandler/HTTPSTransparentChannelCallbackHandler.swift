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

final class HTTPSTransparentChannelCallbackHandler<ChannelHandler: ChannelInboundHandler & RemovableChannelHandler & HTTPHeadResponseSender>
where ChannelHandler.InboundIn == HTTPServerRequestPart, ChannelHandler.OutboundOut == HTTPServerResponsePart {
    private var upgradeState: State
    private weak var channelHandler: ChannelHandler?
    private var logger: Logger
    
    init(
        channelHandler: ChannelHandler,
        logger: Logger = .init(label: "tls")
    ) throws {
        self.upgradeState = .idle
        self.logger = logger
        self.channelHandler = channelHandler
    }
}

private extension HTTPSTransparentChannelCallbackHandler {
    enum State {
        case idle
        case beganConnecting
        case awaitingEnd(connectResult: Channel)
        case awaitingConnection(pendingBytes: [NIOAny])
        case upgradeComplete(pendingBytes: [NIOAny])
        case upgradeFailed
    }
}

extension HTTPSTransparentChannelCallbackHandler: HTTPHeadChannelCallbackHandler {}

extension HTTPSTransparentChannelCallbackHandler {
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard let channelHandler = channelHandler else { return }
        
        switch self.upgradeState {
        case .idle:
            self.handleInitialMessage(context: context, data: channelHandler.unwrapInboundIn(data))
            
        case .beganConnecting:
            // We got .end, we're still waiting on the connection
            if case .end = channelHandler.unwrapInboundIn(data) {
                self.upgradeState = .awaitingConnection(pendingBytes: [])
                self.removeDecoder(context: context)
            }
            
        case .awaitingEnd(let peerChannel):
            if case .end = channelHandler.unwrapInboundIn(data) {
                // Upgrade has completed!
                self.upgradeState = .upgradeComplete(pendingBytes: [])
                self.removeDecoder(context: context)
                self.glue(peerChannel, context: context)
            }
            
        case .awaitingConnection(var pendingBytes):
            // We've seen end, this must not be HTTP anymore. Danger, Will Robinson! Do not unwrap.
            self.upgradeState = .awaitingConnection(pendingBytes: [])
            pendingBytes.append(data)
            self.upgradeState = .awaitingConnection(pendingBytes: pendingBytes)
            
        case .upgradeComplete(pendingBytes: var pendingBytes):
            // We're currently delivering data, keep doing so.
            self.upgradeState = .upgradeComplete(pendingBytes: [])
            pendingBytes.append(data)
            self.upgradeState = .upgradeComplete(pendingBytes: pendingBytes)
            
        case .upgradeFailed:
            break
        }
    }
}

extension HTTPSTransparentChannelCallbackHandler {
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

private extension HTTPSTransparentChannelCallbackHandler {
    private func handleInitialMessage(context: ChannelHandlerContext, data: ChannelHandler.InboundIn) {
        guard case .head(let head) = data else {
            self.logger.error("Invalid HTTP message type \(data)")
            self.channelHandler?.httpErrorAndClose(context: context)
            return
        }
        
        guard head.method == .CONNECT else {
            self.logger.error("Invalid HTTP method: \(head.method)")
            self.channelHandler?.httpErrorAndClose(context: context)
            return
        }
        
        let components = head.uri.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard components.count > 1 else {
            self.logger.error("Invalid HTTP message uri \(head.uri)")
            self.channelHandler?.httpErrorAndClose(context: context)
            return
        }
        
        let host = components[0..<components.count - 1].joined(separator: ":")
        let port = components.last.flatMap { Int($0, radix: 10) } ?? 80  // Port 80 if not specified
        
        self.upgradeState = .beganConnecting
        self.connectTo(host: String(host), port: port, context: context)
    }
    
    private func connectTo(host: String, port: Int, context: ChannelHandlerContext) {
        self.logger.info("Connecting to \(host):\(port)")
        
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
        self.logger.info("Connected to \(String(describing: channel.remoteAddress?.ipAddress ?? "unknown")); state \(upgradeState)")
        
        switch self.upgradeState {
        case .beganConnecting:
            // Ok, we have a channel, let's wait for end.
            self.upgradeState = .awaitingEnd(connectResult: channel)
            
        case .awaitingConnection(pendingBytes: let pendingBytes):
            // Upgrade complete! Begin gluing the connection together.
            self.upgradeState = .upgradeComplete(pendingBytes: pendingBytes)
            self.glue(channel, context: context)
            
        case .awaitingEnd(let peerChannel):
            // This case is a logic error, close already connected peer channel.
            peerChannel.close(mode: .all, promise: nil)
            context.close(promise: nil)
            
        case .idle, .upgradeFailed, .upgradeComplete:
            // These cases are logic errors, but let's be careful and just shut the connection.
            context.close(promise: nil)
        }
    }
    
    private func connectFailed(error: Error, context: ChannelHandlerContext) {
        self.logger.error("Connect failed: \(error)")
        
        switch self.upgradeState {
        case .beganConnecting, .awaitingConnection:
            // We still have a somewhat active connection here in HTTP mode, and can report failure.
            self.channelHandler?.httpErrorAndClose(context: context)
            
        case .awaitingEnd(let peerChannel):
            // This case is a logic error, close already connected peer channel.
            peerChannel.close(mode: .all, promise: nil)
            context.close(promise: nil)
            
        case .idle, .upgradeFailed, .upgradeComplete:
            // Most of these cases are logic errors, but let's be careful and just shut the connection.
            context.close(promise: nil)
        }
        
        context.fireErrorCaught(error)
    }
    
    private func glue(_ peerChannel: Channel, context: ChannelHandlerContext) {
        self.logger.debug("Gluing together \(ObjectIdentifier(context.channel)) and \(ObjectIdentifier(peerChannel))")
        
        guard let channelHandler = channelHandler else { return }
        channelHandler.sendUpgradeSuccessResponse(context: context)
        
        // Now remove the HTTP encoder.
        self.removeEncoder(context: context)
        
        // Now we need to glue our channel and the peer channel together.
        let (localGlue, peerGlue) = HTTPSGuleHandler.matchedPair()
        
        context.channel.pipeline.addHandler(localGlue).and(peerChannel.pipeline.addHandler(peerGlue)).whenComplete { result in
            switch result {
            case .success(_):
                context.pipeline.removeHandler(channelHandler, promise: nil)
            case .failure(_):
                // Close connected peer channel before closing our channel.
                peerChannel.close(mode: .all, promise: nil)
                context.close(promise: nil)
            }
        }
    }
    
    private func removeDecoder(context: ChannelHandlerContext) {
        // We drop the future on the floor here as these handlers must all be in our own pipeline, and this should
        // therefore succeed fast.
        context.pipeline.context(handlerType: ByteToMessageHandler<HTTPRequestDecoder>.self).whenSuccess {
            context.pipeline.removeHandler(context: $0, promise: nil)
        }
    }
    
    private func removeEncoder(context: ChannelHandlerContext) {
        context.pipeline.context(handlerType: HTTPResponseEncoder.self).whenSuccess {
            context.pipeline.removeHandler(context: $0, promise: nil)
        }
    }
}
