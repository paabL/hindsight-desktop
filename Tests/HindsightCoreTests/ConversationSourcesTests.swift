import Foundation
import HindsightAPI
import XCTest

@testable import HindsightCore

final class ConversationSourcesTests: XCTestCase {
    func testConversationSourcesDescribeCollectedCodexAndClaudeData() {
        XCTAssertEqual(ConversationSource.allCases, [.codex, .claudeCode])
        XCTAssertEqual(ConversationSource.codex.documentPrefix, "codex")
        XCTAssertEqual(ConversationSource.claudeCode.documentPrefix, "claude-code")
    }

    func testSessionSourceUsesExplicitMetadataThenFileLocation() {
        var claude = CodexSessionSummary(file: CodexFile(url: URL(fileURLWithPath: "/example/.claude/projects/project/session.jsonl")))
        XCTAssertEqual(claude.source, .claudeCode)
        claude.meta = CodexSessionMeta(id: "session")
        XCTAssertEqual(claude.source, .claudeCode, "Les anciennes métadonnées sans source ne masquent pas l'emplacement Claude")
        claude.meta?.sourceKind = .codex
        XCTAssertEqual(claude.source, .codex, "La source explicite prime sur l'emplacement")

        var codex = CodexSessionSummary(file: CodexFile(url: URL(fileURLWithPath: "/example/.codex/sessions/session.jsonl")))
        XCTAssertEqual(codex.source, .codex)
        codex.meta = CodexSessionMeta(id: "session", sourceKind: .claudeCode)
        XCTAssertEqual(codex.source, .claudeCode)
    }

    func testConversationDocumentsKeepTheirSourceIdentity() throws {
        for source in ConversationSource.allCases {
            let meta = CodexSessionMeta(id: "session", sourceKind: source)
            let conversation = CodexConversation(meta: meta, events: [
                .user(ordinal: 1, date: nil, blocks: [.text("Corrige le test")]),
                .assistant(ordinal: 2, date: nil, text: "Le test est corrigé.", phase: nil),
            ])
            let tasks = CodexTranscript.tasks(conversation)
            XCTAssertEqual(tasks.count, 1)
            let task = try XCTUnwrap(tasks.first)
            XCTAssertEqual(task.documentID, "\(source.documentPrefix)-session-task-001")
            let item = CodexTranscript.memoryItem(task, meta: meta, options: CodexImportOptions())
            XCTAssertEqual(item.documentId, task.documentID)
            XCTAssertEqual(item.metadata?["source"], source.rawValue)
            XCTAssertEqual(item.metadata?["session_id"], "session")
            XCTAssertTrue(item.tags?.contains("source:\(source.rawValue)") == true)
            XCTAssertEqual(item.content, task.content)
        }
    }

    func testHistoricalDocumentsFromRetiredSourcesRemainVisible() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "documents_retired_source", withExtension: "json", subdirectory: "Fixtures"))
        let documents = try JSONDecoder().decode(ListDocumentsResponse.self, from: Data(contentsOf: url)).items
        let report = FileCoverage.report(files: [], documents: documents) { _ in nil }
        let items = DocumentLibrary.build(report: report)
        XCTAssertEqual(items.count, documents.count)
        XCTAssertEqual(Set(items.flatMap { $0.documents.map(\.id) }), Set(documents.map(\.id)))
        for document in documents {
            let item = try XCTUnwrap(items.first { $0.documents.contains { $0.id == document.id } })
            XCTAssertEqual(item.state, .stored)
            XCTAssertEqual(item.documents, [document], "Conserver les identifiants, métadonnées et tags historiques")
            XCTAssertFalse(item.canSend)
            XCTAssertNil(item.sourceURL)
        }
    }
}
