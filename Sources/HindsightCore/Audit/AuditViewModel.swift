import Foundation
import HindsightAPI
import Observation

/// Accès à la banque (journal d'audit) et traces des appels LLM, avec les états « désactivé ».
@MainActor
@Observable
public final class AuditViewModel {
    public enum AuditStatus: Sendable, Equatable {
        case unknown
        /// Activé pour cette banque (réglage global ou override de banque).
        case enabled(viaBankOverride: Bool)
        /// Désactivé ; `canEnableViaAPI` = l'API de configuration de banque est ouverte en écriture.
        case disabled(canEnableViaAPI: Bool)
    }

    /// Variable d'environnement serveur équivalente (format accepté par `PATCH …/config`).
    public static let auditEnvVar = "HINDSIGHT_API_AUDIT_LOG_ENABLED"
    public static let llmTraceEnvVar = "HINDSIGHT_API_LLM_TRACE_ENABLED"
    public static let periods = ["1d", "7d", "30d"]

    public let bank: String
    @ObservationIgnored private let client: HindsightClient
    public let features: FeaturesInfo?

    public var period = "7d"
    /// Clé de regroupement des appelants (`nil` = automatique).
    public var groupBy: String?
    public var actionFilter: String?
    public var llmStatusFilter: String?
    public var llmOperationFilter: String?

    public private(set) var auditStatus: AuditStatus = .unknown
    public private(set) var audit: LoadState<[AuditLogEntry]> = .idle
    public private(set) var auditTotal = 0
    public private(set) var auditStats: AuditLogStatsResponse?
    public private(set) var llm: LoadState<[LLMRequestEntry]> = .idle
    public private(set) var llmTotal = 0
    public private(set) var llmStats: LLMRequestStatsResponse?
    public private(set) var selectedAudit: AuditLogEntry?
    public private(set) var selectedLLM: LLMRequestEntry?

    /// Prévenu après une modification de la configuration de la banque (le tableau de bord se recalcule).
    @ObservationIgnored public var onConfigChanged: (@MainActor () async -> Void)?
    public var confirmation: ConfirmationRequest?
    public var actionMessage: String?

    public init(client: HindsightClient, bank: String, features: FeaturesInfo?) {
        self.client = client
        self.bank = bank
        self.features = features
    }

    public var llmTraceEnabled: Bool { features?.llmTrace ?? true }

    public func loadIfNeeded() async {
        if audit.value == nil, !audit.isLoading { await reload() }
    }

    public func reload() async {
        async let a: Void = loadAudit()
        async let l: Void = loadLLM()
        _ = await (a, l)
    }

    public func loadAudit() async {
        audit = .loading
        do {
            async let cfg = client.bankConfig(bank)
            async let list = client.auditLogs(bank, action: actionFilter, limit: 500)
            async let stats = client.auditLogStats(bank, action: actionFilter, period: period)
            let config = try? await cfg
            auditStatus = Self.status(config: config, features: features)
            let l = try await list
            audit = .loaded(l.items)
            auditTotal = l.total
            auditStats = try? await stats
        } catch is CancellationError {
        } catch {
            audit = .failed(error.userMessage)
        }
    }

    public func loadLLM() async {
        guard llmTraceEnabled else {
            llm = .loaded([])
            return
        }
        llm = .loading
        do {
            async let list = client.llmRequests(bank, status: llmStatusFilter, operation: llmOperationFilter, limit: 500)
            async let stats = client.llmRequestStats(bank, operation: llmOperationFilter, period: period)
            let l = try await list
            llm = .loaded(l.items)
            llmTotal = l.total
            llmStats = try? await stats
        } catch is CancellationError {
        } catch {
            llm = .failed(error.userMessage)
        }
    }

