//
//  File.swift
//  
//
//  Created by xiangyue on 2023/1/1.
//

import NIOCore
import NIOPosix
import NIOHTTP1

final class HTTPProxyHandler: ChannelInboundHandler {
  public typealias InboundIn = HTTPServerRequestPart
  public typealias OutboundOut = HTTPServerResponsePart
  
  private var buffer: ByteBuffer! = nil
  private var keepAlive = false
  
  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
      let reqPart = self.unwrapInboundIn(data)

      switch reqPart {
      case .head(let request):

          self.keepAlive = request.isKeepAlive

          var responseHead = httpResponseHead(request: request, status: HTTPResponseStatus.ok)
        if self.buffer == nil {
          self.buffer = context.channel.allocator.buffer(capacity: 0)
        }
          self.buffer.clear()
          self.buffer.writeString("hell world")
          responseHead.headers.add(name: "content-length", value: "\(self.buffer!.readableBytes)")
          let response = HTTPServerResponsePart.head(responseHead)
          context.write(self.wrapOutboundOut(response), promise: nil)
      case .body(var body):
        
        let content = body.readString(length: body.readableBytes)
        print("body-->\(content)")
          break
      case .end:
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
