import Foundation

/// Simulation de forces animée, sur le modèle de d3-force (celle du Control Plane web) :
/// liens élastiques, répulsion entre nœuds, rappel vers le centre, refroidissement progressif (`alpha`).
///
/// - Déterministe : positions initiales en phyllotaxie, aucun aléa.
/// - Répulsion par quadtree de Barnes-Hut : coût O(n log n), fluide au-delà de 2 000 nœuds.
/// - Cible compilée en `-O` même en Debug (voir Package.swift) : la boucle tourne à chaque image.
/// - Coordonnées « monde » en points, centrées sur (0, 0) ; la vue applique zoom et déplacement.
public struct ForceSimulation: Sendable {
    public struct Link: Sendable, Hashable {
        public let a: Int
        public let b: Int
        public let weight: Double
        public init(_ a: Int, _ b: Int, weight: Double = 1) {
            self.a = a
            self.b = b
            self.weight = weight
        }
    }

    public private(set) var x: [Double]
    public private(set) var y: [Double]
    private var vx: [Double]
    private var vy: [Double]
    private let links: [Link]
    private let degree: [Int]
    private let linkStrength: [Double]
    private let linkBias: [Double]
    private var tree = QuadTree()

    public var alpha = 1.0
    public var alphaMin = 0.001
    public var alphaTarget = 0.0
    public var alphaDecay = 1 - pow(0.001, 1.0 / 300)
    public var velocityDecay = 0.4
    public var linkDistance = 30.0
    public var chargeStrength = -30.0
    /// Portée maximale de la répulsion (d3 : infinie) ; bornée pour qu'un composant isolé ne s'éloigne pas trop.
    public var chargeDistanceMax = 2000.0
    public var theta = 0.9
    public var centerStrength = 0.04

    public var count: Int { x.count }
    public var isSettled: Bool { alpha < alphaMin }

    public init(nodeCount n: Int, links: [Link]) {
        let valid = links.filter { $0.a != $0.b && $0.a >= 0 && $0.b >= 0 && $0.a < n && $0.b < n }
        self.links = valid
        var deg = [Int](repeating: 0, count: n)
        for l in valid {
            deg[l.a] += 1
            deg[l.b] += 1
        }
        degree = deg
        let maxW = max(valid.map(\.weight).max() ?? 1, 1e-9)
        // d3 : force = 1 / min(degré) ; pondérée ici par le poids relatif du lien.
        linkStrength = valid.map { l in (1.0 / Double(max(1, min(deg[l.a], deg[l.b])))) * (0.5 + 0.5 * l.weight / maxW) }
        linkBias = valid.map { l in Double(deg[l.a]) / Double(max(1, deg[l.a] + deg[l.b])) }
        // Phyllotaxie (d3) : répartition initiale régulière et déterministe.
        let radius = 10.0, angle = Double.pi * (3 - 5.0.squareRoot())
        x = (0..<n).map { i in radius * (0.5 + Double(i)).squareRoot() * cos(Double(i) * angle) }
        y = (0..<n).map { i in radius * (0.5 + Double(i)).squareRoot() * sin(Double(i) * angle) }
        vx = [Double](repeating: 0, count: n)
        vy = [Double](repeating: 0, count: n)
    }

    /// Relance l'animation (après un changement ou à la demande).
    public mutating func reheat(_ to: Double = 0.6) { alpha = max(alpha, to) }

    public func degree(of i: Int) -> Int { degree[i] }

    public mutating func tick(_ count: Int = 1) {
        for _ in 0..<count {
            alpha += (alphaTarget - alpha) * alphaDecay
            applyLinks()
            applyCharge()
            applyCenter()
            for i in 0..<x.count {
                vx[i] *= (1 - velocityDecay)
                vy[i] *= (1 - velocityDecay)
                x[i] += vx[i]
                y[i] += vy[i]
            }
        }
    }

    private mutating func applyLinks() {
        for (k, l) in links.enumerated() {
            var dx = x[l.b] + vx[l.b] - x[l.a] - vx[l.a]
            var dy = y[l.b] + vy[l.b] - y[l.a] - vy[l.a]
            if dx == 0, dy == 0 {
                dx = 1e-6 * Double(k % 7 + 1)
                dy = 1e-6 * Double(k % 5 + 1)
            }
            var d = (dx * dx + dy * dy).squareRoot()
            d = (d - linkDistance) / d * alpha * linkStrength[k]
            dx *= d
            dy *= d
            let bias = linkBias[k]
            vx[l.b] -= dx * bias
            vy[l.b] -= dy * bias
            vx[l.a] += dx * (1 - bias)
            vy[l.a] += dy * (1 - bias)
        }
    }

