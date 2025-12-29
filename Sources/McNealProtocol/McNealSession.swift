//
//  McNealSession.swift
//  McNealProtocol Reference Implementation
//
//  Copyright (c) 2025. Licensed under Apache-2.0.
//

import Foundation

public struct PersistedMcNealSession: Codable {
    public let threadId: String
    public let sid: String
    public let myUid: String
    public let peerUid: String
    public let role: String
    
    public let epoch: Int
    public let rootKeyB64: String
    
    public let ratchet: PersistedRatchet
    public let recvWindow: ReplayWindow
}

public final class McNealSession {
    
    public let sid: UUID
    public private(set) var epoch: UInt32 = 1
    
    internal var ratchet: McNealRatchet
    
    // Phase 4 state
    internal var recvWindow = ReplayWindow(windowSize: 256)
    private var recvKeyCache: [UInt64: Data] = [:]     // seq -> msgKey32
    private let recvKeyCacheLimit = 512
    
    // Reliable mode state
    private var sendBuffer: [UInt64: Data] = [:]   // seq -> encoded frame bytes
    private var sendBufferLimit: Int = 256
    
    private var highestContigRecv: UInt64 = 0      // receiver side
    private var recvSeen: Set<UInt64> = []         // small set for contig calculation
    private var ackEveryN: UInt64 = 8
    public var onIncomingData: ((Data) -> Void)?
    public var onOutgoingControlFrame: ((Data) -> Void)?
    
    public init(
        sid: UUID = UUID(),
        ratchet: McNealRatchet,
        epoch: UInt32 = 1
    ) {
        self.sid = sid
        self.ratchet = ratchet
        self.epoch = epoch
    }
    
    // MARK: - Send
    
    /// Create an encrypted DATA frame from plaintext.
    /// We pack ciphertext||tag into McNealFrame.ciphertext (tag is last 16 bytes).
    public func makeDataFrame(plaintext: Data, flags: UInt8 = 0) throws -> Data {
        let (seq, msgKey) = ratchet.nextSendMessageKey()
        
        let header = McNealFrameHeader(frameType: .data, flags: flags, seq: seq, sessionId: sid)
        
        // AAD = the on-wire header bytes (everything before cipherLen/ciphertext)
        let aad = McNealSession.headerAAD(from: header)
        
        let nonce = try McNealAEAD.nonce(sid: sid, epoch: epoch, seq: seq)
        
        let sealed = try McNealAEAD.seal(
            plaintext: plaintext,
            msgKey32: msgKey,
            nonce: nonce,
            aad: aad
        )
        
        // Store ciphertext + tag together
        var packed = Data()
        packed.reserveCapacity(sealed.ciphertext.count + sealed.tag.count)
        packed.append(sealed.ciphertext)
        packed.append(sealed.tag)
        
        let frame = McNealFrame(header: header, ciphertext: packed)
        let frameData = frame.encode()
        
        // Store for resend until ACKed
        sendBuffer[seq] = frameData
        if sendBuffer.count > sendBufferLimit {
            // Drop oldest seqs
            for k in sendBuffer.keys.sorted().prefix(sendBuffer.count - sendBufferLimit) {
                sendBuffer.removeValue(forKey: k)
            }
        }
        
        return frameData
    }
    
    // MARK: - Receive (Phase 4)
    
    public func makeAckFrame(highestReceived: UInt64, flags: UInt8 = 0) -> Data {
        // ACK payload = UInt64 BE
        var payload = Data()
        var v = highestReceived.bigEndian
        payload.append(Data(bytes: &v, count: 8))
        
        let header = McNealFrameHeader(frameType: .ack, flags: flags, seq: 0, sessionId: sid)
        return McNealFrame(header: header, ciphertext: payload).encode()
    }
    
