import Foundation
import HindsightAPI
import HindsightTestSupport
import XCTest

enum Fixture {
    static func string(_ name: String, ext: String = "json") -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"),
            let s = try? String(contentsOf: url, encoding: .utf8)
        else {
            XCTFail("Fixture introuvable : \(name).\(ext)")
            return "{}"
        }
        return s
    }
}

let testBank = "codex-diag-01a12843"
let bankPath = "/v1/default/banks/\(testBank)"

extension MockTransport {
    /// Installe les routes de lecture courantes avec les fixtures.
    func installStandardRoutes() {
        on("GET", "/version", json: Fixture.string("version"))
        on("GET", "/v1/default/banks", json: Fixture.string("banks"))
        on("GET", "\(bankPath)/stats", json: Fixture.string("bank_stats"))
        on("GET", "\(bankPath)/entities", json: Fixture.string("entities_1"))
        on("GET", "\(bankPath)/stats/memories-timeseries", json: Fixture.string("timeseries"))
        on("GET", "\(bankPath)/tags", json: Fixture.string("tags"))
        on("GET", "\(bankPath)/config", json: Fixture.string("bank_config"))
        on("GET", "\(bankPath)/documents") { req in
            .json(Fixture.string(req.queryValue("offset") == "3" ? "documents_page2" : "documents_page1"))
        }
        on("GET", "\(bankPath)/documents/codex-abc-task-002", json: Fixture.string("document_task"))
        on("GET", "\(bankPath)/documents/codex-abc-task-002/chunks", json: Fixture.string("chunks_task"))
        on("GET", "\(bankPath)/memories/list", json: Fixture.string("memories_doc"))
        on("GET", "\(bankPath)/operations", json: Fixture.string("operations_list"))
        on("GET", "\(bankPath)/operations/op-f1", json: Fixture.string("operation_status_failed"))
    }
}

func makeClient(_ transport: MockTransport) -> HindsightClient {
    HindsightClient(baseURL: URL(string: "http://127.0.0.1:8888")!, transport: transport)
}