    /// Répulsion par quadtree de Barnes-Hut (comme d3-force, θ = 0,9) : O(n log n).
    private mutating func applyCharge() {
        let n = x.count
        guard n > 1 else { return }
        tree.build(x: x, y: y)
        let strength = chargeStrength * alpha
        let theta2 = theta * theta
        let maxD2 = chargeDistanceMax * chargeDistanceMax
        var stack = [Int32](repeating: 0, count: 256)
        tree.withBuffers { t in
            for i in 0..<n {
                let xi = x[i], yi = y[i]
                var fx = 0.0, fy = 0.0
                stack[0] = 0
                var top = 1
                while top > 0 {
                    top -= 1
                    let q = Int(stack[top])
                    let mass = t.mass[q]
                    if mass == 0 { continue }
                    let dx = t.cx[q] - xi, dy = t.cy[q] - yi
                    var d2 = dx * dx + dy * dy
                    let w = t.size[q]
                    let leafPoint = Int(t.point[q])
                    if leafPoint >= 0 {
                        // Feuille : un point (ou plusieurs confondus, cumulés dans mass).
                        let others = leafPoint == i ? mass - 1 : mass
                        if others <= 0 || d2 >= maxD2 { continue }
                        var ddx = dx, ddy = dy
                        if d2 < 1e-6 {
                            ddx = 1e-3 * Double((i &* 31) % 7 - 3)
                            ddy = 1e-3 * Double((i &* 17) % 5 - 2)
                            d2 = ddx * ddx + ddy * ddy + 1e-6
                        }
                        let f = strength * others / max(d2, 1)
                        fx += ddx * f
                        fy += ddy * f
                    } else if w * w < theta2 * d2 {
                        // Assez loin : la cellule agit comme un seul point.
                        if d2 >= maxD2 { continue }
                        let f = strength * mass / max(d2, 1)
                        fx += dx * f
                        fy += dy * f
                    } else {
                        for c in 0..<4 {
                            let child = t.child[q * 4 + c]
                            if child >= 0 {
                                if top >= stack.count { stack.append(0) }
                                stack[top] = child
                                top += 1
                            }
                        }
                    }
                }
                vx[i] += fx
                vy[i] += fy
            }
        }
    }

    private mutating func applyCenter() {
        let k = centerStrength * alpha
        for i in 0..<x.count {
            vx[i] -= x[i] * k
            vy[i] -= y[i] * k
        }
    }

    /// Boîte englobante des positions (pour « Recentrer »).
    public var bounds: (minX: Double, minY: Double, maxX: Double, maxY: Double) {
        guard !x.isEmpty else { return (0, 0, 0, 0) }
        return (x.min()!, y.min()!, x.max()!, y.max()!)
    }

    public var positions: [Point2] { zip(x, y).map { Point2($0, $1) } }
}

/// Point 2D (indépendant de CoreGraphics pour rester testable sous Linux).
public struct Point2: Sendable, Hashable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }
}

/// Fait tourner la simulation hors du fil principal ; la vue reçoit des instantanés de positions.
public actor GraphSimulationEngine {
    private var sim: ForceSimulation

    public init(_ sim: ForceSimulation) { self.sim = sim }

    public func step(_ ticks: Int) -> (positions: [Point2], settled: Bool, alpha: Double) {
        sim.tick(ticks)
        return (sim.positions, sim.isSettled, sim.alpha)
    }

    public func reheat(_ to: Double) { sim.reheat(to) }

    public func settle(maxTicks: Int = 600) -> [Point2] {
        var n = 0
        while !sim.isSettled, n < maxTicks {
            sim.tick()
            n += 1
        }
        return sim.positions
    }
}

/// Quadtree en tableaux plats, réutilisé d'un pas à l'autre (pas d'allocation en régime établi).
struct QuadTree: Sendable {
    struct Buffers {
        let cx: UnsafeBufferPointer<Double>
        let cy: UnsafeBufferPointer<Double>
        let mass: UnsafeBufferPointer<Double>
        let size: UnsafeBufferPointer<Double>
        let point: UnsafeBufferPointer<Int32>
        let child: UnsafeBufferPointer<Int32>
    }

    private var cx: [Double] = []
    private var cy: [Double] = []
    private var mass: [Double] = []
    private var size: [Double] = []
    /// Point d'une feuille (-1 pour un nœud interne ou vide).
    private var point: [Int32] = []
    /// 4 enfants par nœud (-1 = absent).
    private var child: [Int32] = []
    private var x0: [Double] = []
    private var y0: [Double] = []
    private(set) var count = 0

