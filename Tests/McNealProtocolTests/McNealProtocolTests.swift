//
//  McNealProtocolTests.swift
//  McNealProtocol Reference Implementation Tests
//
//  Copyright (c) 2025. Licensed under Apache-2.0.
//

import XCTest
@testable import McNealProtocol
import CryptoKit

final class McNealProtocolTests: XCTestCase {
    
    // MARK: - Phase 1: Key Agreement Tests
    
    func testX25519KeyAgreement() throws {
        // Generate ephemeral keys
        let aliceKeys = McNealKeyAgreement.generateEphemeralKeyPair()
        let bobKeys = McNealKeyAgreement.generateEphemeralKeyPair()
        
        // Create nonces (32 bytes each)
        let initiatorNonce = Data(count: 32)
        let responderNonce = Data(repeating: 1, count: 32)
        
        // Both sides derive same root key
        let aliceRootKey = try McNealKeyAgreement.deriveRootKey(
            localPrivateKey: aliceKeys.privateKey,
            remotePublicKeyRaw: bobKeys.publicKeyRaw,
            initiatorNonce: initiatorNonce,
            responderNonce: responderNonce
        )
        
        let bobRootKey = try McNealKeyAgreement.deriveRootKey(
            localPrivateKey: bobKeys.privateKey,
            remotePublicKeyRaw: aliceKeys.publicKeyRaw,
            initiatorNonce: initiatorNonce,
            responderNonce: responderNonce
        )
        
        // Verify both sides derive identical root key
        XCTAssertEqual(aliceRootKey, bobRootKey)
        XCTAssertEqual(aliceRootKey.count, 32)
    }
    
    func testPSKBinding() throws {
        let aliceKeys = McNealKeyAgreement.generateEphemeralKeyPair()
        let bobKeys = McNealKeyAgreement.generateEphemeralKeyPair()
        
        let initiatorNonce = Data(count: 32)
        let responderNonce = Data(repeating: 1, count: 32)
        let psk = Data(repeating: 42, count: 32)
        
        // Derive with PSK
        let withPSK = try McNealKeyAgreement.deriveRootKey(
            localPrivateKey: aliceKeys.privateKey,
            remotePublicKeyRaw: bobKeys.publicKeyRaw,
            initiatorNonce: initiatorNonce,
            responderNonce: responderNonce,
            psk: psk
        )
        
        // Derive without PSK
        let withoutPSK = try McNealKeyAgreement.deriveRootKey(
            localPrivateKey: aliceKeys.privateKey,
            remotePublicKeyRaw: bobKeys.publicKeyRaw,
            initiatorNonce: initiatorNonce,
            responderNonce: responderNonce
        )
        
        // Root keys must be different when PSK is used
        XCTAssertNotEqual(withPSK, withoutPSK)
    }
    
    // MARK: - Phase 2: Ratchet Tests
    
    func testRatchetDeterminism() throws {
        let rootKey = Data(repeating: 1, count: 32)
        
        var ratchet1 = try McNealRatchet(rootKey: rootKey, role: .initiator)
        var ratchet2 = try McNealRatchet(rootKey: rootKey, role: .initiator)
        
        let (seq1, key1) = ratchet1.nextSendMessageKey()
        let (seq2, key2) = ratchet2.nextSendMessageKey()
        
        XCTAssertEqual(seq1, seq2)
        XCTAssertEqual(key1, key2)
        XCTAssertEqual(key1.count, 32)
    }
    
    func testRatchetRoles() throws {
        let rootKey = Data(repeating: 1, count: 32)
        
        var initiator = try McNealRatchet(rootKey: rootKey, role: .initiator)
        var responder = try McNealRatchet(rootKey: rootKey, role: .responder)
        
        let (_, initSendKey) = initiator.nextSendMessageKey()
        let (_, respRecvKey) = responder.nextRecvMessageKey()
        
        // Initiator's send key should match responder's receive key
        XCTAssertEqual(initSendKey, respRecvKey)
    }
    
