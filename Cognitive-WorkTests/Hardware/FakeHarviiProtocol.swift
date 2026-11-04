//
//  FakeHarviiProtocol.swift
//  Cognitive-WorkTests
//
//  Created by Isabela Hissa Pinto on 03/11/26.
//

import Foundation

/// A fake Harvii for the tests: answers the app's requests to the device (the fixed
/// `192.168.4.1` and any `*.local` host) instead of the network. Every other request goes on as usual.
///
/// `HardwareNetworkManager` uses `URLSession.shared`, which honors protocols registered with
/// `URLProtocol.registerClass`, so no app code changes. Use it through ``withFakeHarvii(_:_:)``.
final class FakeHarviiProtocol: URLProtocol {
    
    /// What the fake Harvii answers.
    struct Answer {
        var status: Int = 200
        var json: [String: Any] = [:]
        
        static func ok(_ message: String = "ok", _ extra: [String: Any] = [:]) -> Answer {
            Answer(json: ["success": true, "message": message].merging(extra) { $1 })
        }
        
        static func failure(_ status: Int, _ message: String = "erro") -> Answer {
            Answer(status: status, json: ["success": false, "message": message])
        }
    }
    
    /// A request the fake Harvii got, with its body already read.
    struct Received {
        let request: URLRequest
        let body: Data
        
        var path: String { request.url?.path ?? "" }
        var host: String { request.url?.host ?? "" }
        var json: [String: Any] {
            (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        }
        func header(_ name: String) -> String? { request.value(forHTTPHeaderField: name) }
    }
    
    /// Decides the answer for each request; `nil` means the Harvii isn't reachable.
    nonisolated(unsafe) static var answer: (Received) -> Answer? = { _ in nil }
    /// Every request received, in order.
    nonisolated(unsafe) static var received: [Received] = []
    
    override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host else { return false }
        return host == "192.168.4.1" || host.hasSuffix(".local")
    }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    
    override func startLoading() {
        let received = Received(request: request, body: Self.body(of: request))
        Self.received.append(received)
        
        guard let answer = Self.answer(received), let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: answer.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        let data = (try? JSONSerialization.data(withJSONObject: answer.json)) ?? Data()
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    
    override func stopLoading() {}
    
    /// The body: `URLSession` hands it to protocols as a stream, not as `httpBody`.
    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

/// Runs `body` with the fake Harvii answering through `answer`, then removes it.
func withFakeHarvii(
    _ answer: @escaping (FakeHarviiProtocol.Received) -> FakeHarviiProtocol.Answer?,
    _ body: () async throws -> Void
) async rethrows {
    FakeHarviiProtocol.answer = answer
    FakeHarviiProtocol.received = []
    URLProtocol.registerClass(FakeHarviiProtocol.self)
    defer {
        URLProtocol.unregisterClass(FakeHarviiProtocol.self)
        FakeHarviiProtocol.answer = { _ in nil }
    }
    try await body()
}

/// The keys `HardwareNetworkManager` saves on the phone.
let hardwareStorageKeys = ["hardware.hash", "hardware.host", "hardware.name"]

/// Runs `body` with `values` saved under the hardware keys (the others removed), putting the
/// phone's original values back afterwards.
func withSavedHardware(_ values: [String: String] = [:], _ body: () async throws -> Void) async rethrows {
    let defaults = UserDefaults.standard
    let previous = hardwareStorageKeys.map { ($0, defaults.object(forKey: $0)) }
    for key in hardwareStorageKeys {
        if let value = values[key] {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
    defer {
        for (key, value) in previous { defaults.set(value, forKey: key) }
    }
    try await body()
}
