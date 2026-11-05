import Foundation
import HindsightAPI

/// Où en est un élément, du point de vue de l'utilisateur : un seul état, dans un vocabulaire stable.
public enum LibraryState: String, CaseIterable, Identifiable, Sendable {
    /// Source suivie, absente de la banque.
    case notSent
    /// En mémoire, mais la source a changé depuis l'envoi.
    case modified
    /// Une opération du serveur est en train de l'extraire (ou vient d'être demandée).
    case queued
    /// Envoyé, aucun fait extrait.
    case noFacts
    /// En mémoire, le fichier n'existe plus dans le dossier suivi.
    case fileMissing
    /// En mémoire, identique à la source.
    case current
    /// En mémoire, sans source suivie sur ce Mac.
    case stored

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .notSent: return "Non envoyé"
        case .modified: return "Modifié"
        case .queued: return "En file"
        case .noFacts: return "Sans fait"
        case .fileMissing: return "Fichier disparu"
        case .current: return "À jour"
        case .stored: return "En mémoire"
        }
    }

    public var symbol: String {
        switch self {
        case .notSent: return "circle.dashed"
        case .modified: return "arrow.triangle.2.circlepath.circle.fill"
        case .queued: return "clock.fill"
        case .noFacts: return "exclamationmark.circle.fill"
        case .fileMissing: return "questionmark.folder.fill"
        case .current: return "checkmark.circle.fill"
        case .stored: return "doc.circle"
        }
    }

    /// Ce que l'état veut dire, en une phrase.
    public var explanation: String {
        switch self {
        case .notSent: return "Ce contenu n'est pas dans la banque."
        case .modified: return "La source a changé depuis son envoi : la mémoire en a une version ancienne."
        case .queued: return "Le serveur l'extrait en ce moment, ou va le faire."
        case .noFacts: return "Envoyé, mais aucun fait n'en a été extrait."
        case .fileMissing: return "En mémoire, mais le fichier n'existe plus dans le dossier suivi."
        case .current: return "En mémoire, identique à la source."
        case .stored: return "En mémoire ; sa source n'est pas suivie sur ce Mac."
        }
    }

    /// Appelle une action de l'utilisateur (envoyer, vérifier, retirer).
    public var needsAttention: Bool { [.notSent, .modified, .noFacts, .fileMissing].contains(self) }
}

/// Filtres principaux de la liste.
public enum LibraryScope: String, CaseIterable, Identifiable, Sendable {
    case all, toSend, toCheck, queued, inMemory

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: return "Tout"
        case .toSend: return "À envoyer"
        case .toCheck: return "À vérifier"
        case .queued: return "En file"
        case .inMemory: return "En mémoire"
        }
    }

    public var help: String {
        switch self {
        case .all: return "Tout ce qui est suivi ou en mémoire"
        case .toSend: return "Non envoyés et modifiés depuis l'envoi"
        case .toCheck: return "Sans fait extrait, ou dont le fichier a disparu"
        case .queued: return "En cours d'extraction"
        case .inMemory: return "Tout ce que la banque contient"
        }
    }

    public func includes(_ item: LibraryItem) -> Bool {
        switch self {
        case .all: return true
        case .toSend: return item.state == .notSent || item.state == .modified
        case .toCheck: return item.state == .noFacts || item.state == .fileMissing
        case .queued: return item.state == .queued
        case .inMemory: return !item.documents.isEmpty
        }
    }
}

/// Section de la liste : un dossier suivi, des conversations, ou des documents sans source suivie.
public struct LibraryGroup: Identifiable, Hashable, Sendable {
    public enum Kind: Int, Sendable, Hashable, Comparable {
        case folder, conversations, unfollowedFolder, elsewhere, other
        public static func < (a: Kind, b: Kind) -> Bool { a.rawValue < b.rawValue }
    }

    public let id: String
    public let title: String
    public let kind: Kind

    public var symbol: String {
        switch kind {
        case .folder: return "folder"
        case .conversations: return "bubble.left.and.bubble.right"
        case .unfollowedFolder: return "folder.badge.questionmark"
        case .elsewhere: return "bubble.left.and.exclamationmark.bubble.right"
        case .other: return "tray.full"
        }
    }

