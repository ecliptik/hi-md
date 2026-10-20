import Foundation

/// Remembers the last result of an expensive derivation (sorting, grouping, indexing) for a view.
///
/// SwiftUI re-evaluates `body` whenever any dependency changes, so work written directly in `body`
/// repeats even when its inputs did not change. Hold an instance in `@State` and read through
/// `value(for:compute:)`: the closure runs only when `key` differs from the previous call. Array
/// equality short-circuits when both sides share storage, so an unchanged source costs O(1).
///
/// The cache is deliberately not observable. Writing to it from `body` must not invalidate the view.
@MainActor
final class DerivedValueCache<Key: Equatable, Value> {
    private var stored: (key: Key, value: Value)?

    func value(for key: Key, compute: () -> Value) -> Value {
        if let stored, stored.key == key { return stored.value }
        let value = compute()
        stored = (key, value)
        return value
    }
}
