import Foundation
import HindsightAPI
import Observation

/// Nœud dessinable.
public struct GraphNode: Identifiable, Sendable, Hashable {
    public let id: String
    public let label: String
    /// Texte complet (aperçu au survol).
    public let detail: String
    /// Importance (mentions d'une entité, liens d'un fait) : taille du nœud.
    public let weight: Double
    /// Catégorie : type de fait, ou « entity ».
    public let kind: String
    public let mentionedAt: Date?
    public let occurredAt: Date?
}

public struct GraphEdge: Identifiable, Sendable, Hashable {
    public var id: String { "\(source)→\(target)#\(kind)#\(label ?? "")" }
    public let source: String
    public let target: String
    public let weight: Double
    public let kind: String
    /// Entité partagée qui explique le lien, lorsque l'API la fournit.
    public let label: String?

    public init(source: String, target: String, weight: Double, kind: String, label: String? = nil) {
        self.source = source; self.target = target; self.weight = weight; self.kind = kind; self.label = label
    }
}

/// Lien par indices (dessin rapide).
public struct GraphLink: Sendable, Hashable {
    public let a: Int
    public let b: Int
    public let weight: Double
}

/// Façon de colorer les nœuds.
public enum GraphColorMode: String, CaseIterable, Sendable, Identifiable {
    case recencyMentioned, recencyOccurred, type, importance
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .recencyMentioned: return "Récence · mention"
        case .recencyOccurred: return "Récence · événement"
        case .type: return "Type"
        case .importance: return "Importance"
        }
    }
    public var isGradient: Bool { self != .type }
}

/// Graphe vivant (simulation de forces animée, comme le Control Plane web) : faits ou entités,
/// couleur par récence ou type, survol, sélection, voisinage, pause.
@MainActor
@Observable
public final class GraphViewModel {
    public enum Mode: String, CaseIterable, Sendable, Identifiable {
        case facts, entities
        public var id: String { rawValue }
        public var title: String { self == .entities ? "Entités" : "Faits" }
    }

    public let bank: String
    @ObservationIgnored private let client: HindsightClient
    @ObservationIgnored private let animated: Bool

    public var mode: Mode = .facts {
        didSet {
            if oldValue != mode {
                maxNodes = mode == .facts ? 1000 : 300
                colorMode = mode == .facts ? .recencyMentioned : .importance
            }
        }
    }
    public var filter = FactFilter()
    /// Nombre maximal de nœuds (faits : limite serveur ; entités : les plus mentionnées).
    public var maxNodes = 1000
    /// Co-occurrences minimales pour garder un lien entre entités.
    public var minCount = 2
    public var colorMode: GraphColorMode = .recencyMentioned
    public var highlight = ""

    public private(set) var state: LoadState<Void> = .idle
    public private(set) var nodes: [GraphNode] = []
    public private(set) var edges: [GraphEdge] = []
    public private(set) var links: [GraphLink] = []
    /// Positions courantes (coordonnées monde, centrées sur 0), alignées sur `nodes`.
    public private(set) var positions: [Point2] = []
    public private(set) var serverNodeTotal = 0
    public private(set) var serverEdgeTotal = 0

    // Animation
    public private(set) var isAnimating = false
    public private(set) var isPaused = false
    /// Incrémenté quand la vue doit recadrer (première stabilisation, rechargement).
    public private(set) var fitGeneration = 0

    // Interaction
    public private(set) var hoveredIndex: Int?
    public private(set) var selectedNodeID: String?
    public private(set) var entityDetail: LoadState<EntityDetailResponse> = .idle
    public private(set) var nodeFacts: LoadState<[FactHit]> = .idle
    public private(set) var selectedFact: FactDetailViewModel?

    @ObservationIgnored private var factRows: [String: MemoryGraphTableRow] = [:]
    @ObservationIgnored private var adjacency: [[Int]] = []
    @ObservationIgnored private var indexByID: [String: Int] = [:]
    @ObservationIgnored private var engine: GraphSimulationEngine?
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var loadID = UUID()
    @ObservationIgnored private var selectionID = UUID()
    @ObservationIgnored private var animationID = UUID()
    @ObservationIgnored private var detailTask: Task<Void, Never>?

