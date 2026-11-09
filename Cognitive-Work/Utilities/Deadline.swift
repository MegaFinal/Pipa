//
//  Deadline.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 09/11/26.
//

import Foundation

/// Thrown by ``withDeadline(_:operation:)`` when the work takes longer than allowed.
struct DeadlineExceededError: Error {}

/// Runs `operation`, but stops waiting for it after `duration`.
///
/// CloudKit keeps retrying on a weak connection instead of failing, so a screen that waits for it
/// can stay stuck for minutes. This returns as soon as either the work or the deadline finishes:
/// on time, the work's result (or its error); late, ``DeadlineExceededError``. The late work is
/// cancelled and its result ignored.
func withDeadline<T>(
    _ duration: Duration,
    operation: @escaping () async throws -> T
) async throws -> T {
    let gate = DeadlineGate()
    return try await withCheckedThrowingContinuation { continuation in
        let work = Task {
            do {
                let value = try await operation()
                if gate.close() { continuation.resume(returning: value) }
            } catch {
                if gate.close() { continuation.resume(throwing: error) }
            }
        }
        Task {
            try? await Task.sleep(for: duration)
            guard gate.close() else { return }
            work.cancel()
            continuation.resume(throwing: DeadlineExceededError())
        }
    }
}

/// Lets only the first of the work and the deadline resume the continuation.
private final class DeadlineGate {
    private var isClosed = false

    /// `true` the first time it is called, `false` afterwards.
    func close() -> Bool {
        guard !isClosed else { return false }
        isClosed = true
        return true
    }
}