    func testRatchetAdvancement() throws {
        let rootKey = Data(repeating: 1, count: 32)
        var ratchet = try McNealRatchet(rootKey: rootKey, role: .initiator)
        
        var keys: [Data] = []
        for _ in 0..<10 {
            let (_, key) = ratchet.nextSendMessageKey()
            keys.append(key)
        }
        
        // All keys should be unique
        let uniqueKeys = Set(keys)
        XCTAssertEqual(uniqueKeys.count, keys.count)
    }
    
    // MARK: - Phase 3: AEAD Tests
    
    func testChaChaPolyEncryptDecrypt() throws {
        let sid = UUID()
        let epoch: UInt32 = 1
        let seq: UInt64 = 0
        let msgKey = Data(repeating: 1, count: 32)
        
        let plaintext = "Hello, World!".data(using: .utf8)!
        let aad = Data("additional-data".utf8)
        
        let nonce = try McNealAEAD.nonce(sid: sid, epoch: epoch, seq: seq)
        
        let sealed = try McNealAEAD.seal(
            plaintext: plaintext,
            msgKey32: msgKey,
            nonce: nonce,
            aad: aad
        )
        
        let decrypted = try McNealAEAD.open(
            ciphertext: sealed.ciphertext,
            tag: sealed.tag,
            msgKey32: msgKey,
            nonce: nonce,
            aad: aad
        )
        
        XCTAssertEqual(plaintext, decrypted)
        XCTAssertEqual(sealed.tag.count, 16)
    }
    
    func testNonceDeterminism() throws {
        let sid = UUID()
        let epoch: UInt32 = 1
        let seq: UInt64 = 42
        
        let nonce1 = try McNealAEAD.nonce(sid: sid, epoch: epoch, seq: seq)
        let nonce2 = try McNealAEAD.nonce(sid: sid, epoch: epoch, seq: seq)
        
        // Same inputs = same nonce (deterministic)
        XCTAssertEqual(nonce1, nonce2)
        
        // Different seq = different nonce
        let nonce3 = try McNealAEAD.nonce(sid: sid, epoch: epoch, seq: seq + 1)
        XCTAssertNotEqual(nonce1, nonce3)
    }
    
    // MARK: - Phase 4: Replay Window Tests
    
    func testReplayWindowAcceptsNew() throws {
        var window = ReplayWindow(windowSize: 256)
        
        XCTAssertEqual(window.observe(0), .acceptNew)
        XCTAssertEqual(window.observe(1), .acceptNew)
        XCTAssertEqual(window.observe(2), .acceptNew)
    }
    
    func testReplayWindowRejectsDuplicate() throws {
        var window = ReplayWindow(windowSize: 256)
        
        XCTAssertEqual(window.observe(0), .acceptNew)
        XCTAssertEqual(window.observe(0), .rejectDuplicate)
    }
    
    func testReplayWindowOutOfOrder() throws {
        var window = ReplayWindow(windowSize: 256)
        
        XCTAssertEqual(window.observe(0), .acceptNew)
        XCTAssertEqual(window.observe(2), .acceptNew)
        XCTAssertEqual(window.observe(1), .acceptOutOfOrder)
    }
    
    func testReplayWindowTooOld() throws {
        var window = ReplayWindow(windowSize: 10)
        
        XCTAssertEqual(window.observe(100), .acceptNew)
        XCTAssertEqual(window.observe(89), .rejectTooOld) // 100 - 10 = 90, so 89 is too old
    }
    
    // MARK: - Integration Tests
    
