import Compression
import Foundation

/// A minimal ZIP reader for `.wsz` skins: the central directory, stored and DEFLATE entries, and
/// CRC checks. ZIP64, encryption and multi-disk archives aren't supported; skins never use them.
nonisolated struct ZipArchive: Sendable {
    nonisolated struct Entry: Sendable, Hashable {
        /// The path inside the archive, with `/` separators.
        let path: String
        let method: UInt16
        let flags: UInt16
        let crc32: UInt32
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int

        var fileName: String { path.split(separator: "/").last.map(String.init) ?? path }
        var isDirectory: Bool { path.hasSuffix("/") }
        /// macOS adds `__MACOSX/` and `._name` resource-fork entries when zipping in Finder.
        var isMetadata: Bool {
            path.split(separator: "/").contains { $0 == "__MACOSX" } || fileName.hasPrefix("._")
        }
    }

    enum ZipError: Error, Equatable {
        case notAZip
        case truncated
        case unsupported(String)
        case corrupt(String)
        case tooLarge(String)
    }

    static let storedMethod: UInt16 = 0
    static let deflateMethod: UInt16 = 8
    /// Skins are a few hundred KB; this bounds what a hostile archive can make us allocate.
    static let maximumEntrySize = 32 * 1024 * 1024

    /// Whole archives larger than this are refused before they are copied or read. Classic skins
    /// are well under 1 MB.
    static let maximumArchiveSize = 16 * 1024 * 1024

    let entries: [Entry]
    private let bytes: [UInt8]

    init(data: Data) throws {
        guard data.count <= Self.maximumArchiveSize else { throw ZipError.tooLarge("archive") }
        bytes = [UInt8](data)
        entries = try Self.readCentralDirectory(bytes)
    }

    /// The shallowest file whose name matches case-insensitively, in any folder. Skins are often
    /// zipped inside a folder and vary the case of their file names.
    func entry(named name: String) -> Entry? {
        let wanted = name.lowercased()
        return entries
            .filter { !$0.isDirectory && !$0.isMetadata && $0.fileName.lowercased() == wanted }
            .min { $0.path.split(separator: "/").count < $1.path.split(separator: "/").count }
    }

    /// The entry's bytes. Entries larger than `maximumSize` are refused before anything is inflated.
    func contents(of entry: Entry, maximumSize: Int = maximumEntrySize) throws -> Data {
        guard entry.flags & 0x1 == 0 else { throw ZipError.unsupported("encrypted entry \(entry.path)") }
        guard entry.uncompressedSize <= min(maximumSize, Self.maximumEntrySize) else { throw ZipError.tooLarge(entry.path) }
        let header = entry.localHeaderOffset
        guard header + 30 <= bytes.count, Self.uint32(bytes, header) == 0x0403_4B50 else {
            throw ZipError.corrupt("local header for \(entry.path)")
        }
        let start = header + 30 + Int(Self.uint16(bytes, header + 26)) + Int(Self.uint16(bytes, header + 28))
        guard start + entry.compressedSize <= bytes.count else { throw ZipError.truncated }
        let compressed = bytes[start..<(start + entry.compressedSize)]

        let output: [UInt8]
        switch entry.method {
        case Self.storedMethod:
            output = Array(compressed)
        case Self.deflateMethod:
            output = try Self.inflate(compressed, expectedSize: entry.uncompressedSize, path: entry.path)
        default:
            throw ZipError.unsupported("compression method \(entry.method) for \(entry.path)")
        }
        guard output.count == entry.uncompressedSize else { throw ZipError.corrupt("size of \(entry.path)") }
        guard Self.crc32(output) == entry.crc32 else { throw ZipError.corrupt("checksum of \(entry.path)") }
        return Data(output)
    }

    func contents(named name: String, maximumSize: Int = maximumEntrySize) throws -> Data? {
        guard let entry = entry(named: name) else { return nil }
        return try contents(of: entry, maximumSize: maximumSize)
    }

    // MARK: Central directory

    private static func readCentralDirectory(_ bytes: [UInt8]) throws -> [Entry] {
        guard bytes.count >= 22 else { throw ZipError.notAZip }
        // The end record sits in the last 22 bytes plus an optional comment of up to 64 KB.
        let lowest = max(0, bytes.count - 22 - 0xFFFF)
        guard let end = stride(from: bytes.count - 22, through: lowest, by: -1)
            .first(where: { uint32(bytes, $0) == 0x0605_4B50 }) else { throw ZipError.notAZip }
        let count = Int(uint16(bytes, end + 10))
        let size = Int(uint32(bytes, end + 12))
        let offset = Int(uint32(bytes, end + 16))
        guard count != 0xFFFF, size != 0xFFFF_FFFF, offset != 0xFFFF_FFFF else { throw ZipError.unsupported("ZIP64") }
        guard offset + size <= bytes.count else { throw ZipError.truncated }

        var entries: [Entry] = []
        entries.reserveCapacity(count)
        var cursor = offset
        for _ in 0..<count {
            guard cursor + 46 <= bytes.count, uint32(bytes, cursor) == 0x0201_4B50 else {
                throw ZipError.corrupt("central directory")
            }
            let flags = uint16(bytes, cursor + 8)
            let nameLength = Int(uint16(bytes, cursor + 28))
            let extraLength = Int(uint16(bytes, cursor + 30))
            let commentLength = Int(uint16(bytes, cursor + 32))
            guard cursor + 46 + nameLength <= bytes.count else { throw ZipError.truncated }
            let nameBytes = bytes[(cursor + 46)..<(cursor + 46 + nameLength)]
            // Bit 11 marks UTF-8 names; older tools wrote code page 437, close enough to Latin-1 here.
            let path = (flags & 0x800 != 0 ? String(bytes: nameBytes, encoding: .utf8) : nil)
                ?? String(bytes: nameBytes, encoding: .utf8)
                ?? String(bytes: nameBytes, encoding: .isoLatin1)
                ?? ""
            entries.append(Entry(
                path: path.replacingOccurrences(of: "\\", with: "/"),
                method: uint16(bytes, cursor + 10),
                flags: flags,
                crc32: uint32(bytes, cursor + 16),
                compressedSize: Int(uint32(bytes, cursor + 20)),
                uncompressedSize: Int(uint32(bytes, cursor + 24)),
                localHeaderOffset: Int(uint32(bytes, cursor + 42))
            ))
            cursor += 46 + nameLength + extraLength + commentLength
        }
        return entries
    }

    /// Compression's `COMPRESSION_ZLIB` is raw DEFLATE (RFC 1951), which is what ZIP stores.
    private static func inflate(_ compressed: ArraySlice<UInt8>, expectedSize: Int, path: String) throws -> [UInt8] {
        guard expectedSize > 0 else { return [] }
        guard !compressed.isEmpty else { throw ZipError.corrupt("deflate stream of \(path)") }
        var output = [UInt8](repeating: 0, count: expectedSize)
        let written = compressed.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer { destination in
                compression_decode_buffer(
                    destination.baseAddress!, expectedSize,
                    source.baseAddress!, source.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written == expectedSize else { throw ZipError.corrupt("deflate stream of \(path)") }
        return output
    }

    // MARK: Helpers

    private static func uint16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    private static func uint32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
    }

    private static let crcTable: [UInt32] = (0..<256).map { index in
        (0..<8).reduce(UInt32(index)) { crc, _ in crc & 1 == 1 ? 0xEDB8_8320 ^ (crc >> 1) : crc >> 1 }
    }

    /// The CRC-32 that ZIP uses (IEEE 802.3, reflected).
    static func crc32<Bytes: Sequence>(_ bytes: Bytes) -> UInt32 where Bytes.Element == UInt8 {
        ~bytes.reduce(UInt32.max) { crc, byte in crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
    }
}
