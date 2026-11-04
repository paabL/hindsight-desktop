import Foundation
import HindsightAPI

/// Plafonds de consommation, réglés dans l'écran « Consommation » et mémorisés dans les réglages de l'app.
public struct ConsumptionBudgets: Codable, Sendable, Hashable {
    /// Que faire quand un plafond est atteint.
    public enum Action: String, Codable, CaseIterable, Identifiable, Sendable {
        /// Notification et bandeau seulement.
        case alert
        /// Pause douce de toutes les banques : plus d'envoi depuis l'app, consolidation automatique coupée.
        case softPause
        /// Gel de la file : le serveur redémarre sans traiter sa file (lectures toujours possibles).
        case freezeQueue

        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .alert: return "Alerter seulement"
            case .softPause: return "Mettre en pause"
            case .freezeQueue: return "Geler la file"
            }
        }
    }

    /// Plafonds d'un abonnement, en jetons, sur les mêmes fenêtres glissantes que les fournisseurs.
    public struct Subscription: Codable, Sendable, Hashable {
        public var tokens5h: Int?
        public var tokensWeek: Int?
        public init(tokens5h: Int? = nil, tokensWeek: Int? = nil) {
            self.tokens5h = tokens5h
            self.tokensWeek = tokensWeek
        }
        var isEmpty: Bool { tokens5h == nil && tokensWeek == nil }
    }

    /// Dollars facturés à l'usage par jour (heure locale, depuis minuit).
    public var dailyDollars: Double?
    /// Par fournisseur d'abonnement (`claude-code`, `openai-codex`…).
    public var subscriptions: [String: Subscription] = [:]
    /// Pourcentage du quota Codex (relevé dans les sessions Codex de ce Mac) à ne pas dépasser.
    public var codexQuotaPercent: Double?
    /// Fraction du plafond à partir de laquelle l'app prévient.
    public var warnAt: Double = 0.8
    public var action: Action = .softPause
    /// L'action automatique a été confirmée une fois par l'utilisateur ; sans cela, l'app ne fait qu'alerter.
    public var actionConfirmed = false

    public init(
        dailyDollars: Double? = nil, subscriptions: [String: Subscription] = [:], codexQuotaPercent: Double? = nil,
        warnAt: Double = 0.8, action: Action = .softPause, actionConfirmed: Bool = false
    ) {
        self.dailyDollars = dailyDollars
        self.subscriptions = subscriptions
        self.codexQuotaPercent = codexQuotaPercent
        self.warnAt = warnAt
        self.action = action
        self.actionConfirmed = actionConfirmed
    }

    public var isEmpty: Bool { dailyDollars == nil && subscriptions.values.allSatisfy(\.isEmpty) && codexQuotaPercent == nil }

    /// Plus grande valeur acceptée (mille milliards) : au-delà, une saisie est une erreur.
    public static let maxAmount = 1e12

    /// Lit un montant saisi : « 5 », « 1,5 », « 200k », « 1.5M », espaces tolérés. Refuse le vide, ce qui
    /// n'est pas un nombre fini, le négatif, le nul et le démesuré.
    public static func parseAmount(_ text: String) -> Double? {
        var t = text.trimmingCharacters(in: .whitespaces).lowercased()
        t = t.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\u{00A0}", with: "")
        guard !t.isEmpty else { return nil }
        var factor = 1.0
        if t.hasSuffix("k") {
            factor = 1_000
            t.removeLast()
        } else if t.hasSuffix("m") {
            factor = 1_000_000
            t.removeLast()
        }
        guard t.allSatisfy({ $0.isNumber || $0 == "." }), let v = Double(t) else { return nil }
        let value = v * factor
        guard value.isFinite, value > 0, value <= maxAmount else { return nil }
        return value
    }

    /// Montant affiché pour la saisie : « 5 » plutôt que « 5.0 » ; vide si la valeur est inutilisable.
    public static func amountText(_ value: Double) -> String {
        guard value.isFinite, value > 0, value <= maxAmount else { return "" }
        return value == value.rounded() ? String(Int(value)) : String(value)
    }

    /// Action réellement appliquée au dépassement (une action non confirmée se limite à l'alerte).
    public var effectiveAction: Action { actionConfirmed ? action : .alert }

    static let settingsKey = "consumptionBudgets"

    @MainActor
    public static func load(from settings: SettingsStore) -> ConsumptionBudgets {
        guard let raw = settings.string(forKey: settingsKey),
            let b = try? JSONDecoder().decode(ConsumptionBudgets.self, from: Data(raw.utf8))
        else { return ConsumptionBudgets() }
        return b
    }

    @MainActor
    public func save(to settings: SettingsStore) {
        if self == ConsumptionBudgets() {
            settings.set(nil, forKey: Self.settingsKey)
        } else if let data = try? JSONEncoder().encode(self) {
            settings.set(String(decoding: data, as: UTF8.self), forKey: Self.settingsKey)
        }
    }

    // Les champs ajoutés plus tard ne doivent pas rendre illisibles les réglages déjà enregistrés.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dailyDollars = try c.decodeIfPresent(Double.self, forKey: .dailyDollars)
        subscriptions = try c.decodeIfPresent([String: Subscription].self, forKey: .subscriptions) ?? [:]
        codexQuotaPercent = try c.decodeIfPresent(Double.self, forKey: .codexQuotaPercent)
        warnAt = try c.decodeIfPresent(Double.self, forKey: .warnAt) ?? 0.8
        action = try c.decodeIfPresent(Action.self, forKey: .action) ?? .softPause
        actionConfirmed = try c.decodeIfPresent(Bool.self, forKey: .actionConfirmed) ?? false
    }
}