    func testEndToEndEncryption() throws {
        // Setup Alice
        let aliceKeys = McNealKeyAgreement.generateEphemeralKeyPair()
        let bobKeys = McNealKeyAgreement.generateEphemeralKeyPair()
        
        let initiatorNonce = Data(repeating: 0, count: 32)
        let responderNonce = Data(repeating: 1, count: 32)
        
        let aliceRootKey = try McNealKeyAgreement.deriveRootKey(
            localPrivateKey: aliceKeys.privateKey,
            remotePublicKeyRaw: bobKeys.publicKeyRaw,
            initiatorNonce: initiatorNonce,
            responderNonce: responderNonce
        )
        
        let bobRootKey = try McNealKeyAgreement.deriveRootKey(
            localPrivateKey: bobKeys.privateKey,
            remotePublicKeyRaw: aliceKeys.publicKeyRaw,
            initiatorNonce: initiatorNonce,
            responderNonce: responderNonce
        )
        
        var aliceRatchet = try McNealRatchet(rootKey: aliceRootKey, role: .initiator)
        var bobRatchet = try McNealRatchet(rootKey: bobRootKey, role: .responder)
        
        let aliceSession = McNealSession(ratchet: aliceRatchet)
        let bobSession = McNealSession(ratchet: bobRatchet)
        
        // Alice sends message
        let plaintext = "Hello Bob!".data(using: .utf8)!
        let encrypted = try aliceSession.makeDataFrame(plaintext: plaintext)
        
        // Bob receives and decrypts
        let decrypted = try bobSession.openDataFrame(encrypted)
        
        XCTAssertEqual(plaintext, decrypted)
    }
    
    func testMultipleMessages() throws {
        let aliceKeys = McNealKeyAgreement.generateEphemeralKeyPair()
        let bobKeys = McNealKeyAgreement.generateEphemeralKeyPair()
        
        let initiatorNonce = Data(repeating: 0, count: 32)
        let responderNonce = Data(repeating: 1, count: 32)
        
        let aliceRootKey = try McNealKeyAgreement.deriveRootKey(
            localPrivateKey: aliceKeys.privateKey,
            remotePublicKeyRaw: bobKeys.publicKeyRaw,
            initiatorNonce: initiatorNonce,
            responderNonce: responderNonce
        )
        
        let bobRootKey = try McNealKeyAgreement.deriveRootKey(
            localPrivateKey: bobKeys.privateKey,
            remotePublicKeyRaw: aliceKeys.publicKeyRaw,
            initiatorNonce: initiatorNonce,
            responderNonce: responderNonce
        )
        
        var aliceRatchet = try McNealRatchet(rootKey: aliceRootKey, role: .initiator)
        var bobRatchet = try McNealRatchet(rootKey: bobRootKey, role: .responder)
        
        let aliceSession = McNealSession(ratchet: aliceRatchet)
        let bobSession = McNealSession(ratchet: bobRatchet)
        
        let messages = ["First", "Second", "Third"]
        
        for msg in messages {
            let plaintext = msg.data(using: .utf8)!
            let encrypted = try aliceSession.makeDataFrame(plaintext: plaintext)
            let decrypted = try bobSession.openDataFrame(encrypted)
            
            XCTAssertEqual(plaintext, decrypted)
        }
    }
    
    // MARK: - Fragmentation Tests
    
    func testFragmentation() throws {
        let largeData = Data(repeating: 42, count: 10000)
        
        let fragments = McNealFragmenter.fragment(largeData, maxChunkSize: 1024)
        
        XCTAssertGreaterThan(fragments.count, 1)
        
        // Verify all fragments share same messageId
        let firstId = fragments[0].header.messageId
        for fragment in fragments {
            XCTAssertEqual(fragment.header.messageId, firstId)
        }
        
        // Verify indices are sequential
        for (i, fragment) in fragments.enumerated() {
            XCTAssertEqual(fragment.header.index, UInt32(i))
        }
    }
    
    func testFragmentReassembly() throws {
        let original = Data(repeating: 42, count: 5000)
        
        let fragments = McNealFragmenter.fragment(original, maxChunkSize: 1024)
        
        var reassembler = McNealFragmenter.Reassembler()
        
        var reassembled: Data?
        for fragment in fragments {
            let packed = try McNealFragmenter.pack(header: fragment.header, payload: fragment.payload)
            let (header, payload) = try McNealFragmenter.unpack(packed)
            reassembled = reassembler.insert(header: header, payload: payload)
        }
        
        XCTAssertNotNil(reassembled)
        XCTAssertEqual(reassembled, original)
    }
    
