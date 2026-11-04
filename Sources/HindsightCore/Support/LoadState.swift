import Foundation

/// État de chargement d'une donnée asynchrone, pour les vues.
public enum LoadState<Value: Sendable>: Sendable {
    case idle
    case loading
    case loaded(Value)
    case failed(String)

    public var value: Value? {
        if case .loaded(let v) = self { return v }
        return nil
    }
    public var errorMessage: String? {
        if case .failed(let m) = self { return m }
        return nil
    }
    public var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}
