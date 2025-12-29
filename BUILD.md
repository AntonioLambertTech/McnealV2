# Build & Test Instructions

## Prerequisites

- macOS 13.0+ or iOS 16.0+
- Xcode 15.0+ or Swift 5.9+
- Swift Package Manager (included with Swift)

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/AntonioLambertTech/McnealV2.git
cd McNealProtocol-Reference
```

### 2. Run Security Scan

Before making any changes, verify the repository is clean:

```bash
./security-scan.sh
```

### 3. Build the Project

Using Swift Package Manager:

```bash
swift build
```

Using Xcode:

```bash
open Package.swift
# Wait for dependencies to resolve
# Press Cmd+B to build
```

### 4. Run Tests

Using Swift Package Manager:

```bash
swift test
```

Using Xcode:

```bash
open Package.swift
# Press Cmd+U to run all tests
```

### 5. Run Example

The minimal example demonstrates the complete protocol flow:

```bash
swift run MinimalExample
```

Or in Xcode:
1. Open `Package.swift`
2. Select the `MinimalExample` scheme
3. Press Cmd+R to run

## Expected Test Results

All tests should pass. The test suite covers:

- X25519 key agreement
- PSK binding
- Ratchet determinism
- ChaCha20-Poly1305 AEAD
- Anti-replay protection
- Out-of-order message handling
- Message fragmentation
- Per-message alphabet generation (novel feature)
- Frequency mapping uniqueness
- Minimum frequency spacing
- Round-trip encoding/decoding

## Key Tests to Review

### 1. Alphabet Changes Per Message
```swift
func testAlphabetChangesPerMessage()
```
**Proves**: Same plaintext produces different frequency patterns across messages.

### 2. Deterministic Mapping  
```swift
func testAlphabetDeterminism()
```
**Proves**: Same msgKey produces identical frequency mapping on both sides.

### 3. Minimum Spacing
```swift
func testAlphabetMinimumSpacing()
```
**Proves**: All symbols maintain ≥15 Hz separation for reliable detection.

### 4. Out-of-Order Decryption
```swift
func testMultipleMessages()
```
**Proves**: Messages can arrive out of order and still decrypt correctly.

## Troubleshooting

### Build Fails with "CryptoKit not found"

**Solution**: Ensure you're running on macOS 13+ or iOS 16+. CryptoKit is a system framework.

### Tests Timeout

**Solution**: Frequency mapping generation is computationally intensive. This is expected for reference implementation. Production would use pre-computed tables.

### "Symbol too large for frequency range" Error

**Solution**: This is a configuration issue. Adjust `maxHz` in `McNealAlphabetConfig` or reduce symbol count.

## Performance Notes

This is a **reference implementation** optimized for clarity, not speed:

- Key derivation: ~1-5ms
- Message encryption: ~0.5-2ms  
- Message decryption: ~0.5-2ms
- Alphabet generation: ~10-50ms (per message key)

Production implementations should:
- Cache alphabet instances
- Use lookup tables for frequency mapping
- Implement SIMD operations for audio processing

## Continuous Integration

To set up CI (GitHub Actions):

```yaml
name: Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - name: Run Tests
        run: swift test
```

## Code Coverage

To generate code coverage reports:

```bash
swift test --enable-code-coverage
xcrun llvm-cov show .build/debug/McNealProtocolPackageTests.xctest/Contents/MacOS/McNealProtocolPackageTests \
  -instr-profile=.build/debug/codecov/default.profdata \
  -format=html -output-dir=coverage
open coverage/index.html
```

## Benchmarking

To benchmark performance:

```bash
swift test --filter "Performance" --enable-code-coverage
```

(Performance tests are not included in reference implementation - add as needed)

## Static Analysis

Run SwiftLint (if installed):

```bash
swiftlint lint --strict
```

## Before Pushing to GitHub

Always run the security scan:

```bash
./security-scan.sh
```

This checks for:
- API keys
- Firebase configs
- Debug prints
- Hardcoded credentials
- Personal information
- Required documentation

## Getting Help

- **Technical Issues**: Open a GitHub issue
- **Security Concerns**: Email Antonio@oneislandtech.com
- **Build Problems**: Check Swift version (`swift --version`)

## Contributing

See `README.md` for contribution guidelines. TL;DR:

- Bug fixes welcome
- Test improvements welcome  
- Documentation welcome
- Production features not accepted (out of scope)
- Performance optimizations not accepted (reference impl)
