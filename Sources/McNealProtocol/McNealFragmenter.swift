//
//  McNealFragmenter.swift
//  MCNEALProtocol
//
//  Created by Antonio Lambert on 12/18/25.
//


import Foundation

/// Splits and reassembles long payloads for McNeal DATA frames.
/// This is a pure helper — encryption happens elsewhere.
//public enum McNealFragmenter {
public final class McNealFragmenter {
    static let shared = McNealFragmenter()
    private init() {}
    // MARK: - Fragment metadata (encrypted inside payload)

    public struct FragmentHeader: Codable {
        public let messageId: UUID
        public let index: UInt32
        public let total: UInt32

        public init(messageId: UUID, index: UInt32, total: UInt32) {
            self.messageId = messageId
            self.index = index
            self.total = total
        }
    }

    // MARK: - Fragmenting

    /// Split data into fragments with headers.
    /// - Parameters:
    ///   - data: full payload (text bytes, media bytes, WAV bytes, etc.)
    ///   - maxChunkSize: max bytes per fragment payload (not including header)
    public static func fragment(
        _ data: Data,
        maxChunkSize: Int = 4096
    ) -> [(header: FragmentHeader, payload: Data)] {

        precondition(maxChunkSize > 0)

        let messageId = UUID()
        let total = UInt32((data.count + maxChunkSize - 1) / maxChunkSize)

        var result: [(FragmentHeader, Data)] = []
        result.reserveCapacity(Int(total))

        var offset = 0
        var index: UInt32 = 0

        while offset < data.count {
            let end = min(offset + maxChunkSize, data.count)
            let chunk = data.subdata(in: offset..<end)

            let header = FragmentHeader(
                messageId: messageId,
                index: index,
                total: total
            )

            result.append((header, chunk))

            offset = end
            index += 1
        }

        return result
    }

    // MARK: - Packing (header + payload)

    /// Pack header + payload into a single Data blob (to be encrypted).
    public static func pack(header: FragmentHeader, payload: Data) throws -> Data {
        let headerData = try JSONEncoder().encode(header)

        var out = Data()
        out.reserveCapacity(4 + headerData.count + payload.count)

        // Prefix header length (UInt32 BE)
        var len = UInt32(headerData.count).bigEndian
        out.append(Data(bytes: &len, count: 4))
        out.append(headerData)
        out.append(payload)

        return out
    }

    /// Unpack header + payload after decryption.
    public static func unpack(_ data: Data) throws -> (FragmentHeader, Data) {
        guard data.count >= 4 else {
            throw FragmentError.invalidFormat
        }

        let len = data.prefix(4).withUnsafeBytes {
            $0.load(as: UInt32.self).bigEndian
        }

        let headerStart = 4
        let headerEnd = headerStart + Int(len)

        guard headerEnd <= data.count else {
            throw FragmentError.invalidFormat
        }

        let headerData = data.subdata(in: headerStart..<headerEnd)
        let payload = data.subdata(in: headerEnd..<data.count)

        let header = try JSONDecoder().decode(FragmentHeader.self, from: headerData)
        return (header, payload)
    }

    // MARK: - Reassembly

    public final class Reassembler {

        private struct Bucket {
            let total: UInt32
            var parts: [UInt32: Data]
        }

        private var buckets: [UUID: Bucket] = [:]

        public init() {}

        /// Insert a fragment. Returns full reassembled Data when complete.
        public func insert(
            header: FragmentHeader,
            payload: Data
        ) -> Data? {

            var bucket = buckets[header.messageId] ??
                Bucket(total: header.total, parts: [:])

            bucket.parts[header.index] = payload
            buckets[header.messageId] = bucket

            guard bucket.parts.count == Int(bucket.total) else {
                return nil
            }

            // Reassemble in order
            var out = Data()
            for i in 0..<bucket.total {
                guard let part = bucket.parts[i] else {
                    return nil
                }
                out.append(part)
            }

            // Cleanup
            buckets.removeValue(forKey: header.messageId)

            return out
        }

        /// Optional: drop partial messages (timeout / cancel)
        public func discard(messageId: UUID) {
            buckets.removeValue(forKey: messageId)
        }
    }

    // MARK: - Errors

    public enum FragmentError: Error {
        case invalidFormat
    }
    
    // MARK: - Shared Reassembler (for single-shot flows like Messenger)

    private static let reassembler = Reassembler()

    
    // MARK: - Detection

    /// Check if data appears to be fragmented (has our fragment header).
    public static func isFragmented(_ data: Data) -> Bool {
        // Need at least 4 bytes for length prefix
        guard data.count >= 4 else {
            return false
        }
        
        // Read the header length
        let headerLen = data.prefix(4).withUnsafeBytes {
            $0.load(as: UInt32.self).bigEndian
        }
        
        // Sanity check: header should be reasonable size (< 1KB)
        // and must fit within remaining data
        guard headerLen > 0 && headerLen < 1024 && Int(headerLen) + 4 <= data.count else {
            return false
        }
        
        // Try to decode the header to verify it's valid JSON with our structure
        let headerStart = 4
        let headerEnd = headerStart + Int(headerLen)
        let headerData = data.subdata(in: headerStart..<headerEnd)
        
        // If we can decode a FragmentHeader, it's fragmented
        return (try? JSONDecoder().decode(FragmentHeader.self, from: headerData)) != nil
    }

    /// Smart wrapper: returns data as-is if not fragmented, otherwise reassembles.
    public static func insertFragmentAndTryReassemble(_ data: Data) -> Data? {
        //  Check if this is actually fragmented data
        guard isFragmented(data) else {
            return data  // Return directly, no unpacking needed
        }
        
        // Original fragmented path
        do {
            let (header, payload) = try unpack(data)
            return reassembler.insert(header: header, payload: payload)
        } catch {
            return nil
        }
    }

}
