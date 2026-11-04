import Foundation

/// Ligne d'un diff de texte.
public struct DiffLine: Identifiable, Sendable, Hashable {
    public enum Kind: Sendable { case same, removed, added }
    public let id: Int
    public let kind: Kind
    public let text: String
    public let oldNumber: Int?
    public let newNumber: Int?
}

public enum LineDiff {
    /// Diff ligne à ligne (plus longue sous-suite commune). Suffisant pour un script de quelques centaines de lignes.
    public static func diff(_ old: [String], _ new: [String]) -> [DiffLine] {
        let n = old.count, m = new.count
        var lcs = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        if n > 0, m > 0 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    lcs[i][j] = old[i] == new[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
                }
            }
        }
        var out: [DiffLine] = []
        var i = 0, j = 0
        func push(_ k: DiffLine.Kind, _ t: String, _ o: Int?, _ nn: Int?) {
            out.append(DiffLine(id: out.count, kind: k, text: t, oldNumber: o, newNumber: nn))
        }
        while i < n || j < m {
            if i < n, j < m, old[i] == new[j] {
                push(.same, old[i], i + 1, j + 1)
                i += 1
                j += 1
            } else if j < m, i == n || lcs[i][j + 1] > lcs[i + 1][j] {  // à égalité : suppression d'abord
                push(.added, new[j], nil, j + 1)
                j += 1
            } else {
                push(.removed, old[i], i + 1, nil)
                i += 1
            }
        }
        return out
    }

    /// Ne garde que les changements et `context` lignes autour (les autres sont remplacées par « … »).
    public static func compact(_ lines: [DiffLine], context: Int = 2) -> [DiffLine] {
        let changed = lines.indices.filter { lines[$0].kind != .same }
        guard !changed.isEmpty else { return [] }
        var keep = Set<Int>()
        for c in changed { for k in max(0, c - context)...min(lines.count - 1, c + context) { keep.insert(k) } }
        var out: [DiffLine] = []
        var last = -1
        for k in keep.sorted() {
            if last >= 0, k > last + 1 {
                out.append(DiffLine(id: -k, kind: .same, text: "…", oldNumber: nil, newNumber: nil))
            }
            out.append(lines[k])
            last = k
        }
        return out
    }
}
