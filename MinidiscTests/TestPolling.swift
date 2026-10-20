import Foundation

/// Polls `condition` until it holds or `timeout` passes, and returns whether it held.
///
/// Use this instead of a fixed sleep before asserting that something asynchronous happened: a full
/// parallel run can delay a main-actor task far past a few milliseconds, while a successful poll
/// still returns as soon as the condition is true.
@MainActor
func pollUntil(
    timeout: Duration = .seconds(5),
    interval: Duration = .milliseconds(10),
    _ condition: @MainActor () async -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: interval)
    }
    return await condition()
}
