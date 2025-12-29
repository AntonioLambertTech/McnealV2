//
//  MinimalExample.swift
//  McNeal Protocol Reference Implementation
//
//  A minimal working example demonstrating the complete McNeal protocol flow.
//

import Foundation
import McNealProtocol

func runMinimalExample() throws {
    print("=== McNeal Protocol V2 - Minimal Example ===\n")
    
    // STEP 1: Key Agreement (X25519)
    print("Key Agreement Phase")
    print("   Generating ephemeral X25519 key pairs...")
    
    let aliceKeys = McNealKeyAgreement.generateEphemeralKeyPair()
    let bobKeys = McNealKeyAgreement.generateEphemeralKeyPair()
    
    // Generate nonces (in real protocol, these would be exchanged)
    let initiatorNonce = Data(repeating: 0xAA, count: 32)
    let responderNonce = Data(repeating: 0xBB, count: 32)
    
    print("   Deriving root keys...")
    
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
    
    assert(aliceRootKey == bobRootKey, "Root keys must match!")
    print("   Root keys match: \(aliceRootKey.prefix(8).hexString)...\n")
    
    // STEP 2: Initialize Ratchets
    print("Ratchet Initialization")
    print("   Alice (initiator) and Bob (responder)...")
    
    var aliceRatchet = try McNealRatchet(rootKey: aliceRootKey, role: .initiator)
    var bobRatchet = try McNealRatchet(rootKey: bobRootKey, role: .responder)
    
    let aliceSession = McNealSession(ratchet: aliceRatchet)
    let bobSession = McNealSession(ratchet: bobRatchet)
    
    print("   Sessions initialized\n")
    
    // STEP 3: Send Messages
    print("Message Exchange")
    
    let messages = [
        "Hello, Bob!",
        "This is Alice.",
        "McNeal protocol works!"
    ]
    
    for (i, msg) in messages.enumerated() {
        print("   Message \(i+1): \"\(msg)\"")
        
        // Alice encrypts
        let plaintext = msg.data(using: .utf8)!
        let encrypted = try aliceSession.makeDataFrame(plaintext: plaintext)
        print("      Encrypted: \(encrypted.count) bytes")
        
        // Bob decrypts
        let decrypted = try bobSession.openDataFrame(encrypted)
        let decryptedText = String(data: decrypted, encoding: .utf8)!
        print("      Decrypted: \"\(decryptedText)\"")
        
        assert(msg == decryptedText, "Decryption failed!")
        print("      Message verified\n")
    }
    
    // STEP 4: Demonstrate Per-Message Alphabet
    print("Per-Message Alphabet (Novel Feature)")
    print("   Same plaintext produces DIFFERENT frequency patterns...\n")
    
    let config = McNealAlphabetConfig()
    let testWord = "hello"
    
    // Get message keys from ratchet state
    let (_, msgKey1) = aliceSession.ratchet.nextSendMessageKey()
    let (_, msgKey2) = aliceSession.ratchet.nextSendMessageKey()
    
    let alphabet1 = try McNealAlphabet(msgKey32: msgKey1, config: config)
    let alphabet2 = try McNealAlphabet(msgKey32: msgKey2, config: config)
    
    print("   Plaintext: \"\(testWord)\"")
    print("")
    print("   Message 1 frequencies (Hz):")
    let freq1 = try alphabet1.encodeToHz(testWord)
    for (i, hz) in freq1.enumerated() {
        print("      \(testWord[testWord.index(testWord.startIndex, offsetBy: i)]): \(String(format: "%.1f", hz)) Hz")
    }
    
    print("")
    print("   Message 2 frequencies (Hz):")
    let freq2 = try alphabet2.encodeToHz(testWord)
    for (i, hz) in freq2.enumerated() {
        print("      \(testWord[testWord.index(testWord.startIndex, offsetBy: i)]): \(String(format: "%.1f", hz)) Hz")
    }
    
    print("")
    print("   Same plaintext, different frequency patterns!\n")
    
    // STEP 5: Demonstrate Anti-Replay
    print("Anti-Replay Protection")
    
    let msg = "Test message".data(using: .utf8)!
    let frame = try aliceSession.makeDataFrame(plaintext: msg)
    
    // First receive: should work
    _ = try bobSession.openDataFrame(frame)
    print("   First receive: Accepted")
    
    // Second receive (duplicate): should fail
    do {
        _ = try bobSession.openDataFrame(frame)
        print("   Second receive: Should have failed!")
    } catch {
        print("   Second receive: Rejected (duplicate)")
    }
    
    print("\n=== Example Complete ===")
}

// MARK: - Helper Extensions

extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

// Run the example
do {
    try runMinimalExample()
} catch {
    print("Error: \(error)")
}