    /// Précision sous le titre de section.
    public var note: String? {
        switch kind {
        case .unfollowedFolder: return "dossier non suivi"
        case .elsewhere: return "sessions absentes de ce Mac"
        default: return nil
        }
    }
}

/// Un élément : une source (fichier, conversation) et les documents de la banque qui en viennent, ou un
/// document seul.
public struct LibraryItem: Identifiable, Sendable {
    public let id: String
    public let group: LibraryGroup
    /// Nom court (fichier, titre de la conversation, identifiant du document).
    public let title: String
    /// Où il se trouve (dossier, projet, identifiant).
    public let location: String
    public let state: LibraryState
    /// Fichier ou conversation suivis ; nil pour un document sans source suivie.
    public let entry: CoverageEntry?
    public let documents: [DocumentListItem]
    // Calculés une fois : la liste les relit à chaque tri, filtre et rendu.
    public let facts: Int
    public let textLength: Int
    public let lastSent: Date?
    public let tags: [String]

    public init(
        id: String, group: LibraryGroup, title: String, location: String, state: LibraryState, entry: CoverageEntry?,
        documents: [DocumentListItem]
    ) {
        self.id = id
        self.group = group
        self.title = title
        self.location = location
        self.state = state
        self.entry = entry
        self.documents = documents
        facts = documents.reduce(0) { $0 + $1.memoryUnitCount }
        textLength = documents.reduce(0) { $0 + $1.textLength }
        lastSent = documents.compactMap { HSDate.parse($0.updatedAt) }.max()
        tags = Array(Set(documents.flatMap(\.tags))).sorted()
    }

    public var sourceModified: Date? { entry.map { $0.file.modified } }
    public var isConversation: Bool { entry?.session != nil }
    /// Envoyable d'ici ; les conversations sont collectées dans le dossier commun.
    public var canSend: Bool { entry?.canSend ?? false }
    /// Fichier sur ce Mac ; les conversations consultables sont des fichiers JSONL.
    public var sourceURL: URL? {
        guard let e = entry, e.session == nil || e.file.url.pathExtension == "jsonl" else { return nil }
        return e.file.url
    }
}

/// Construction de la bibliothèque à partir du rapport de couverture.
public enum DocumentLibrary {
    /// - Parameters:
    ///   - queued: identifiants de documents qu'une opération en attente ou en cours va (ré)extraire.
    public static func build(report: CoverageReport, queued: Set<String> = []) -> [LibraryItem] {
        var items: [LibraryItem] = []
        var folderOrder: [String] = []
        for e in report.entries where e.session == nil && !folderOrder.contains(e.file.repo) { folderOrder.append(e.file.repo) }

        func isQueued(_ docs: [DocumentListItem], expected: String?) -> Bool {
            docs.contains { queued.contains($0.id) } || expected.map { queued.contains($0) } == true
        }

        for e in report.entries {
            if let s = e.session {
                let group = LibraryGroup(id: "conversations:\(s.source.rawValue)", title: "Conversations \(s.source.title)", kind: .conversations)
                let title = (s.meta?.title ?? s.firstUserText ?? s.meta?.id ?? s.id).split(separator: "\n").first.map(String.init) ?? s.id
                let project = s.meta?.projectName ?? "?"
                var state = libraryState(e.status)
                if isQueued(e.documents, expected: nil) { state = .queued }
                items.append(
                    LibraryItem(
                        id: e.id, group: group, title: String(title.prefix(120)), location: "\(project) · \(Format.dateTime(e.file.modified))",
                        state: state, entry: e, documents: e.documents))
            } else {
                let group = LibraryGroup(id: "folder:\(e.file.repo)", title: e.file.repo, kind: .folder)
                let dir = (e.file.path as NSString).deletingLastPathComponent
                var state = libraryState(e.status)
                if state != .current, isQueued(e.documents, expected: FileCoverage.documentID(repo: e.file.repo, path: e.file.path)) {
                    state = .queued
                }
                items.append(
                    LibraryItem(
                        id: e.id, group: group, title: (e.file.path as NSString).lastPathComponent,
                        location: dir.isEmpty ? e.file.repo : "\(e.file.repo)/\(dir)", state: state, entry: e, documents: e.documents))
            }
        }

        for d in report.orphans {
            let (repo, path) = FileCoverage.repoAndPath(d) ?? ("?", d.id)
            let group = LibraryGroup(id: "folder:\(repo)", title: repo, kind: .folder)
            let dir = (path as NSString).deletingLastPathComponent
            items.append(
                LibraryItem(
                    id: "doc:" + d.id, group: group, title: (path as NSString).lastPathComponent,
                    location: dir.isEmpty ? repo : "\(repo)/\(dir)", state: isQueued([d], expected: nil) ? .queued : .fileMissing, entry: nil,
                    documents: [d]))
        }

        for d in report.others {
            let group: LibraryGroup
            let title: String, location: String
            if let (repo, path) = FileCoverage.repoAndPath(d) {
                group = LibraryGroup(id: "unfollowed:\(repo)", title: repo, kind: .unfollowedFolder)
                title = (path as NSString).lastPathComponent
                let dir = (path as NSString).deletingLastPathComponent
                location = dir.isEmpty ? repo : "\(repo)/\(dir)"
            } else if FileCoverage.sessionID(d) != nil {
                group = LibraryGroup(id: "elsewhere", title: "Autres conversations", kind: .elsewhere)
                title = d.id
                location = Format.dateTime(d.updatedAt)
            } else {
                group = LibraryGroup(id: "other", title: "Autres documents", kind: .other)
                title = d.id
                location = Format.dateTime(d.updatedAt)
            }
            let state: LibraryState = isQueued([d], expected: nil) ? .queued : (d.memoryUnitCount == 0 ? .noFacts : .stored)
            items.append(LibraryItem(id: "doc:" + d.id, group: group, title: title, location: location, state: state, entry: nil, documents: [d]))
        }
        return items
    }

