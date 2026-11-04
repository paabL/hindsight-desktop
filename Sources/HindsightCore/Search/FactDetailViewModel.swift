import Foundation
import HindsightAPI
import Observation

/// Détail d'un fait : texte complet, métadonnées, chunk source, faits sources (pour une observation),
/// et lien vers le document d'origine.
@MainActor
@Observable
public final class FactDetailViewModel: Identifiable {
    public nonisolated let factID: String
    public let bank: String
    @ObservationIgnored private let client: HindsightClient

    public private(set) var hit: FactHit
    public private(set) var detail: LoadState<MemoryDetail> = .idle
    public private(set) var chunk: LoadState<ChunkResponse> = .idle
    public private(set) var sources: LoadState<[FactHit]> = .idle
    public private(set) var history: JSONValue?

    /// Brouillon de correction (nil = pas en édition).
    public var edit: FactEdit?
    public var confirmation: ConfirmationRequest?
    public var actionMessage: String?
    /// Prévenu après toute écriture réussie (pour rafraîchir une liste).
    @ObservationIgnored public var onChanged: (@MainActor () -> Void)?

    public nonisolated var id: String { factID }

    public init(client: HindsightClient, bank: String, hit: FactHit) {
        self.client = client
        self.bank = bank
        self.factID = hit.id
        self.hit = hit
    }

    /// Document et chunk d'origine, si connus.
    public var documentTarget: (documentID: String, chunkID: String?)? {
        guard let doc = hit.documentID ?? detail.value?.documentID else { return nil }
        return (doc, hit.chunkID ?? detail.value?.chunkID)
    }

    public func load() async {
        detail = .loading
        do {
            let d = try await client.memory(bank, id: factID)
            detail = .loaded(d)
            let enriched = FactHit(d, fallbackID: factID)
            // On garde le score et ce que la liste connaissait déjà si le détail est plus pauvre.
            hit = FactHit(
                id: hit.id, text: enriched.text.isEmpty ? hit.text : enriched.text, type: enriched.type ?? hit.type,
                context: enriched.context ?? hit.context, mentionedAt: enriched.mentionedAt ?? hit.mentionedAt,
                occurredStart: enriched.occurredStart ?? hit.occurredStart, occurredEnd: enriched.occurredEnd ?? hit.occurredEnd,
                documentID: enriched.documentID ?? hit.documentID, chunkID: enriched.chunkID ?? hit.chunkID,
                tags: enriched.tags.isEmpty ? hit.tags : enriched.tags,
                entities: enriched.entities.isEmpty ? hit.entities : enriched.entities, score: hit.score,
                sourceFactIDs: enriched.sourceFactIDs.isEmpty ? hit.sourceFactIDs : enriched.sourceFactIDs,
                attachments: enriched.attachments.isEmpty ? hit.attachments : enriched.attachments,
                state: enriched.state ?? hit.state)
        } catch is CancellationError {
            return
        } catch {
            detail = .failed(error.userMessage)
        }
        async let c: Void = loadChunk()
        async let s: Void = loadSources()
        _ = await (c, s)
    }

    private func loadChunk() async {
        guard let id = hit.chunkID else {
            chunk = .idle
            return
        }
        chunk = .loading
        do {
            chunk = .loaded(try await client.chunk(id: id))
        } catch is CancellationError {
        } catch {
            chunk = .failed(error.userMessage)
        }
    }

    /// Faits sources d'une observation (20 au plus) et son historique.
    private func loadSources(limit: Int = 20) async {
        let ids = Array(hit.sourceFactIDs.prefix(limit))
        guard !ids.isEmpty else {
            sources = .idle
            return
        }
        sources = .loading
        let client = self.client, bank = self.bank
        let fetched = await withTaskGroup(of: (Int, FactHit?).self) { group in
            for (i, id) in ids.enumerated() {
                group.addTask {
                    guard let d = try? await client.memory(bank, id: id) else { return (i, nil) }
                    return (i, FactHit(d, fallbackID: id))
                }
            }
            var out: [(Int, FactHit)] = []
            for await (i, h) in group { if let h { out.append((i, h)) } }
            return out.sorted { $0.0 < $1.0 }.map(\.1)
        }
        sources = .loaded(fetched)
        if hit.isObservation { history = try? await client.observationHistory(bank, id: factID) }
    }

