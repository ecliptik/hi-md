import Foundation
import OSLog

/// Decodes one element of a JSON array without letting a single bad entry fail the whole array.
nonisolated struct LossyDecodable<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: any Decoder) throws {
        value = try? decoder.singleValueContainer().decode(Value.self)
    }
}

nonisolated enum JSONStoreRecovery {
    /// Copies an unreadable store aside so it can be inspected and is not lost when the next save
    /// overwrites it. The original stays in place; a following write replaces it.
    @discardableResult
    static func quarantine(_ url: URL, logger: Logger, fileManager: FileManager = .default) -> URL? {
        let stamp = Int(Date().timeIntervalSince1970)
        let name = url.deletingPathExtension().lastPathComponent
        let destination = url.deletingLastPathComponent()
            .appendingPathComponent("\(name).unreadable-\(stamp).\(url.pathExtension)")
        do {
            try fileManager.copyItem(at: url, to: destination)
            logger.error("Kept an unreadable copy of '\(url.lastPathComponent, privacy: .public)' as '\(destination.lastPathComponent, privacy: .public)'")
            return destination
        } catch {
            logger.error("Could not keep an unreadable copy of '\(url.lastPathComponent, privacy: .public)': \(error, privacy: .public)")
            return nil
        }
    }

    /// Decodes a JSON array, dropping entries that no longer decode instead of failing outright.
    /// Throws only when the data is not a JSON array at all.
    static func decodeArray<Element: Decodable>(_ type: Element.Type, from data: Data) throws -> (elements: [Element], dropped: Int) {
        let entries = try JSONDecoder().decode([LossyDecodable<Element>].self, from: data)
        let elements = entries.compactMap(\.value)
        return (elements, entries.count - elements.count)
    }
}
