import ProxyCatCore
import Foundation
import Dispatch

@main
public struct ProxyCat {
    public private(set) var text = "Hello, World!"

    public static func main() {
        let url = URL(string: "http://www.gov.cn")
        print(url?.host)
        Task {
            let proxyServer = ProxyServer()
            await proxyServer.start()
        }
        
        dispatchMain()
    }
}
