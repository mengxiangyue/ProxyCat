import ProxyCatCore
import Dispatch

@main
public struct ProxyCat {
    public private(set) var text = "Hello, World!"

    public static func main() {
        print(ProxyCat().text)
        let proxyServer = ProxyServer()
        proxyServer.start()
        dispatchMain()
    }
}
