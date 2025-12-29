//
//  McNealRole.swift
//  MCNEALProtocol
//
//  Created by Antonio Lambert on 12/18/25.
//
import Foundation
import CryptoKit

public enum McNealRole {
    case initiator
    case responder
}

///
/// - You initialize with rootKey + role
/// - It gives you directional chain keys (send/recv)
/// - Each send/recv can derive a msgKey for a given seq
/// - Each direction steps independently
public struct McNealRatchet {

    // MARK: - State

    private(set) var sendChainKey: Data   // 32 bytes
    private(set) var recvChainKey: Data   // 32 bytes

    private(set) var sendSeq: UInt64 = 0
    private(set) var recvSeq: UInt64 = 0

    // MARK: - Labels
    private(set) var replayWindow = ReplayWindow()

    private static let labelChainA = "MCNEAL-CHAIN-A"
    private static let labelChainB = "MCNEAL-CHAIN-B"
    private static let labelMsg    = "MCNEAL-MSG"
    private static let labelStep   = "MCNEAL-STEP"


    // MARK: - Init

    public init(rootKey: Data, role: McNealRole) throws {
        guard rootKey.count == 32 else {
            throw NSError(
                domain: "McNealRatchet",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "rootKey must be exactly 32 bytes (got \(rootKey.count))"]
            )
        }

        // derive chainA/chainB from rootKey
        let chainA = Self.hmac(key: rootKey, data: Data(Self.labelChainA.utf8))
        let chainB = Self.hmac(key: rootKey, data: Data(Self.labelChainB.utf8))

        switch role {
        case .initiator:
            self.sendChainKey = chainA
            self.recvChainKey = chainB
        case .responder:
            self.sendChainKey = chainB
            self.recvChainKey = chainA
        }
    }
    
    public mutating func zeroize() {
        // Reset counters
        sendSeq = 0
        recvSeq = 0

        // Overwrite chain keys
        sendChainKey = Data(repeating: 0, count: sendChainKey.count)
        recvChainKey = Data(repeating: 0, count: recvChainKey.count)
    }



    // MARK: - Sending

    /// Derive current send message key (32 bytes) for the current sendSeq (or provide a specific seq).
    public mutating func nextSendMessageKey() -> (seq: UInt64, msgKey: Data) {
        let seq = sendSeq
        let key = deriveMessageKey(chainKey: sendChainKey, seq: seq)
        // advance chain + seq
        sendChainKey = step(chainKey: sendChainKey)
        sendSeq &+= 1
        return (seq, key)
    }

    // MARK: - Receiving

    /// Derive expected receive message key for the current recvSeq.
    /// You can later extend this to support out-of-order (skip window).
    public mutating func nextRecvMessageKey() -> (seq: UInt64, msgKey: Data) {
        let seq = recvSeq
        let key = deriveMessageKey(chainKey: recvChainKey, seq: seq)
        // advance chain + seq
        recvChainKey = step(chainKey: recvChainKey)
        recvSeq &+= 1
        return (seq, key)
    }

    // MARK: - Core derivations

    private func deriveMessageKey(chainKey: Data, seq: UInt64) -> Data {
        var material = Data(Self.labelMsg.utf8)
        material.append(Self.u64be(seq))
        // 32-byte msgKey
        return Self.hmac(key: chainKey, data: material)
    }

    private func step(chainKey: Data) -> Data {
        // 32-byte next chain key
        return Self.hmac(key: chainKey, data: Data(Self.labelStep.utf8))
    }

    // MARK: - HMAC helper

    private static func hmac(key: Data, data: Data) -> Data {
        let sk = SymmetricKey(data: key)
        let mac = HMAC<SHA256>.authenticationCode(for: data, using: sk)
        return Data(mac) // 32 bytes
    }

    // MARK: - Encoding helper

    private static func u64be(_ x: UInt64) -> Data {
        var v = x.bigEndian
        return Data(bytes: &v, count: MemoryLayout<UInt64>.size)
    }
}

extension McNealRatchet {

    func snapshot() -> PersistedRatchet {
        PersistedRatchet(
            sendChainKeyB64: sendChainKey.base64EncodedString(),
            recvChainKeyB64: recvChainKey.base64EncodedString(),
            sendSeq: sendSeq,
            recvSeq: recvSeq,
            replayWindow: replayWindow
        )
    }

    static func restore(
        rootKey: Data,
        role: McNealRole,
        snapshot: PersistedRatchet
    ) throws -> McNealRatchet {

        var r = try McNealRatchet(rootKey: rootKey, role: role)
        r.sendChainKey = Data(base64Encoded: snapshot.sendChainKeyB64)!
        r.recvChainKey = Data(base64Encoded: snapshot.recvChainKeyB64)!
        r.sendSeq = snapshot.sendSeq
        r.recvSeq = snapshot.recvSeq
        r.replayWindow = snapshot.replayWindow
        return r
    }
}

public struct PersistedRatchet: Codable {
    let sendChainKeyB64: String
    let recvChainKeyB64: String
    let sendSeq: UInt64
    let recvSeq: UInt64
    let replayWindow: ReplayWindow
}