    // MARK: - Alphabet Tests (Core Novel Claims)
    
    func testAlphabetChangesPerMessage() throws {
        let config = McNealAlphabetConfig()
        
        // Two different message keys
        let msgKey1 = Data(repeating: 1, count: 32)
        let msgKey2 = Data(repeating: 2, count: 32)
        
        let alphabet1 = try McNealAlphabet(msgKey32: msgKey1, config: config)
        let alphabet2 = try McNealAlphabet(msgKey32: msgKey2, config: config)
        
        // Same symbol should map to DIFFERENT frequencies
        let freqA1 = try alphabet1.hz(forSymbol: "A")
        let freqA2 = try alphabet2.hz(forSymbol: "A")
        
        XCTAssertNotEqual(freqA1, freqA2, accuracy: 1.0)
        
        // Verify multiple symbols are different
        for symbol in ["h", "e", "l", "o"] {
            let freq1 = try alphabet1.hz(forSymbol: symbol)
            let freq2 = try alphabet2.hz(forSymbol: symbol)
            XCTAssertNotEqual(freq1, freq2, accuracy: 1.0)
        }
    }
    
    func testAlphabetDeterminism() throws {
        let config = McNealAlphabetConfig()
        let msgKey = Data(repeating: 42, count: 32)
        
        // Create two alphabets with same key
        let alphabet1 = try McNealAlphabet(msgKey32: msgKey, config: config)
        let alphabet2 = try McNealAlphabet(msgKey32: msgKey, config: config)
        
        // They should produce identical frequency mappings
        XCTAssertEqual(alphabet1.frequencyMap, alphabet2.frequencyMap)
        
        // Verify specific symbols map to same frequencies
        for symbol in alphabet1.shuffledSymbols {
            let freq1 = try alphabet1.hz(forSymbol: symbol)
            let freq2 = try alphabet2.hz(forSymbol: symbol)
            XCTAssertEqual(freq1, freq2, accuracy: 0.001)
        }
    }
    
    func testAlphabetMinimumSpacing() throws {
        let config = McNealAlphabetConfig()
        let msgKey = Data(repeating: 1, count: 32)
        
        let alphabet = try McNealAlphabet(msgKey32: msgKey, config: config)
        
        // Check all pairs have minimum 15 Hz spacing
        let minSpacing: Double = 15.0
        
        for i in 0..<alphabet.frequencyMap.count {
            for j in (i+1)..<alphabet.frequencyMap.count {
                let spacing = abs(alphabet.frequencyMap[i] - alphabet.frequencyMap[j])
                XCTAssertGreaterThanOrEqual(spacing, minSpacing,
                    "Frequencies \(i) and \(j) are too close: \(spacing) Hz < \(minSpacing) Hz")
            }
        }
    }
    
    func testAlphabetRoundTrip() throws {
        let config = McNealAlphabetConfig()
        let msgKey = Data(repeating: 1, count: 32)
        
        let alphabet = try McNealAlphabet(msgKey32: msgKey, config: config)
        
        let testText = "Hello, World! 123"
        
        // Encode to Hz
        let hzValues = try alphabet.encodeToHz(testText)
        
        // Decode back
        let decoded = try alphabet.decodeFromHz(hzValues)
        
        XCTAssertEqual(testText, decoded)
    }
    
    func testSamePlaintextDifferentCiphertext() throws {
        let config = McNealAlphabetConfig()
        
        let msgKey1 = Data(repeating: 1, count: 32)
        let msgKey2 = Data(repeating: 2, count: 32)
        
        let alphabet1 = try McNealAlphabet(msgKey32: msgKey1, config: config)
        let alphabet2 = try McNealAlphabet(msgKey32: msgKey2, config: config)
        
        let plaintext = "the"
        
        let hz1 = try alphabet1.encodeToHz(plaintext)
        let hz2 = try alphabet2.encodeToHz(plaintext)
        
        // Same plaintext produces different frequency sequences
        XCTAssertNotEqual(hz1, hz2)
    }
}
