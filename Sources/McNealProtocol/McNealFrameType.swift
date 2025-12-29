//
//  McNealFrameType.swift
//  MCNEALProtocol
//
//  Created by Antonio Lambert on 12/18/25.
//

import Foundation

public enum McNealFrameType: UInt8, Sendable {
    case data  = 0x01
    case ack   = 0x02
    case ping  = 0x03
    case pong  = 0x04
    case close = 0x05
}

public struct McNealFrameHeader: Sendable, Equatable {
    public static let magic: UInt32 = 0x4D434E4C // "MCNL"
    public static let version: UInt8 = 1

    public var frameType: McNealFrameType
    public var flags: UInt8
    public var seq: UInt64
    public var sessionId: UUID

    public init(frameType: McNealFrameType, flags: UInt8 = 0, seq: UInt64, sessionId: UUID) {
        self.frameType = frameType
        self.flags = flags
        self.seq = seq
        self.sessionId = sessionId
    }
}

/// A simple binary frame:
/// [magic u32][version u8][type u8][flags u8][reserved u8]
/// [seq u64][sessionId 16 bytes][cipherLen u32][ciphertext...]
public struct McNealFrame: Sendable, Equatable {

    public let header: McNealFrameHeader
    public let ciphertext: Data

    public init(header: McNealFrameHeader, ciphertext: Data) {
        self.header = header
        self.ciphertext = ciphertext
    }

    public func encode() -> Data {
        var out = Data()
        out.reserveCapacity(4 + 1 + 1 + 1 + 1 + 8 + 16 + 4 + ciphertext.count)

        out.appendU32BE(McNealFrameHeader.magic)
        out.appendU8(McNealFrameHeader.version)
        out.appendU8(header.frameType.rawValue)
        out.appendU8(header.flags)
        out.appendU8(0) // reserved

        out.appendU64BE(header.seq)
        out.appendUUID(header.sessionId)

        out.appendU32BE(UInt32(ciphertext.count))
        out.append(ciphertext)

        return out
    }

    public static func decode(_ data: Data) throws -> McNealFrame {
        var c = Cursor(data)

        let magic = try c.readU32BE()
        guard magic == McNealFrameHeader.magic else {
            throw McNealFrameError.invalidMagic
        }

        let ver = try c.readU8()
        guard ver == McNealFrameHeader.version else {
            throw McNealFrameError.unsupportedVersion(ver)
        }

        let typeRaw = try c.readU8()
        guard let t = McNealFrameType(rawValue: typeRaw) else {
            throw McNealFrameError.invalidType(typeRaw)
        }

        let flags = try c.readU8()
        _ = try c.readU8() // reserved

        let seq = try c.readU64BE()
        let sid = try c.readUUID()

        let clen = try c.readU32BE()
        guard clen <= UInt32(c.remaining) else {
            throw McNealFrameError.invalidLength
        }

        let cipher = try c.readData(Int(clen))

        let header = McNealFrameHeader(frameType: t, flags: flags, seq: seq, sessionId: sid)
        return McNealFrame(header: header, ciphertext: cipher)
    }
}

public enum McNealFrameError: Error, Sendable {
    case invalidMagic
    case unsupportedVersion(UInt8)
    case invalidType(UInt8)
    case invalidLength
    case cursorUnderflow
}

// MARK: - Cursor + Data helpers

private struct Cursor {
    private let data: Data
    private var idx: Int = 0

    init(_ data: Data) { self.data = data }

    var remaining: Int { data.count - idx }

    mutating func readU8() throws -> UInt8 {
        guard remaining >= 1 else { throw McNealFrameError.cursorUnderflow }
        defer { idx += 1 }
        return data[idx]
    }

    mutating func readU32BE() throws -> UInt32 {
        let d = try readData(4)
        return d.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
    }

    mutating func readU64BE() throws -> UInt64 {
        let d = try readData(8)
        return d.withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
    }

    mutating func readUUID() throws -> UUID {
        let d = try readData(16)
        let b = [UInt8](d)
        guard b.count == 16 else { throw McNealFrameError.cursorUnderflow }
        return UUID(uuid: (
            b[0], b[1], b[2], b[3],
            b[4], b[5],
            b[6], b[7],
            b[8], b[9],
            b[10], b[11], b[12], b[13], b[14], b[15]
        ))
    }

    mutating func readData(_ count: Int) throws -> Data {
        guard remaining >= count else { throw McNealFrameError.cursorUnderflow }
        let slice = data.subdata(in: idx..<(idx + count))
        idx += count
        return slice
    }
}

private extension Data {
    mutating func appendU8(_ v: UInt8) { append(contentsOf: [v]) }

    mutating func appendU32BE(_ v: UInt32) {
        var x = v.bigEndian
        append(Data(bytes: &x, count: 4))
    }

    mutating func appendU64BE(_ v: UInt64) {
        var x = v.bigEndian
        append(Data(bytes: &x, count: 8))
    }

    mutating func appendUUID(_ uuid: UUID) {
        var u = uuid.uuid
        append(Data(bytes: &u.0, count: 16))
    }
}