    static func libraryState(_ s: CoverageStatus) -> LibraryState {
        switch s {
        case .current: return .current
        case .modified: return .modified
        case .noFacts: return .noFacts
        case .missing: return .notSent
        }
    }

    /// Tri des éléments d'une section.
    public enum Sort: String, CaseIterable, Identifiable, Sendable {
        case name, recent, facts, size
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .name: return "Nom"
            case .recent: return "Plus récents"
            case .facts: return "Plus de faits"
            case .size: return "Plus longs"
            }
        }
    }

    /// Sections dans l'ordre d'affichage, chacune avec ses éléments triés.
    public static func sections(_ items: [LibraryItem], sort: Sort) -> [(group: LibraryGroup, items: [LibraryItem])] {
        var order: [LibraryGroup] = []
        var byGroup: [String: [LibraryItem]] = [:]
        for i in items {
            if byGroup[i.group.id] == nil { order.append(i.group) }
            byGroup[i.group.id, default: []].append(i)
        }
        // Dossiers suivis dans leur ordre d'analyse, puis conversations, dossiers non suivis, le reste.
        let ranked = order.enumerated().sorted { a, b in
            a.element.kind != b.element.kind ? a.element.kind < b.element.kind
                : (a.element.kind == .unfollowedFolder ? a.element.title < b.element.title : a.offset < b.offset)
        }.map(\.element)
        return ranked.map { g in (g, sorted(byGroup[g.id] ?? [], sort)) }
    }

    static func sorted(_ items: [LibraryItem], _ sort: Sort) -> [LibraryItem] {
        switch sort {
        case .name:
            return items.sorted { ($0.location + "/" + $0.title).localizedStandardCompare($1.location + "/" + $1.title) == .orderedAscending }
        case .recent:
            func when(_ i: LibraryItem) -> Date { max(i.sourceModified ?? .distantPast, i.lastSent ?? .distantPast) }
            return items.sorted { when($0) > when($1) }
        case .facts:
            return items.sorted { ($0.facts, $1.title) > ($1.facts, $0.title) }
        case .size:
            return items.sorted { (max($0.textLength, $0.entry?.file.size ?? 0), $1.title) > (max($1.textLength, $1.entry?.file.size ?? 0), $0.title) }
        }
    }
}
