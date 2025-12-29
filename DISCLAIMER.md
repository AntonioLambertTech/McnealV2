# Disclaimer

## Reference Implementation Notice

This software is a **reference implementation** created for academic research, patent documentation, and educational purposes. It is **NOT** intended for production use.

## No Warranty

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

## Patent Status

**Patents Pending**: Core aspects of this protocol, including but not limited to:

- Per-message deterministic frequency mapping derived from cryptographic ratchet state
- Symbolic audio encoding with cryptographically-derived frequency assignments
- Methods for traffic pattern obfuscation using variable symbol-to-frequency mappings

Commercial use of the novel aspects of this protocol may require licensing. Academic and research use is permitted under the Apache 2.0 license.

## Security Limitations

This reference implementation:

- **Has NOT been audited** by independent security professionals
- **Does NOT include** formal security proofs
- **Is NOT constant-time** in all operations
- **Does NOT protect against** side-channel attacks
- **May contain** implementation bugs or vulnerabilities

**DO NOT use this code in production systems without:**
1. Comprehensive security audit by qualified professionals
2. Extensive testing in your specific environment
3. Addition of proper error handling and logging
4. Implementation of key rotation and session management
5. Integration with proper authentication system

## Intended Use Cases

### Appropriate Uses
- Academic research and analysis
- Educational purposes and learning
- Protocol design reference
- Proof-of-concept demonstrations
- Benchmarking and performance testing
- Patent documentation

### Inappropriate Uses
- Production messaging applications
- Handling of classified or sensitive information
- Mission-critical communications
- Healthcare or financial systems
- Any system where security failure has serious consequences

## Limitations

This implementation intentionally omits:

1. **Network Layer**: No transport protocol, no reconnection logic
2. **Persistence**: No session storage, no key backup
3. **Authentication**: No identity verification, no PKI
4. **Optimization**: No SIMD, no Accelerate framework usage
5. **Production Features**: No rate limiting, no abuse prevention
6. **User Experience**: No error messages, no progress indicators

These omissions are **by design** to keep the reference implementation focused on protocol correctness rather than completeness.

## No Endorsement

This software does not represent an endorsement of any particular cryptographic approach. The frequency-domain obfuscation technique is experimental and has not been peer-reviewed or formally verified.

## Assumption of Risk

By using this software, you acknowledge that:

1. You understand it is a reference implementation only
2. You will not use it in production without proper security review
3. You accept all risks associated with its use
4. You are responsible for compliance with applicable laws and regulations
5. You understand the security limitations outlined above

## Legal Compliance

Users are responsible for ensuring their use of this software complies with:

- Export control regulations
- Encryption laws in their jurisdiction
- Patent laws and licensing requirements
- Any other applicable legal requirements

The authors make no representations about the legal suitability of this software for any purpose.

## Contribution Guidelines

Contributions are welcome, but please note:

- **Bug fixes**: Welcome and encouraged
- **Test cases**: Highly appreciated
- **Documentation**: Always helpful
- **Production features**: Will not be accepted (out of scope)
- **Performance hacks**: Not accepted (reference implementation prioritizes clarity)

## Version Statement

This disclaimer applies to version 1.0.x of the McNeal Protocol Reference Implementation. Future versions may have different status or scope.

## Questions?

For questions about:
- **Technical issues**: Open a GitHub issue
- **Security concerns**: Email [Antonio@oneislandtech.com]
- **Licensing**: Email [Antonio@oneislandtech.com]
- **Patents**: Consult with your legal counsel

---

**By using this software, you acknowledge that you have read, understood, and agree to this disclaimer.**

Last Updated: December 2025
