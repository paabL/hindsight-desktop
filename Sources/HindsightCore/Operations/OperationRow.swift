import Foundation
import HindsightAPI

public enum OperationStatusKind: String, Sendable, CaseIterable {
    case pending, processing, completed, failed, cancelled, other

    public init(_ raw: String) { self = OperationStatusKind(rawValue: raw.lowercased()) ?? .other }

    public var title: String {
        switch self {
        case .pending: return "En attente"
        case .processing: return "En cours"
        case .completed: return "Terminée"
        case .failed: return "Échec"
        case .cancelled: return "Annulée"
        case .other: return "Autre"
        }
    }

    /// Opération encore active (le serveur la fera évoluer).
    public var isActive: Bool { self == .pending || self == .processing }
}

/// Vue pratique d'une `OperationResponse` pour l'affichage.
public struct OperationRow: Identifiable, Sendable, Hashable {
    public let raw: OperationResponse

    public init(_ raw: OperationResponse) { self.raw = raw }

    public var id: String { raw.id }
    public var status: OperationStatusKind { OperationStatusKind(raw.status) }
    public var typeKey: String { raw.operationType ?? raw.taskType }

    public static func typeTitle(_ key: String) -> String {
        switch key {
        case "retain", "batch_retain": return "Rétention (extraction de faits)"
        case "consolidation": return "Consolidation"
        case "refresh_mental_model": return "Rafraîchissement de modèle mental"
        case "file_convert_retain": return "Conversion de fichier + rétention"
        case "webhook_delivery": return "Envoi de webhook"
        case "reprocess_document": return "Retraitement de document"
        case "bank_export", "export": return "Export"
        case "bank_import", "import": return "Import"
        case "bank_clone", "clone": return "Clonage"
        default: return key.replacingOccurrences(of: "_", with: " ")
        }
    }

    public var title: String { Self.typeTitle(typeKey) }

    /// Cible lisible : document, modèle mental, nom de fichier…
    public var target: String? { raw.documentId ?? raw.mentalModelId ?? raw.filename }

    public var errorMessage: String? {
        guard let e = raw.errorMessage, !e.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return e
    }

    public var createdAt: Date? { HSDate.parse(raw.createdAt) }
    public var updatedAt: Date? { HSDate.parse(raw.updatedAt) }
    public var nextRetryAt: Date? { HSDate.parse(raw.nextRetryAt) }

    /// Avancement 0…1 si le serveur fournit `processed` et `total`.
    public var progressFraction: Double? {
        guard let p = raw.progress, let done = p.processed, let total = p.total, total > 0 else { return nil }
        return min(1, max(0, Double(done) / Double(total)))
    }

    /// Terminée sans avoir rien traité de ce qu'elle annonçait (ex. consolidation reprise après un échec alors que
    /// les observations étaient coupées) : « Terminée » serait trompeur. Une consolidation qui en traite une partie
    /// (100 sur 5 648) est normale : elle passe la suite à l'opération suivante.
    public static func endedWithoutWork(status: String, processed: Int?, total: Int?) -> Bool {
        OperationStatusKind(status) == .completed && processed == 0 && (total ?? 0) > 0
    }

    public var endedWithoutWork: Bool { Self.endedWithoutWork(status: raw.status, processed: raw.progress?.processed, total: raw.progress?.total) }

    /// Erreur d'une opération en cours ou en attente : le serveur garde le message de la tentative précédente jusqu'à
    /// la fin de l'opération (ex. 429 Gemini pendant une panne, puis reprise normale). Ce n'est pas un échec actuel.
    public static func errorIsFromPreviousAttempt(status: String) -> Bool { OperationStatusKind(status).isActive }

    public var errorIsFromPreviousAttempt: Bool { errorMessage != nil && Self.errorIsFromPreviousAttempt(status: raw.status) }
    public var statusTitle: String { endedWithoutWork ? "Sans effet" : status.title }

    public var progressLabel: String? {
        guard let p = raw.progress else { return nil }
        if endedWithoutWork, let total = p.total { return "terminée sans rien traiter sur \(total) en attente" }
        if let done = p.processed, let total = p.total { return "\(p.stage) — \(done)/\(total)" }
        return p.stage
    }

    /// Première ligne du message d'erreur, tronquée, sans identifiants variables (uuid, nombres de 4+ chiffres)
    /// mais en gardant les codes courts (429, 500…) : sert au regroupement.
    public var failureSignature: String? {
        guard let e = errorMessage else { return nil }
        let firstLine = e.split(whereSeparator: \.isNewline).first.map(String.init) ?? e
        let cleaned = firstLine.replacingOccurrences(of: #"[0-9a-f]{8}-[0-9a-f-]{27}"#, with: "<uuid>", options: .regularExpression)
            .replacingOccurrences(of: #"\d{4,}"#, with: "N", options: .regularExpression)
        return String(cleaned.prefix(160))
    }
}

/// Groupe d'opérations échouées partageant la même cause.
public struct FailureGroup: Identifiable, Sendable, Hashable {
    public var id: String { signature }
    public let signature: String
    public let sampleMessage: String
    public let operationIDs: [String]
    public var count: Int { operationIDs.count }
}
