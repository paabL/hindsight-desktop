import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Couche réseau minimale, remplaçable par un faux serveur dans les tests.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Transport réel basé sur `URLSession` (async/await).
public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let cfg = URLSessionConfiguration.ephemeral
            cfg.timeoutIntervalForRequest = 60
            cfg.timeoutIntervalForResource = 3600
            cfg.httpMaximumConnectionsPerHost = 6
            self.session = URLSession(configuration: cfg)
        }
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request, delegate: SameOriginRedirects())
            guard let http = response as? HTTPURLResponse else { throw HindsightError.invalidResponse }
            return (data, http)
        } catch let e as HindsightError {
            throw e
        } catch is CancellationError {
            throw CancellationError()
        } catch let e as URLError where e.code == .cancelled {
            throw CancellationError()
        } catch {
            throw HindsightError.unreachable((error as NSError).localizedDescription)
        }
    }
}

/// Une redirection ne doit envoyer ni corps de document ni identifiants à un autre serveur.
final class SameOriginRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    static func allowed(from source: URL, to target: URL) -> Bool {
        target.user == nil && target.password == nil && HindsightClient.sameOrigin(source, target)
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard let source = task.originalRequest?.url, let target = request.url,
              Self.allowed(from: source, to: target) else {
            completionHandler(nil)
            return
        }
        var redirected = request
        // URLSession peut retirer Authorization même pour un chemin du même serveur.
        // La vérification d'origine ci-dessus doit précéder toute restauration de la clé.
        redirected.setValue(task.originalRequest?.value(forHTTPHeaderField: "Authorization"), forHTTPHeaderField: "Authorization")
        completionHandler(redirected)
    }
}
