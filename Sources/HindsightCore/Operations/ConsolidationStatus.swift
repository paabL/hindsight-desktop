import Foundation
import HindsightAPI

/// État de la consolidation d'une banque, calculé ici pour toutes les vues : la Vue d'ensemble,
/// Traitements et la confirmation de « Consolider » disent la même chose.
///
/// Quand la banque ne crée pas d'observations (`enable_observations` faux), le serveur accepte une
/// consolidation et la termine aussitôt sans rien traiter : il ne faut donc ni la proposer, ni
/// présenter ses faits comme « en attente ».
public struct ConsolidationStatus: Sendable, Equatable, Encodable {
    public enum Phase: String, Sendable, Encodable {
        /// La banque ne crée pas d'observations : aucune consolidation n'a d'effet.
        case disabled
        /// Une consolidation est en cours.
        case running
        /// Une consolidation attend son tour dans la file.
        case queued
        /// Des faits ne sont pas encore consolidés.
        case pending
        /// Tous les faits sont consolidés.
        case upToDate
    }

    /// Réglage résolu pour cette banque (« Créer des observations »).
    public let enabled: Bool
    /// Le serveur consolide de lui-même après les envois.
    public let automatic: Bool
    /// Faits pas encore consolidés (`pending_consolidation`).
    public let pendingFacts: Int
    /// Faits en échec définitif de consolidation (`failed_consolidation`).
    public let failedFacts: Int
    /// Dernière consolidation qui a réellement traité des faits, pas la dernière opération lancée.
    public let lastConsolidatedAt: String?
    /// Consolidations en cours et en attente (`active` = les deux).
    public let running: Int
    public let queued: Int
    public let active: Int
    public let phase: Phase

    /// `serverObservations` : drapeau `features.observations` du serveur, utilisé si la banque ne dit rien.
    public init(stats: BankStatsResponse, config: BankConfigResponse?, serverObservations: Bool?, operations: ActiveConsolidations) {
        let enabled = Self.createsObservations(config, serverObservations: serverObservations)
        self.enabled = enabled
        automatic = Self.consolidatesAfterExtraction(config, serverObservations: serverObservations)
        pendingFacts = stats.pendingConsolidation
        failedFacts = stats.failedConsolidation
        lastConsolidatedAt = stats.lastConsolidatedAt
        running = max(0, operations.running)
        queued = max(0, operations.queued)
        active = running + queued
        phase = !enabled ? .disabled : running > 0 ? .running : queued > 0 ? .queued
            : stats.pendingConsolidation > 0 ? .pending : .upToDate
    }

    /// Réglage résolu POUR CETTE BANQUE d'abord : une banque peut désactiver ce que le serveur active.
    public static func createsObservations(_ config: BankConfigResponse?, serverObservations: Bool?) -> Bool {
        config?.config["enable_observations"]?.boolValue ?? serverObservations ?? true
    }

    /// La banque consolidera-t-elle d'elle-même après une extraction ? Sert aux estimations d'envoi et de
    /// retraitement. Sans réglages connus, oui : l'estimation reste prudente (même défaut que Comportement de la mémoire).
    public static func consolidatesAfterExtraction(_ config: BankConfigResponse?, serverObservations: Bool?) -> Bool {
        createsObservations(config, serverObservations: serverObservations)
            && (config?.config["enable_auto_consolidation"]?.boolValue ?? true)
    }

    /// Pourquoi « Consolider » ne peut rien faire maintenant ; nil quand il y a des faits à consolider.
    /// Les faits en échec définitif relèvent de « Reconsolider », pas d'une nouvelle consolidation.
    public var refusal: String? {
        switch phase {
        case .disabled: return Self.disabledMessage
        case .running: return "Une consolidation est déjà en cours pour cette banque."
        case .queued: return "Une consolidation est déjà en attente pour cette banque."
        case .upToDate: return "Rien à consolider : tous les faits de cette banque sont déjà consolidés."
        case .pending: return nil
        }
    }

    public static let disabledMessage =
        "La consolidation est désactivée pour cette banque : le serveur ne crée pas d'observations. Activez « Créer des observations » dans « Réglages › Comportement de la mémoire › Consolidation »."

    /// Consolidations en cours et en attente, une ligne lue par statut ; nil si le serveur ne répond pas.
    public static func activeOperations(_ client: HindsightClient, _ bank: String) async -> ActiveConsolidations? {
        async let processing = try? client.listOperations(bank, status: "processing", type: "consolidation", limit: 1).total
        async let pending = try? client.listOperations(bank, status: "pending", type: "consolidation", limit: 1).total
        guard let running = await processing, let queued = await pending else { return nil }
        return ActiveConsolidations(running: running, queued: queued)
    }
}

/// Consolidations d'une banque selon leur statut d'opération (structure plutôt que tuple entre tâches).
public struct ActiveConsolidations: Sendable, Equatable {
    public var running: Int
    public var queued: Int
    public init(running: Int = 0, queued: Int = 0) {
        self.running = running
        self.queued = queued
    }
}
