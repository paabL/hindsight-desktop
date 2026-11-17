import Foundation
import HindsightAPI
import HindsightCore

/// État de la banque choisie lu pour le volet de la barre des menus, gardé 20 s : quelques requêtes légères
/// (statistiques en cache côté serveur, réglages, consolidations actives, opérations en échec).
struct MenuBankReading {
    let bank: String
    let at: Date
    let consolidation: ConsolidationStatus?
    let failed: Int?
}

/// Volet de la barre des menus : l'essentiel de l'app en un relevé, sans changer la section ouverte dans la
/// fenêtre principale. Ce qui vaut pour toutes les banques (connexion, pause, file, consommation) vient de ce
/// que l'app suit déjà ; seule la banque choisie demande des requêtes, et seulement quand le volet est ouvert.
extension DesktopBridge {
    func menuStatus(live: Bool?) async -> [String: Any] {
        if let live, live != menuLive {
            menuLive = live
            // Volet ouvert : la file et les traces sont relevées plus souvent (toutes les 20 s et 10 s).
            app.consumption.setLive("menubar", live)
        }
        let connected = app.connection.isConnected
        var connectionError: String?
        if case .failed(let text) = app.connection { connectionError = text }
        let local = ["127.0.0.1", "localhost", "::1", "[::1]"].contains(app.serverURL.host?.lowercased() ?? "")
        if menuLive, local, !testing, !app.service.isBusy, serviceTask == nil, Date().timeIntervalSince(menuServiceCheckedAt) > 15 {
            menuServiceCheckedAt = Date()
            await app.service.refresh()
        }
        var bankReading: MenuBankReading?
        if connected, let bank = app.selectedBankID, !testing {
            if let cached = menuBank, cached.bank == bank, !menuLive || Date().timeIntervalSince(cached.at) < 20 {
                bankReading = cached
            } else if menuLive {
                bankReading = await readMenuBank(bank)
                menuBank = bankReading
            }
        }
        let monitor = app.consumption!
        let summary = monitor.summary
        let running = monitor.running.prefix(4).map { op -> [String: Any] in
            let progress = op.row.raw.progress
            return ["id": op.id, "bank": op.bank, "type": op.row.typeKey, "title": op.row.title, "target": wire(op.row.target),
                    "createdAt": op.row.raw.createdAt, "stage": wire(progress?.stage),
                    "processed": wire(progress?.processed), "total": wire(progress?.total)]
        }
        let service = app.service!
        let (messages, keys) = emittedMessages()
        return [
            "connected": connected,
            "connecting": { if case .connecting = app.connection { return true } else { return false } }(),
            "connectionError": wire(connectionError),
            "serverURL": app.serverURL.absoluteString,
            "version": wire(app.connection.version?.apiVersion),
            "banks": wire(app.banks),
            "bank": wire(app.selectedBankID),
            "pause": pauseSnapshot().merging(["busy": app.pause.isBusy, "progress": wire(app.pause.progress)]) { $1 },
            "consultationOnly": app.session.map { $0.operations.consultationOnly || $0.consolidation.consultationOnly || $0.dashboard.snapshot?.consultationOnly == true } ?? false,
            "service": [
                "local": local, "installed": service.isInstalled, "known": service.status != .unknown,
                "running": service.status.isRunning, "phase": service.phase,
                "canStart": service.canStart, "canStop": service.canStop,
                "busy": service.isBusy || serviceTask != nil,
            ],
            "activity": [
                "pending": monitor.pendingTotal, "processing": monitor.processingTotal, "running": running,
                "queues": monitor.queues.map { ["bank": $0.bank, "pending": $0.pending, "processing": $0.processing] },
            ],
            "bankStatus": bankReading.map { reading -> [String: Any] in
                ["bank": reading.bank, "consolidation": wire(reading.consolidation), "failed": wire(reading.failed)]
            } ?? NSNull(),
            "usage": [
                "tracked": app.connection.version?.features.llmTrace ?? false,
                "today": summary.today.dollars, "todayTokens": summary.today.tokens.input + summary.today.tokens.output,
                "subscription5h": summary.last5h.subscriptionTokens,
                "tokensPerMinute": summary.rate.tokensPerMinute, "idle": summary.rate.isIdle,
                "gauges": monitor.gauges.map { ["id": $0.id, "used": $0.used, "limit": $0.limit, "fraction": $0.fraction,
                                                "level": $0.level.rawValue, "resetsAt": wire($0.resetsAt)] },
            ],
            "confirmations": confirmationsPayload(),
            "messages": messages.map { SecretMasker.mask($0) },
            "messageKeys": keys,
            "at": wire(Date()),
        ]
    }

    private func readMenuBank(_ bank: String) async -> MenuBankReading {
        let client = app.client
        async let stats = try? client.bankStats(bank)
        async let config = try? client.bankConfig(bank)
        async let active = ConsolidationStatus.activeOperations(client, bank)
        async let failed = try? client.listOperations(bank, status: "failed", limit: 1, excludeParents: true).total
        let consolidation: ConsolidationStatus?
        if let stats = await stats {
            consolidation = ConsolidationStatus(
                stats: stats, config: await config, serverObservations: app.connection.version?.features.observations,
                operations: await active ?? ActiveConsolidations())
        } else {
            consolidation = nil
        }
        return MenuBankReading(bank: bank, at: Date(), consolidation: consolidation, failed: await failed)
    }
}
