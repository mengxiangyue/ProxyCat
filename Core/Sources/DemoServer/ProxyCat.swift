import ProxyCatCore
import Foundation
import Dispatch

/// test https curl -v -x http://localhost:8080  https://www.apple.com
/// test https curl -v -x http://localhost:8080 -k  https://www.baidu.com
/// -k ignore certification check
/// test http curl -v -x http://localhost:8080  http://www.maitanbang.com/test/
/// right now http proxy does not handle the 301
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