    public init(client: HindsightClient, bank: String, animated: Bool = true) {
        self.client = client
        self.bank = bank
        self.animated = animated
    }

    public func loadIfNeeded() async {
        if nodes.isEmpty, !state.isLoading, state.errorMessage == nil { await reload() }
    }

    public func reload(layout: Bool = true) async {
        let id = UUID()
        loadID = id
        selectionID = UUID()
        detailTask?.cancel()
        detailTask = nil
        stopAnimation()
        engine = nil
        let mode = mode, filter = filter, maxNodes = max(0, maxNodes), minCount = minCount
        state = .loading
        selectedNodeID = nil
        hoveredIndex = nil
        entityDetail = .idle
        nodeFacts = .idle
        selectedFact = nil
        do {
            try Task.checkCancellation()
            let tags = TagFilter(tags: filter.effectiveTags, match: filter.tagsMatch)
            let (n, e): ([GraphNode], [GraphEdge])
            switch mode {
            case .entities:
                let g = try await client.entityGraph(bank, limit: maxNodes * 8, minCount: minCount, tags: tags)
                try Task.checkCancellation()
                guard loadID == id else { return }
                serverNodeTotal = g.totalEntities
                serverEdgeTotal = g.totalEdges
                factRows = [:]
                (n, e) = Self.entityGraph(g, maxNodes: maxNodes)
            case .facts:
                let g = try await client.graph(bank, type: filter.singleType, limit: maxNodes, tags: tags, documentID: nil)
                try Task.checkCancellation()
                guard loadID == id else { return }
                serverNodeTotal = g.totalUnits
                serverEdgeTotal = g.edges.count
                factRows = Dictionary(g.tableRows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                (n, e) = Self.factGraph(g, maxNodes: maxNodes)
            }
            install(nodes: n, edges: e)
            state = .loaded(())
            if layout { await startSimulation(loadID: id) } else { positions = [] }
        } catch {
            guard loadID == id else { return }
            state = Task.isCancelled || error is CancellationError ? .idle : .failed(error.userMessage)
        }
    }

    private func install(nodes n: [GraphNode], edges e: [GraphEdge]) {
        nodes = n
        edges = e
        indexByID = Dictionary(n.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        links = e.compactMap { edge in
            guard let a = indexByID[edge.source], let b = indexByID[edge.target], a != b else { return nil }
            return GraphLink(a: a, b: b, weight: edge.weight)
        }
        var adj = [[Int]](repeating: [], count: n.count)
        for l in links {
            adj[l.a].append(l.b)
            adj[l.b].append(l.a)
        }
        adjacency = adj
    }

    // MARK: Animation

    private func startSimulation(loadID: UUID) async {
        let sim = ForceSimulation(nodeCount: nodes.count, links: links.map { ForceSimulation.Link($0.a, $0.b, weight: $0.weight) })
        let engine = GraphSimulationEngine(sim)
        self.engine = engine
        positions = sim.positions
        isPaused = false
        if !animated {
            let settled = await engine.settle()
            guard self.loadID == loadID, !Task.isCancelled, self.engine === engine else { return }
            positions = settled
            fitGeneration += 1
            return
        }
        runLoop()
    }

    private func runLoop() {
        guard let engine else { return }
        isAnimating = true
        runTask?.cancel()
        runTask = Task { [weak self] in
            var fitted = false
            while !Task.isCancelled {
                let r = await engine.step(2)
                // Un pas en cours au moment de la pause ne doit pas déplacer le graphe figé, et une boucle
                // annulée ne doit pas toucher à l'état d'une boucle relancée entre-temps.
                guard let self, !Task.isCancelled else { return }
                self.positions = r.positions
                if !fitted, r.alpha < 0.25 {
                    fitted = true
                    self.fitGeneration += 1
                }
                if r.settled { break }
                try? await Task.sleep(for: .milliseconds(16))
            }
            if !Task.isCancelled { self?.isAnimating = false }
        }
    }

    public func pause() {
        animationID = UUID()
        runTask?.cancel()
        runTask = nil
        isAnimating = false
        isPaused = true
    }

    /// Reprend (ou relance) l'animation.
    public func resume() {
        guard let engine else { return }
        let id = UUID()
        animationID = id
        isPaused = false
        Task {
            await engine.reheat(0.3)
            guard animationID == id, self.engine === engine, !isPaused else { return }
            runLoop()
        }
    }

    public func togglePause() { isPaused || !isAnimating ? resume() : pause() }

    /// Recadre le graphe dans la vue (⌘0, double-clic sur le fond).
    public func requestFit() { fitGeneration += 1 }

    /// Revenir de la fiche d'un fait à celle de l'entité sélectionnée (mode entités).
    public func clearFact() {
        detailTask?.cancel()
        detailTask = nil
        selectedFact = nil
    }

    public func stopAnimation() {
        animationID = UUID()
        runTask?.cancel()
        runTask = nil
        isAnimating = false
    }

    // MARK: Lecture

    public func index(of id: String) -> Int? { indexByID[id] }

    public func neighbors(of index: Int) -> [Int] { adjacency.indices.contains(index) ? adjacency[index] : [] }

    /// Nœuds dont le libellé contient la recherche.
    public var highlightedIDs: Set<String> {
        let q = highlight.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return Set(nodes.filter {
            $0.label.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                || $0.detail.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }.map(\.id))
    }

    /// Voisins directs du nœud sélectionné.
    public var neighborIDs: Set<String> {
        guard let s = selectedNodeID, let i = indexByID[s] else { return [] }
        return Set(neighbors(of: i).map { nodes[$0].id })
    }

    public var selectedNode: GraphNode? { selectedNodeID.flatMap { indexByID[$0] }.map { nodes[$0] } }
    public var hoveredNode: GraphNode? { hoveredIndex.flatMap { nodes.indices.contains($0) ? nodes[$0] : nil } }

    public func hover(_ index: Int?) {
        if hoveredIndex != index { hoveredIndex = index }
    }

    // MARK: Couleurs

    /// Plage de dates de l'axe de récence choisi (légende).
    public var dateRange: ClosedRange<Date>? {
        let dates = nodes.compactMap { colorMode == .recencyOccurred ? ($0.occurredAt ?? $0.mentionedAt) : $0.mentionedAt }
        guard let lo = dates.min(), let hi = dates.max() else { return nil }
        return lo...hi
    }

    /// Valeurs 0…1 pour les modes dégradés (nil = pas de valeur : couleur neutre), alignées sur `nodes`.
    public var colorValues: [Double?] {
        switch colorMode {
        case .type:
            return nodes.map { _ in nil }
        case .importance:
            let maxW = max(nodes.map(\.weight).max() ?? 1, 1)
            return nodes.map { ($0.weight / maxW).squareRoot() }
        case .recencyMentioned, .recencyOccurred:
            guard let r = dateRange else { return nodes.map { _ in nil } }
            let span = max(r.upperBound.timeIntervalSince(r.lowerBound), 1)
            return nodes.map { n in
                let d = colorMode == .recencyOccurred ? (n.occurredAt ?? n.mentionedAt) : n.mentionedAt
                return d.map { $0.timeIntervalSince(r.lowerBound) / span }
            }
        }
    }

    // MARK: Construction

    /// Garde les `maxNodes` entités les plus mentionnées et les liens entre elles.
    static func entityGraph(_ g: EntityGraphResponse, maxNodes: Int) -> ([GraphNode], [GraphEdge]) {
        let top = g.nodes.map(\.data).sorted { ($0.mentionCount, $1.id) > ($1.mentionCount, $0.id) }.prefix(max(0, maxNodes))
        let keep = Set(top.map(\.id))
        let nodes = top.map {
            GraphNode(
                id: $0.id, label: $0.label.isEmpty ? $0.id : $0.label, detail: "\($0.mentionCount) mentions",
                weight: Double(max($0.mentionCount, 1)), kind: "entity", mentionedAt: nil, occurredAt: nil)
        }
        let edges = g.edges.map(\.data).filter { keep.contains($0.source) && keep.contains($0.target) }.map {
            GraphEdge(source: $0.source, target: $0.target, weight: Double(max($0.weight, 1)), kind: $0.linkType)
        }
        return (Array(nodes), edges)
    }

    static func factGraph(_ g: GraphDataResponse, maxNodes: Int) -> ([GraphNode], [GraphEdge]) {
        let rows = Dictionary(g.tableRows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var degree: [String: Int] = [:]
        for e in g.edges {
            degree[e.data.source, default: 0] += 1
            degree[e.data.target, default: 0] += 1
        }
        let top = g.nodes.map(\.data).sorted { (degree[$0.id] ?? 0, $1.id) > (degree[$1.id] ?? 0, $0.id) }.prefix(max(0, maxNodes))
        let keep = Set(top.map(\.id))
        let nodes = top.map { d -> GraphNode in
            let row = rows[d.id]
            let text = row?.text.isEmpty == false ? row!.text : d.text
            let label = d.label.isEmpty ? String(text.prefix(60)) : d.label
            return GraphNode(
                id: d.id, label: label, detail: text, weight: Double((degree[d.id] ?? 0) + 1), kind: row?.factType ?? "?",
                mentionedAt: HSDate.parse(row?.mentionedAt) ?? HSDate.parse(row?.date) ?? HSDate.parse(d.date),
                occurredAt: HSDate.parse(row?.occurredStart))
        }
        let edges = g.edges.map(\.data).filter { keep.contains($0.source) && keep.contains($0.target) }.map {
            GraphEdge(source: $0.source, target: $0.target, weight: max($0.weight, 0.1), kind: $0.linkType, label: $0.entityName.isEmpty ? nil : $0.entityName)
        }
        return (Array(nodes), edges)
    }

    // MARK: Sélection

    public func select(_ id: String?) async {
        let requestID = UUID()
        selectionID = requestID
        detailTask?.cancel()
        detailTask = nil
        selectedNodeID = id
        entityDetail = .idle
        nodeFacts = .idle
        selectedFact = nil
        guard let id else { return }
        switch mode {
        case .entities:
            entityDetail = .loading
            nodeFacts = .loading
            async let detail = client.entity(bank, id: id)
            async let facts = client.listMemories(bank, MemoryListQuery(entityID: id, limit: 50))
            do {
                let response = try await detail
                guard selectionID == requestID else { return }
                try Task.checkCancellation()
                entityDetail = .loaded(response)
            } catch {
                guard selectionID == requestID else { return }
                entityDetail = Task.isCancelled || error is CancellationError ? .idle : .failed(error.userMessage)
            }
            do {
                let response = try await facts
                guard selectionID == requestID else { return }
                try Task.checkCancellation()
                nodeFacts = .loaded(response.items.map(FactHit.init))
            } catch {
                guard selectionID == requestID else { return }
                nodeFacts = Task.isCancelled || error is CancellationError ? .idle : .failed(error.userMessage)
            }
        case .facts:
            let hit: FactHit
            if let row = factRows[id] {
                hit = FactHit(
                    id: row.id, text: row.text, type: row.factType, context: row.context, mentionedAt: row.mentionedAt,
                    occurredStart: row.occurredStart, occurredEnd: row.occurredEnd, documentID: row.documentId,
                    chunkID: row.chunkId, tags: row.tags, entities: FactHit.splitEntities(row.entities))
            } else {
                hit = FactHit(id: id, text: selectedNode?.detail ?? "")
            }
            let vm = FactDetailViewModel(client: client, bank: bank, hit: hit)
            selectedFact = vm
            await vm.load()
        }
    }

    public func selectFact(_ hit: FactHit) {
        detailTask?.cancel()
        let vm = FactDetailViewModel(client: client, bank: bank, hit: hit)
        selectedFact = vm
        detailTask = Task { await vm.load() }
    }
}
