import Foundation

/// The proxy's own downloads: a private cacheless session, through the core's mixed port if given.
enum ProxyURLSession {
    static func make(
        proxyPort: Int?, timeout: TimeInterval, delegate: (any URLSessionDelegate)? = nil
    ) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = timeout
        if let proxyPort {
            configuration.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPEnable: 1, kCFNetworkProxiesHTTPProxy: "127.0.0.1",
                kCFNetworkProxiesHTTPPort: proxyPort, kCFNetworkProxiesHTTPSEnable: 1,
                kCFNetworkProxiesHTTPSProxy: "127.0.0.1", kCFNetworkProxiesHTTPSPort: proxyPort
            ]
        }
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }
}