    private mutating func ensureCapacity(_ capacity: Int) {
        guard cx.count < capacity else { return }
        let extra = capacity - cx.count
        cx += [Double](repeating: 0, count: extra)
        cy += [Double](repeating: 0, count: extra)
        mass += [Double](repeating: 0, count: extra)
        size += [Double](repeating: 0, count: extra)
        x0 += [Double](repeating: 0, count: extra)
        y0 += [Double](repeating: 0, count: extra)
        point += [Int32](repeating: -1, count: extra)
        child += [Int32](repeating: -1, count: extra * 4)
    }

    private mutating func newNode(x0 nx: Double, y0 ny: Double, size s: Double) -> Int {
        if count >= cx.count { ensureCapacity(max(16, cx.count * 2)) }
        let q = count
        count += 1
        x0[q] = nx
        y0[q] = ny
        size[q] = s
        mass[q] = 0
        cx[q] = 0
        cy[q] = 0
        point[q] = -1
        for c in 0..<4 { child[q * 4 + c] = -1 }
        return q
    }

    mutating func build(x: [Double], y: [Double]) {
        let n = x.count
        ensureCapacity(n * 3 + 16)
        count = 0
        guard n > 0 else { return }
        var minX = x[0], maxX = x[0], minY = y[0], maxY = y[0]
        for i in 1..<n {
            minX = min(minX, x[i])
            maxX = max(maxX, x[i])
            minY = min(minY, y[i])
            maxY = max(maxY, y[i])
        }
        let side = max(maxX - minX, maxY - minY, 1) * 1.0001
        let root = newNode(x0: minX, y0: minY, size: side)
        for i in 0..<n { insert(i, px: x[i], py: y[i], root: root) }
        // Centres de masse : les enfants sont créés après leur parent, donc un parcours inverse suffit.
        for q in stride(from: count - 1, through: 0, by: -1) where point[q] < 0 {
            var m = 0.0, sx = 0.0, sy = 0.0
            for c in 0..<4 {
                let ch = Int(child[q * 4 + c])
                if ch >= 0, mass[ch] > 0 {
                    m += mass[ch]
                    sx += cx[ch] * mass[ch]
                    sy += cy[ch] * mass[ch]
                }
            }
            mass[q] = m
            if m > 0 {
                cx[q] = sx / m
                cy[q] = sy / m
            }
        }
    }

    private func isEmptyInternal(_ q: Int) -> Bool {
        point[q] < 0 && child[q * 4] < 0 && child[q * 4 + 1] < 0 && child[q * 4 + 2] < 0 && child[q * 4 + 3] < 0
    }

    private mutating func insert(_ i: Int, px: Double, py: Double, root: Int) {
        var q = root
        var depth = 0
        while true {
            if point[q] >= 0 {
                // Feuille occupée : point confondu (ou profondeur limite) → masse cumulée.
                if depth > 48 || (abs(cx[q] - px) < 1e-9 && abs(cy[q] - py) < 1e-9) {
                    mass[q] += 1
                    return
                }
                // Subdivise : l'occupant descend dans un enfant.
                let j = point[q], ox = cx[q], oy = cy[q], om = mass[q]
                point[q] = -1
                mass[q] = 0
                let c = childNode(q, quadrant(q, ox, oy))
                point[c] = j
                cx[c] = ox
                cy[c] = oy
                mass[c] = om
                continue
            }
            if isEmptyInternal(q) {
                point[q] = Int32(i)
                cx[q] = px
                cy[q] = py
                mass[q] = 1
                return
            }
            q = childNode(q, quadrant(q, px, py))
            depth += 1
        }
    }

    private func quadrant(_ q: Int, _ px: Double, _ py: Double) -> Int {
        let h = size[q] / 2
        return (px >= x0[q] + h ? 1 : 0) + (py >= y0[q] + h ? 2 : 0)
    }

    private mutating func childNode(_ q: Int, _ c: Int) -> Int {
        let existing = Int(child[q * 4 + c])
        if existing >= 0 { return existing }
        let h = size[q] / 2
        let n = newNode(x0: x0[q] + (c & 1 == 1 ? h : 0), y0: y0[q] + (c & 2 == 2 ? h : 0), size: h)
        child[q * 4 + c] = Int32(n)
        return n
    }

    func withBuffers<R>(_ body: (Buffers) -> R) -> R {
        cx.withUnsafeBufferPointer { a in
            cy.withUnsafeBufferPointer { b in
                mass.withUnsafeBufferPointer { m in
                    size.withUnsafeBufferPointer { s in
                        point.withUnsafeBufferPointer { p in
                            child.withUnsafeBufferPointer { c in
                                body(Buffers(cx: a, cy: b, mass: m, size: s, point: p, child: c))
                            }
                        }
                    }
                }
            }
        }
    }

    /// Masse totale (= nombre de points insérés) : pour les tests.
    var totalMass: Double { count > 0 ? mass[0] : 0 }
}
