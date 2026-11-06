import Foundation

/// Sections de la barre latérale.
public enum AppSection: String, CaseIterable, Identifiable, Sendable {
    case sources, dashboard, memory, mentalModels, documents, consumption, operations, search, timeline, graph, audit, admin, server

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .sources: return "Dossier mémoire"
        case .dashboard: return "Vue d'ensemble"
        case .memory: return "Structure"
        case .mentalModels: return "Connaissances"
        case .documents: return "Documents en mémoire"
        case .consumption: return "Consommation"
        case .operations: return "Opérations"
        case .search: return "Recherche"
        case .timeline: return "Chronologie"
        case .graph: return "Graphe"
        case .audit: return "Activité"
        case .admin: return "Administration"
        case .server: return "Serveur & modèles"
        }
    }

    /// Nom de symbole SF Symbols.
    public var symbol: String {
        switch self {
        case .sources: return "folder"
        case .dashboard: return "square.grid.2x2"
        case .memory: return "brain"
        case .mentalModels: return "text.book.closed"
        case .documents: return "doc.text.image"
        case .consumption: return "gauge.with.dots.needle.33percent"
        case .operations: return "arrow.triangle.2.circlepath"
        case .search: return "magnifyingglass"
        case .timeline: return "calendar.day.timeline.left"
        case .graph: return "point.3.connected.trianglepath.dotted"
        case .audit: return "chart.bar.xaxis"
        case .admin: return "slider.horizontal.3"
        case .server: return "server.rack"
        }
    }
}