/// Jauge d'un plafond : consommé, limite, niveau.
public struct BudgetGauge: Sendable, Hashable, Identifiable {
    public enum Unit: Sendable, Hashable { case dollars, tokens, percent }
    public enum Level: Int, Sendable, Comparable {
        case ok, warning, exceeded
        public static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }

    public let id: String
    public let title: String
    public let used: Double
    public let limit: Double
    public let unit: Unit
    public let level: Level
    /// Fin de la fenêtre quand elle est fixe (minuit, réinitialisation du quota Codex).
    public let resetsAt: Date?
    /// Précision (« relevé il y a 12 min », « fenêtre glissante »).
    public let note: String?

    public var fraction: Double { limit > 0 ? used / limit : 0 }

    public static func format(_ value: Double, _ unit: Unit) -> String {
        switch unit {
        case .dollars: return Format.dollars(value)
        case .tokens: return Format.tokens(Int(value.rounded()))
        case .percent: return "\(Int(value.rounded())) %"
        }
    }

    public var usedText: String { Self.format(used, unit) }
    public var limitText: String { Self.format(limit, unit) }
}

extension ConsumptionMath {
    /// Jauges des plafonds réglés. `events` triés par date croissante.
    public static func gauges(
        _ events: [ConsumptionEvent], budgets: ConsumptionBudgets, prices: PriceBook, codex: CodexQuota?, now: Date,
        calendar: Calendar = .current
    ) -> [BudgetGauge] {
        func level(_ used: Double, _ limit: Double) -> BudgetGauge.Level {
            guard limit > 0 else { return .ok }
            if used >= limit { return .exceeded }
            return used >= limit * budgets.warnAt ? .warning : .ok
        }
        var out: [BudgetGauge] = []
        if let limit = budgets.dailyDollars, limit > 0 {
            let start = startOfDay(now, calendar: calendar)
            let used = totals(since(events, start), prices: prices).dollars
            out.append(
                BudgetGauge(
                    id: "dollars.day", title: "Facturé aujourd'hui", used: used, limit: limit, unit: .dollars, level: level(used, limit),
                    resetsAt: calendar.date(byAdding: .day, value: 1, to: start), note: nil))
        }
        for provider in budgets.subscriptions.keys.sorted() {
            let sub = budgets.subscriptions[provider]!
            let name = SubscriptionNames.title(provider)
            for (window, hours, limit) in [("5h", 5.0, sub.tokens5h), ("week", 168.0, sub.tokensWeek)] {
                guard let limit, limit > 0 else { continue }
                let used = Double(
                    since(events, now.addingTimeInterval(-hours * 3600)).reduce(0) { $0 + ($1.provider == provider ? $1.tokens.total : 0) })
                out.append(
                    BudgetGauge(
                        id: "sub.\(provider).\(window)", title: "\(name) · \(window == "5h" ? "5 h" : "7 jours")", used: used,
                        limit: Double(limit), unit: .tokens, level: level(used, Double(limit)), resetsAt: nil,
                        note: "jetons envoyés par Hindsight, fenêtre glissante"))
            }
        }
        if let threshold = budgets.codexQuotaPercent, threshold > 0, let codex {
            for (name, w) in [("primary", codex.primary), ("secondary", codex.secondary)] {
                guard let w else { continue }
                // Fenêtre réinitialisée depuis le relevé : le pourcentage n'a plus cours.
                let used = w.isExpired(now: now) ? 0 : w.usedPercent
                out.append(
                    BudgetGauge(
                        id: "codex.\(name)", title: "Quota Codex · \(w.title)", used: used, limit: threshold, unit: .percent,
                        level: level(used, threshold), resetsAt: w.isExpired(now: now) ? nil : w.resetsAt,
                        note: w.isExpired(now: now) ? "réinitialisé depuis le dernier relevé" : "relevé le \(Format.dateTime(codex.observedAt))"))
            }
        }
        return out
    }
}

/// Noms lisibles des fournisseurs d'abonnement.
public enum SubscriptionNames {
    public static func title(_ provider: String) -> String {
        switch provider.lowercased() {
        case "claude-code": return "Claude Code"
        case "openai-codex", "codex": return "Codex"
        case "chatgpt": return "ChatGPT"
        default: return provider
        }
    }
}

/// Chiffre de la barre des menus : la part du plafond Claude Code sur 5 h, ou à défaut les jetons
/// d'abonnement envoyés sur 5 h. Court, pour rester lisible à côté de la miniature du logo.
public struct MenuBarReading: Sendable, Equatable {
    public let text: String
    /// Phrase lue par VoiceOver.
    public let spoken: String
    public let level: BudgetGauge.Level
    /// Le serveur travaille : appels récents ou opérations en cours.
    public let isWorking: Bool

    public static func make(gauges: [BudgetGauge], subscriptionTokens5h: Int, rate: ConsumptionMath.Rate, processing: Int) -> MenuBarReading {
        let working = !rate.isIdle || processing > 0
        let activity = working ? ", en cours" : ", au repos"
        let gauge = gauges.first { $0.id == "sub.claude-code.5h" } ?? gauges.first { $0.id.hasSuffix(".5h") }
        guard let gauge else {
            let tokens = Format.tokens(subscriptionTokens5h)
            return MenuBarReading(
                text: tokens, spoken: "Hindsight : \(tokens) jetons d'abonnement sur 5 h\(activity)", level: .ok, isWorking: working)
        }
        let percent = "\(Int((gauge.fraction * 100).rounded())) %"
        let mark = gauge.level == .exceeded ? "⚠︎ " : ""
        return MenuBarReading(
            text: mark + percent, spoken: "Hindsight : \(gauge.title), \(percent) du plafond\(activity)", level: gauge.level,
            isWorking: working)
    }
}
