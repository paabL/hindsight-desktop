// swift-tools-version: 6.0
import PackageDescription

// HindsightAPI  : modèles Codable (générés depuis docs/openapi.json) + client HTTP pur.
// HindsightCore : ViewModels, services (éditeur de script de lancement, diff, etc.). Aucune dépendance UI.
// HindsightBridge : pont privé du moteur vers l’application Tauri / React (macOS uniquement).
var products: [Product] = [
    .library(name: "HindsightAPI", targets: ["HindsightAPI"]),
    .library(name: "HindsightCore", targets: ["HindsightCore"]),
]

var targets: [Target] = [
    .target(name: "HindsightAPI"),
    // Moteur de disposition du graphe : compilé optimisé même en Debug (calcul à chaque image).
    .target(name: "HindsightLayout", swiftSettings: [.unsafeFlags(["-O"])]),
    .target(name: "HindsightCore", dependencies: ["HindsightAPI", "HindsightLayout"]),
    // Faux serveur HTTP + lecteur d'OpenAPI, partagés par les tests (jamais lié à l'app).
    .target(name: "HindsightTestSupport", dependencies: ["HindsightAPI"]),
    .testTarget(
        name: "HindsightAPITests",
        dependencies: ["HindsightAPI", "HindsightTestSupport"],
        resources: [.copy("Fixtures")]
    ),
    .testTarget(
        name: "HindsightCoreTests",
        dependencies: ["HindsightCore", "HindsightAPI", "HindsightLayout", "HindsightTestSupport"],
        resources: [.copy("Fixtures")],
        swiftSettings: [.swiftLanguageMode(.v5)]  // classes de test @MainActor : évite du bruit d'isolation d'XCTest
    ),
]

#if os(macOS)
products += [
    .executable(name: "HindsightBridge", targets: ["HindsightBridge"]),
]
targets += [
    .executableTarget(name: "HindsightBridge", dependencies: ["HindsightCore", "HindsightAPI"], swiftSettings: [.swiftLanguageMode(.v5)]),
]
#endif

let package = Package(
    name: "Hindsight",
    platforms: [.macOS(.v15)],
    products: products,
    targets: targets,
    swiftLanguageModes: [.v6]
)
