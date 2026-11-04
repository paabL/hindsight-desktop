#if os(macOS)
import Foundation
import XCTest
import Darwin
@testable import HindsightAPI

/// Vérifie le transport réel, avec deux serveurs éphémères sur la boucle locale.
final class TransportSecurityTests: XCTestCase {
    func testSameOriginRedirectPreservesTheRequest() async throws {
        let server = try RedirectFixture()
        defer { server.close() }
        let client = HindsightClient(baseURL: server.url, authorization: "Bearer fixture-only")
        let request = APIRequest("POST", ["same"], body: .json(Data(#"{"text":"fixture body"}"#.utf8)))
        let (_, response) = try await client.perform(request)
        XCTAssertEqual(response.statusCode, 200)
        let records = try await server.records()
        XCTAssertEqual(records.map(\.path), ["/same", "/capture"])
        XCTAssertEqual(records.last?.authorization, "Bearer fixture-only")
        XCTAssertEqual(records.last?.body, #"{"text":"fixture body"}"#)
    }

    func testCrossOriginRedirectNeverSendsBodyOrAuthorization() async throws {
        let server = try RedirectFixture()
        defer { server.close() }
        let client = HindsightClient(baseURL: server.url, authorization: "Bearer fixture-only")
        let request = APIRequest("POST", ["foreign"], body: .json(Data(#"{"text":"fixture body"}"#.utf8)))
        do {
            _ = try await client.perform(request)
            XCTFail("La redirection doit être refusée.")
        } catch let error as HindsightError {
            XCTAssertEqual(error.httpStatus, 307)
        }
        let records = try await server.records()
        XCTAssertEqual(records.map(\.path), ["/foreign"], "Le serveur destinataire ne doit recevoir aucune requête.")
    }
}

private final class RedirectFixture {
    struct Record: Decodable, Sendable {
        let path: String
        let authorization: String?
        let body: String
    }

    let process: Process
    let url: URL

    init() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-u", "-c", #"""
import http.server, json, threading
records = []
class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get('Content-Length', 0))).decode()
        records.append({'path': self.path, 'authorization': self.headers.get('Authorization'), 'body': body})
        if self.path in ('/same', '/foreign'):
            self.send_response(307)
            self.send_header('Location', '/capture' if self.path == '/same' else 'http://127.0.0.1:%d/capture' % other.server_port)
            self.send_header('Content-Length', '0')
            self.end_headers()
        else:
            self.send_response(200)
            self.send_header('Content-Length', '2')
            self.end_headers()
            self.wfile.write(b'{}')
    def do_GET(self):
        data = json.dumps(records).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)
    def log_message(self, *args): pass
other = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
threading.Thread(target=other.serve_forever, daemon=True).start()
server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
print(server.server_port, flush=True)
server.serve_forever()
"""#]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        var line = Data()
        while let data = try pipe.fileHandleForReading.read(upToCount: 1), !data.isEmpty, data[0] != 10 {
            line.append(data)
        }
        guard let port = Int(String(decoding: line, as: UTF8.self)),
              let url = URL(string: "http://127.0.0.1:\(port)") else {
            process.terminate()
            throw HindsightError.refused("Serveur de test indisponible.")
        }
        self.process = process
        self.url = url
    }

    func records() async throws -> [Record] {
        let client = HindsightClient(baseURL: url)
        return try await client.send(APIRequest("GET", ["records"]))
    }

    func close() {
        if process.isRunning { kill(process.processIdentifier, SIGKILL); process.waitUntilExit() }
    }
}
#endif
