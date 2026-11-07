import Foundation
import HindsightAPI

/// Attend la fin d'une opération asynchrone (export, clone, import…) en interrogeant son statut.
public enum OperationWaiter {
    public struct Failed: Error, CustomStringConvertible {
        public let status: OperationStatusResponse
        public var description: String {
            "L'opération a échoué : \(status.errorMessage ?? status.status)"
        }
    }

    public struct TimedOut: Error, CustomStringConvertible {
        public let operationID: String
        public var description: String { "L'opération n'est pas encore terminée ; suivez-la dans « Activité › Traitements »." }
    }

    public static func wait(
        client: HindsightClient, bank: String, operationID: String, interval: Duration = .seconds(2),
        timeout: TimeInterval = 1800, progress: @MainActor @Sendable (OperationStatusResponse) -> Void = { _ in }
    ) async throws -> OperationStatusResponse {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try Task.checkCancellation()
            let s = try await client.operation(bank, id: operationID)
            await progress(s)
            switch s.status {
            case "completed": return s
            case "failed", "cancelled", "not_found": throw Failed(status: s)
            default: try await Task.sleep(for: interval)
            }
        }
        throw TimedOut(operationID: operationID)
    }

    /// URL de téléchargement de l'archive dans `result_metadata` (`download_url`, sinon `storage_key`).
    public static func downloadTarget(_ s: OperationStatusResponse) -> (url: String?, key: String?, filename: String?) {
        let m = s.resultMetadata ?? [:]
        return (m["download_url"]?.stringValue, m["storage_key"]?.stringValue, m["filename"]?.stringValue)
    }
}