    static func status(config: BankConfigResponse?, features: FeaturesInfo?) -> AuditStatus {
        let override = config?.overrides["audit_log_enabled"]?.boolValue
        let resolved = config?.config["audit_log_enabled"]?.boolValue
        let canWrite = features?.bankConfigApi ?? true
        if override == true { return .enabled(viaBankOverride: true) }
        if let resolved { return resolved ? .enabled(viaBankOverride: false) : .disabled(canEnableViaAPI: canWrite) }
        if let f = features?.auditLog { return f ? .enabled(viaBankOverride: false) : .disabled(canEnableViaAPI: canWrite) }
        return .unknown
    }

    // MARK: Synthèses

    /// Noms donnés aux clients non identifiés (partagés entre banques).
    @ObservationIgnored public var callers: CallerDirectory?
    public var accessRows: [AccessRow] { AccessSummary.compute(audit.value ?? [], groupBy: groupBy, names: callers?.names ?? [:]) }
    public var groupingKeys: [String] { AccessSummary.availableKeys(audit.value ?? []) }
    public var actionCounts: [(action: String, count: Int)] { AccessSummary.actionCounts(audit.value ?? []) }
    public var llmUsage: [LLMUsageRow] { LLMUsageSummary.compute(llm.value ?? []) }

    public func selectAudit(_ e: AuditLogEntry?) {
        selectedAudit = e
        // Serveur 1.1.0 : la liste n'a plus les corps de requête et de réponse ; on lit l'entrée complète.
        guard let e, e.request == nil, e.response == nil else { return }
        Task { [weak self] in
            guard let self, let full = try? await self.client.auditLog(self.bank, id: e.id), self.selectedAudit?.id == e.id else { return }
            self.selectedAudit = full
        }
    }
    public func selectLLM(_ e: LLMRequestEntry?) { selectedLLM = e }

    // MARK: Activation (confirmée)

    public func requestEnableAudit() { requestAudit(enabled: true) }
    public func requestDisableAudit() { requestAudit(enabled: false) }

    /// Le journal peut-il être activé ou désactivé d'ici ? Faux si son état est inconnu ou si le serveur refuse
    /// les réglages par banque.
    public var canToggleAudit: Bool {
        switch auditStatus {
        case .enabled: return features?.bankConfigApi != false
        case .disabled(let canEnableViaAPI): return canEnableViaAPI
        default: return false
        }
    }

    private func requestAudit(enabled: Bool) {
        guard canToggleAudit else {
            if case .disabled = auditStatus {
                actionMessage = "Ce serveur n'accepte pas les réglages par banque : activez le journal côté serveur en ajoutant `\(Self.auditEnvVar)=true` au script de lancement, puis redémarrez-le."
            } else if case .enabled = auditStatus {
                actionMessage = ServerCapabilities.bankConfigDisabledMessage
            } else {
                actionMessage = "État du journal d'accès inconnu : actualisez la page avant de le modifier."
            }
            return
        }
        confirmation = ConfirmationRequest(
            title: enabled ? "Activer le journal d'accès pour « \(bank) » ?" : "Désactiver le journal d'accès pour « \(bank) » ?",
            message: enabled
                ? "Le serveur enregistrera chaque accès à cette banque (action, transport, requête, réponse). Les accès passés ne sont pas récupérables. Écrit `audit_log_enabled = true` dans la configuration de la banque (PATCH …/config)."
                : "Les prochains accès ne seront plus enregistrés. Les entrées existantes sont conservées.",
            confirmTitle: enabled ? "Activer" : "Désactiver", severity: enabled ? .normal : .destructive
        ) { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.client.updateBankConfig(self.bank, updates: ["audit_log_enabled": .bool(enabled)])
                self.actionMessage = enabled ? "Journal d'accès activé pour cette banque." : "Journal d'accès désactivé."
                await self.loadAudit()
                await self.onConfigChanged?()
            } catch {
                self.actionMessage =
                    "Le serveur a refusé (\(error.userMessage)). Pour l'activer côté serveur : ajouter `\(Self.auditEnvVar)=true` à l'environnement du processus Hindsight, puis le redémarrer."
            }
        }
    }
}
