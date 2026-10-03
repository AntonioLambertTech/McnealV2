Patent Notice

This project is covered by one or more pending patent applications.
Use of this software is subject to the terms of the Apache 2.0 license.

# McnealV2
McNeal Protocol V2 - Per-Message Ratcheted Cryptographic Alphabet with Frequency-Domain Transformation, Binary Frame Protocol, and Out-of-Order Message Processing

# McNeal Protocol V2 - Reference Implementation

A secure messaging protocol combining X25519 key agreement, ChaCha20-Poly1305 AEAD encryption, double-ratchet forward secrecy, and novel per-message frequency-domain obfuscation.

## Important Notices

- **Reference Implementation Only**: This is a proof-of-concept implementation for academic and research purposes
- **Patents Pending**: Core aspects of this protocol are subject to pending patent applications
- **Not Production-Ready**: This code intentionally omits production features (persistence, reconnection, optimization)
- **No Warranty**: Provided "AS IS" without warranty of any kind

## What is McNeal V2?

McNeal V2 is an end-to-end encrypted messaging protocol that adds a unique obfuscation layer on top of traditional cryptographic primitives:

**Core Innovation**: Each encrypted message generates a unique, deterministic symbol-to-frequency mapping derived from the per-message encryption key. The same plaintext "hello" will produce different frequency patterns in message 1 vs message 100 vs message 1000, making traffic analysis more difficult.

### Key Features

1. **X25519 Key Agreement** - Ephemeral Diffie-Hellman with optional pre-shared key binding
2. **Double Ratchet** - Forward secrecy with independent send/receive chains
3. **ChaCha20-Poly1305 AEAD** - Authenticated encryption with deterministic nonces
4. **Anti-Replay Protection** - Sliding window (256 messages) with out-of-order support
5. **Per-Message Alphabet** - Frequency mappings derived from ratchet state (msgKey)
6. **Fragmentation** - Transparent handling of messages exceeding MTU

## Repository Structure

```
McNealProtocol-Reference/
├── Sources/McNealProtocol/       # Core protocol implementation
│   ├── McNealKeyAgreement.swift  # Phase 1: X25519 DH → root key
│   ├── McNealRole.swift          # Phase 2: Double ratchet
│   ├── McNealAEAD.swift          # Phase 3: ChaCha20-Poly1305
│   ├── ReplayWindow.swift        # Phase 4: Anti-replay
│   ├── McNealSession.swift       # Session state machine
│   ├── McNealFrameType.swift     # Wire protocol frames
│   ├── McNealFragmenter.swift    # Message fragmentation
│   └── McNealAlphabetConfig.swift # Frequency mapping (novel)
├── Tests/                        # Unit tests proving claims
├── Examples/                     # Minimal working examples
├── LICENSE                       # Apache-2.0
├── NOTICE                        # Copyright notice
├── SECURITY.md                   # Security disclosure policy
└── README.md                     # This file
```

## Quick Start

### Requirements

- Swift 5.9+
- macOS 13+ / iOS 16+ (for CryptoKit)
- Xcode 15+ or Swift Package Manager

### Running Tests

```bash
# Clone the repository
git clone https://github.com/AntonioLambertTech/McnealV2.git
cd McNealProtocol-Reference

# Run tests
swift test

# Or with Xcode
open Package.swift
# Then Cmd+U to run tests
```

### Basic Example

```swift
import McNealProtocol

// 1. Key Agreement
let aliceKeys = McNealKeyAgreement.generateEphemeralKeyPair()
let bobKeys = McNealKeyAgreement.generateEphemeralKeyPair()

let aliceRootKey = try McNealKeyAgreement.deriveRootKey(
    localPrivateKey: aliceKeys.privateKey,
    remotePublicKeyRaw: bobKeys.publicKeyRaw,
    initiatorNonce: Data(repeating: 1, count: 32),
    responderNonce: Data(repeating: 2, count: 32)
)

// 2. Initialize Ratchets
var aliceRatchet = try McNealRatchet(rootKey: aliceRootKey, role: .initiator)
let aliceSession = McNealSession(ratchet: aliceRatchet)

// 3. Encrypt & Send
let plaintext = "Hello, Bob!".data(using: .utf8)!
let encrypted = try aliceSession.makeDataFrame(plaintext: plaintext)

// 4. Receive & Decrypt (Bob's side)
let bobRootKey = /* derive same root key */
var bobRatchet = try McNealRatchet(rootKey: bobRootKey, role: .responder)
let bobSession = McNealSession(ratchet: bobRatchet)

let decrypted = try bobSession.openDataFrame(encrypted)
print(String(data: decrypted, encoding: .utf8)!) // "Hello, Bob!"
```

## Protocol Phases

### Phase 1: Key Agreement (X25519)
- Ephemeral key pairs generated per session
- Optional PSK binding for MITM resistance
- Nonce ordering: initiator first, responder second
- Output: 32-byte root key

### Phase 2: Ratchet (Double Ratchet)
- Two independent chain keys (send/receive)
- Per-message keys derived via HMAC-SHA256
- Automatic key advancement on each message
- Separate sequence counters per direction

### Phase 3: AEAD (ChaCha20-Poly1305)
- Deterministic nonce: `SHA256(sid || epoch || seq)`
- AAD includes frame header for integrity
- 16-byte authentication tag appended

