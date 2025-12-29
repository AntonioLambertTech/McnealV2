# Security Policy

## Supported Versions

This is a reference implementation for research and patent documentation purposes. Security updates will be provided on a best-effort basis.

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |

## Reporting a Vulnerability

**Please do NOT report security vulnerabilities through public GitHub issues.**

Instead, please report them via email to: **Antonio@oneislandtech.com**

Include the following information:

1. **Type of issue** (e.g., buffer overflow, cryptographic weakness, timing attack)
2. **Full paths of affected files**
3. **Location of the affected source code** (tag/branch/commit or direct URL)
4. **Step-by-step instructions to reproduce** the issue
5. **Proof-of-concept or exploit code** (if possible)
6. **Impact** of the issue, including how an attacker might exploit it

### Response Timeline

- **Initial Response**: Within 48 hours
- **Preliminary Assessment**: Within 1 week
- **Fix Timeline**: Depends on severity
  - Critical: Within 30 days
  - High: Within 60 days
  - Medium: Within 90 days
  - Low: Best effort

### What to Expect

1. Acknowledgment of your report within 48 hours
2. Regular updates on our progress (at minimum, weekly)
3. Credit in release notes (if desired)
4. Notification when the issue is fixed

## Security Considerations

This reference implementation is NOT intended for production use. Known limitations include:

### Cryptographic Scope
- **Implemented**: X25519, ChaCha20-Poly1305, HMAC-SHA256, Double Ratchet
- **Not Implemented**: Key rotation, session rekeying, identity verification, deniability

### Attack Resistance
- **Protected Against**: Replay attacks, packet reordering, MITM (with PSK)
- **Partially Protected**: Traffic analysis (frequency obfuscation is probabilistic)
- **Not Protected Against**: Quantum computers, timing attacks, side-channels, traffic correlation

### Known Weaknesses
1. **No Formal Proof**: Protocol has not undergone formal security verification
2. **Implementation Limitations**: No constant-time guarantees, potential side-channels in Swift runtime

### Out of Scope
The following are explicitly NOT addressed by this implementation:
- Network-layer attacks (DDoS, connection hijacking)
- Endpoint compromise (malware, keyloggers)
- Social engineering
- Physical security
- Metadata protection beyond frequency obfuscation

## Best Practices

If you choose to build upon this reference implementation:

1. **Do NOT use in production** without extensive security review
2. **Add authentication layer** (identity verification)
3. **Implement key rotation** for long-lived sessions
4. **Use TLS** for transport layer security
5. **Add rate limiting** to prevent abuse
6. **Implement session timeout**
7. **Use secure random number generation** for all nonces
8. **Clear sensitive data** from memory after use
9. **Implement proper error handling** (avoid information leakage)
10. **Conduct security audit** before deployment

## Acknowledgments

We appreciate responsible disclosure from security researchers. Contributors will be acknowledged in:
- SECURITY.md (this file)
- Release notes
- Git commit messages (with permission)

## Security Hall of Fame

*(Reserved for security researchers who responsibly disclose vulnerabilities)*

---

**Last Updated**: December 2025