    // MARK: Curation (toujours confirmée)

    /// Seuls les faits world/experience se corrigent ; les observations sont dérivées.
    public var canCurate: Bool { hit.type == "world" || hit.type == "experience" }
    public var isInvalidated: Bool { hit.state == "invalidated" }

    public func beginEdit() {
        edit = FactEdit(
            text: hit.text, context: hit.context ?? "", occurredStart: hit.occurredStart ?? "",
            occurredEnd: hit.occurredEnd ?? "", factType: hit.type ?? "world")
    }

    public func cancelEdit() { edit = nil }

    /// Requête minimale correspondant au brouillon, ou nil si rien ne change.
    public func updateRequest(for e: FactEdit) -> UpdateMemoryRequest? {
        var r = UpdateMemoryRequest()
        var changed = false
        let textChanged = e.text != hit.text
        if e.context != (hit.context ?? "") { r.context = e.context; changed = true }
        if e.occurredStart != (hit.occurredStart ?? "") { r.occurredStart = e.occurredStart; changed = true }
        if e.occurredEnd != (hit.occurredEnd ?? "") { r.occurredEnd = e.occurredEnd; changed = true }
        if e.factType != (hit.type ?? "") { r.factType = e.factType; changed = true }
        guard changed || textChanged else { return nil }
        // Le serveur exige `text` ou `state` : on renvoie le texte (même inchangé).
        r.text = e.text
        return r
    }

    public func requestSaveEdit() {
        guard let e = edit, let req = updateRequest(for: e) else {
            edit = nil
            return
        }
        let textChanged = e.text != hit.text
        confirmation = ConfirmationRequest(
            title: "Corriger ce fait ?",
            message: (textChanged
                ? "Le nouveau texte sera ré-indexé ; les observations et liens qui en dérivent sont supprimés puis reconsolidés (appel LLM de consolidation)."
                : "Le serveur exige le texte avec toute correction : il sera ré-indexé tel quel, et les observations qui en dérivent reconsolidées.")
                + "\n\nL'ancienne version reste dans l'archive de curation du serveur.",
            confirmTitle: "Enregistrer", severity: .normal
        ) { [weak self] in
            await self?.write(req, success: "Fait corrigé.")
            self?.edit = nil
        }
    }

    public func requestInvalidate(reason: String) {
        let r = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        confirmation = ConfirmationRequest(
            title: "Invalider ce fait ?",
            message: "Il sera exclu du recall et de la consolidation ; ses liens et observations dérivées sont retirés. C'est réversible (« Rétablir »).",
            confirmTitle: "Invalider"
        ) { [weak self] in
            await self?.write(UpdateMemoryRequest(state: "invalidated", reason: r.isEmpty ? nil : r), success: "Fait invalidé.")
        }
    }

    public func requestRevalidate() {
        confirmation = ConfirmationRequest(
            title: "Rétablir ce fait ?", message: "Il redevient visible du recall et sera reconsolidé.",
            confirmTitle: "Rétablir", severity: .normal
        ) { [weak self] in
            await self?.write(UpdateMemoryRequest(state: "valid"), success: "Fait rétabli.")
        }
    }

    public func requestClearObservations() {
        confirmation = ConfirmationRequest(
            title: "Effacer les observations issues de ce fait ?",
            message: "Les observations qui en dérivent sont supprimées ; elles pourront être recréées par la prochaine consolidation.",
            confirmTitle: "Effacer"
        ) { [weak self] in
            guard let self else { return }
            do {
                let r = try await self.client.clearMemoryObservations(self.bank, id: self.factID)
                self.actionMessage = "\(r.deletedCount) observation(s) supprimée(s)."
                self.onChanged?()
            } catch {
                self.actionMessage = "Échec : \(error.userMessage)"
            }
        }
    }

    private func write(_ req: UpdateMemoryRequest, success: String) async {
        do {
            _ = try await client.updateMemory(bank, id: factID, req)
            actionMessage = success
            await load()
            onChanged?()
        } catch {
            actionMessage = "Échec : \(error.userMessage)"
        }
    }
}

/// Brouillon de correction d'un fait.
public struct FactEdit: Sendable, Equatable {
    public var text: String
    public var context: String
    public var occurredStart: String
    public var occurredEnd: String
    public var factType: String
}