### Phase 4: Anti-Replay (Sliding Window)
- 256-message window (configurable)
- Accepts out-of-order within window
- Rejects duplicates and too-old messages
- Key cache for out-of-order decryption

### Novel: Per-Message Frequency Mapping
- Each `msgKey` derives a unique symbol→frequency mapping
- Minimum 15 Hz spacing between symbols
- Same plaintext = different frequencies per message
- Deterministic: both sender/receiver derive identical map from shared `msgKey`

## What's Intentionally Omitted

This reference implementation focuses on **correctness** not **completeness**. The following are deliberately excluded:

### Not Included (by design)
- Firebase/backend integration
- Session persistence (keychain, database)
- Network transport layer
- Automatic reconnection/retry
- SIMD/Accelerate optimizations
- Audio session management
- UI components
- Production error handling
- Stealth/obfuscation beyond frequency mapping
- Rate limiting
- User authentication

### What IS Included (proof)
- Core cryptographic primitives
- Frame encoding/decoding
- Replay protection
- Out-of-order message handling
- Message fragmentation
- Per-message alphabet derivation
- Test vectors for all claims

## Testing Highlights

The test suite proves the following controversial claims:

### Test: Alphabet Changes Per Message
```swift
func testAlphabetChangesPerMessage() {
    let msg1 = try McNealAlphabet(msgKey32: msgKey1, config: config)
    let msg2 = try McNealAlphabet(msgKey32: msgKey2, config: config)
    
    // Same plaintext, different frequencies
    let hz1 = try msg1.hz(forSymbol: "A")
    let hz2 = try msg2.hz(forSymbol: "A")
    XCTAssertNotEqual(hz1, hz2, accuracy: 1.0)
}
```

### Test: Deterministic Mapping
```swift
func testDeterministicMapping() {
    let alice = try McNealAlphabet(msgKey32: sharedKey, config: config)
    let bob = try McNealAlphabet(msgKey32: sharedKey, config: config)
    
    // Same key = identical mapping
    XCTAssertEqual(alice.frequencyMap, bob.frequencyMap)
}
```

### Test: Collision Separation
```swift
func testMinimumFrequencySpacing() {
    let alphabet = try McNealAlphabet(msgKey32: msgKey, config: config)
    
    for i in 0..<alphabet.frequencyMap.count {
        for j in (i+1)..<alphabet.frequencyMap.count {
            let spacing = abs(alphabet.frequencyMap[i] - alphabet.frequencyMap[j])
            XCTAssertGreaterThanOrEqual(spacing, 15.0)
        }
    }
}
```

### Test: Out-of-Order Decryption
```swift
func testOutOfOrderWithKeyCache() {
    // Send messages 0, 1, 2
    // Receive in order: 0, 2, 1 (out of order)
    // All should decrypt correctly
}
```

## Security Considerations

### What This Protocol Provides
- End-to-end encryption (ChaCha20-Poly1305)
- Forward secrecy (ratchet mechanism)
- Replay protection (sliding window)
- Authentication (AEAD tags)
- Integrity (AAD over headers)
- Traffic pattern obfuscation (variable frequency mapping)

### What This Protocol Does NOT Provide
- Identity verification (no PKI)
- Deniability (no Signal-style X3DH)
- Group messaging
- Metadata protection beyond frequency obfuscation
- Protection against quantum computers (uses X25519)
- Formal security proof

### Known Limitations
- No protection against traffic correlation

### Does Not Provide
- Network anonymity (use Tor)
- Timing-channel resistance
- Formal security proof

**This is a reference implementation for research purposes.**
For production use, conduct security audit and add constant-time operations.

## Contributing

This is a reference implementation for patent documentation. Pull requests for the following are welcome:

- Bug fixes in core crypto
- Additional test cases
- Documentation improvements
- Performance benchmarks (without changing algorithm)

Please do NOT submit:
- Additional features
- Production enhancements
- Transport layer integrations
- UI components

## License

Apache License 2.0 - See [LICENSE](LICENSE)

## Security Disclosures

Please report security vulnerabilities via email to [Antonio@oneislandtech.com](mailto:Antonio@oneislandtech.com)

Do NOT open public issues for security problems.

## Citations

If you reference this work in academic publications, please cite:

```bibtex
@misc{mcneal2025,
  title={McNeal Protocol V2: Ratcheted Frequency-Domain Obfuscation for Secure Messaging},
  author={Antonio Lambert},
  year={2025},
  howpublished={GitHub Repository},
  url={https://github.com/AntonioLambertTech/McnealV2}
}
```

## Acknowledgments

- ChaCha20-Poly1305: Daniel J. Bernstein
- X25519: Daniel J. Bernstein
- Double Ratchet: Trevor Perrin, Moxie Marlinspike (Signal Protocol)
- Swift CryptoKit: Apple Inc.

## Disclaimer

This software is provided for educational and research purposes. The authors make no claims about its suitability for production use. Patents pending on novel aspects of the frequency mapping mechanism. Commercial use may require licensing.

---

**Built with ❤️ for the cryptography community**


## License

This repository is licensed under the Apache License 2.0.

This is a reference implementation intended for validation,
experimentation, and peer review.

Certain production details are intentionally omitted and are
covered by a pending patent application.
