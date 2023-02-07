import ProxyCatCore
import Foundation
import Dispatch

@main
public struct ProxyCat {
    public private(set) var text = "Hello, World!"

    public static func main() {
        Task {
            let proxyServer = ProxyServer()
            await proxyServer.start()
        }
        
        dispatchMain()
    }
}