    /// Decrypt an incoming DATA frame bytes into plaintext (Phase 4: replay + out-of-order).
    public func openDataFrame(_ frameBytes: Data) throws -> Data {
        let frame = try McNealFrame.decode(frameBytes)
        
        // Basic checks
        guard frame.header.frameType == .data else {
            throw NSError(domain: "McNealSession", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Not a DATA frame"])
        }
        guard frame.header.sessionId == self.sid else {
            throw NSError(domain: "McNealSession", code: 100,
                          userInfo: [NSLocalizedDescriptionKey: "SessionId mismatch"])
        }
        
        // Anti-replay gate
        switch recvWindow.observe(frame.header.seq) {
        case .rejectDuplicate:
            throw NSError(domain: "McNealSession", code: 200,
                          userInfo: [NSLocalizedDescriptionKey: "Replay/duplicate seq \(frame.header.seq)"])
        case .rejectTooOld:
            throw NSError(domain: "McNealSession", code: 201,
                          userInfo: [NSLocalizedDescriptionKey: "Seq too old \(frame.header.seq)"])
        case .acceptNew, .acceptOutOfOrder:
            break
        }
        
        // Split packed ciphertext||tag
        guard frame.ciphertext.count >= 16 else {
            throw NSError(domain: "McNealSession", code: 210,
                          userInfo: [NSLocalizedDescriptionKey: "Ciphertext too small (missing tag)"])
        }
        let tag = frame.ciphertext.suffix(16)
        let ciphertext = frame.ciphertext.prefix(frame.ciphertext.count - 16)
        
        // Get the receive msgKey for THIS seq (supports out-of-order)
        let msgKey = try recvMsgKey(forSeq: frame.header.seq)
        
        // Decrypt
        let nonce = try McNealAEAD.nonce(sid: sid, epoch: epoch, seq: frame.header.seq)
        let aad = McNealSession.headerAAD(from: frame.header)
        
        let plaintext = try McNealAEAD.open(
            ciphertext: Data(ciphertext),
            tag: Data(tag),
            msgKey32: msgKey,
            nonce: nonce,
            aad: aad
        )
        
        // Mark this seq as received
        noteReceivedSeq(frame.header.seq)
        
        return plaintext
    }
    
    private func noteReceivedSeq(_ seq: UInt64) {
        recvSeen.insert(seq)
        
        while recvSeen.contains(highestContigRecv + 1) {
            highestContigRecv += 1
            recvSeen.remove(highestContigRecv)
        }
    }
    
    // MARK: - Key resolution (OOO support)
    
    /// Resolve receive msgKey for an arbitrary seq within the replay window.
    /// - If seq is in the cache: use it.
    /// - If seq >= current recvSeq: advance ratchet, caching skipped keys.
    /// - If seq < current recvSeq and not cached: too late (key discarded/evicted).
    private func recvMsgKey(forSeq seq: UInt64) throws -> Data {
        
        // Out-of-order hit
        if let k = recvKeyCache.removeValue(forKey: seq) {
            return k
        }
        
        // If packet is older than ratchet position and not cached -> cannot decrypt
        if seq < ratchet.recvSeq {
            throw NSError(domain: "McNealSession", code: 300,
                          userInfo: [NSLocalizedDescriptionKey:
                            "Missing recv key for old seq \(seq) (ratchet at \(ratchet.recvSeq))"])
        }
        
        // Bound how far we will step forward in one go (avoid runaway)
        let maxStep = UInt64(recvWindow.windowSize + 8)
        if seq > ratchet.recvSeq + maxStep {
            throw NSError(domain: "McNealSession", code: 301,
                          userInfo: [NSLocalizedDescriptionKey:
                            "Seq \(seq) too far ahead of recvSeq \(ratchet.recvSeq)"])
        }
        
        // Step forward until we reach seq, caching intermediates
        while ratchet.recvSeq <= seq {
            let (expectedSeq, key) = ratchet.nextRecvMessageKey()
            if expectedSeq == seq {
                return key
            } else {
                cacheRecvKey(key, forSeq: expectedSeq)
            }
        }
        
        // Shouldn't happen
        throw NSError(domain: "McNealSession", code: 399,
                      userInfo: [NSLocalizedDescriptionKey: "Recv key resolution failed"])
    }
    
    private func cacheRecvKey(_ key: Data, forSeq seq: UInt64) {
        recvKeyCache[seq] = key
        
        // Bound cache size (drop lowest seqs first)
        if recvKeyCache.count > recvKeyCacheLimit {
            let overflow = recvKeyCache.count - recvKeyCacheLimit
            if overflow > 0 {
                for k in recvKeyCache.keys.sorted().prefix(overflow) {
                    recvKeyCache.removeValue(forKey: k)
                }
            }
        }
    }
    
    // MARK: - AAD helper (matches McNealFrame.encode header bytes)
    
    private static func headerAAD(from h: McNealFrameHeader) -> Data {
        // Must match McNealFrame.encode() header layout exactly:
        // magic u32, version u8, type u8, flags u8, reserved u8, seq u64, sessionId 16
        var out = Data()
        out.reserveCapacity(4 + 1 + 1 + 1 + 1 + 8 + 16)
        
        out.appendU32BE(McNealFrameHeader.magic)
        out.appendU8(McNealFrameHeader.version)
        out.appendU8(h.frameType.rawValue)
        out.appendU8(h.flags)
        out.appendU8(0) // reserved
        
        out.appendU64BE(h.seq)
        out.appendUUID(h.sessionId)
        return out
    }
    
    public enum McNealReceiveEvent {
        case data(Data)
        case ack(UInt64)
        case ping
        case pong
        case closed
    }
    
    public func receiveFrame(_ frameBytes: Data) throws -> McNealReceiveEvent {
        let frame = try McNealFrame.decode(frameBytes)
        
        guard frame.header.sessionId == sid else {
            throw NSError(domain: "McNealSession", code: 900,
                          userInfo: [NSLocalizedDescriptionKey: "Session mismatch"])
        }
        
        switch frame.header.frameType {
            
        case .data:
            let plaintext = try openDataFrame(frameBytes)
            
            onIncomingData?(plaintext)
            
            // Emit ACK every N packets
            if highestContigRecv > 0 && highestContigRecv % ackEveryN == 0 {
                let ack = makeAckFrame(highestReceived: highestContigRecv)
                onOutgoingControlFrame?(ack)
            }
            
            return .data(plaintext)
            
        case .ack:
            let highest = frame.ciphertext.withUnsafeBytes {
                $0.load(as: UInt64.self).bigEndian
            }
            return .ack(highest)
            
        case .ping:
            return .ping
            
        case .pong:
            return .pong
            
        case .close:
            zeroize()
            return .closed
        }
    }
    
    private func zeroize() {
        recvKeyCache.removeAll()
        ratchet.zeroize()
        recvWindow.reset()
    }
}

// MARK: - Local Data helpers

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
