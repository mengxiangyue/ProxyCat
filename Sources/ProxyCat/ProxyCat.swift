import ProxyCatCore
import Foundation
import Dispatch

@main
public struct ProxyCat {
    public private(set) var text = "Hello, World!"

    public static func main() {
        let url = URL(string: "http://www.gov.cn")
        print(url?.host)
        let proxyServer = ProxyServer()
        proxyServer.start()
        dispatchMain()
    }
}
