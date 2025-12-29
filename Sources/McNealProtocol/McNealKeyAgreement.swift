//
//  McNealKeyAgreement.swift
//  MCNEALProtocol
//
//  Created by Antonio Lambert on 12/18/25.
//


import Foundation
import CryptoKit

public enum McNealKeyAgreement {

    // MARK: - Constants

    private static let pskBindLabel = "mcneal-bind"
    private static let rootInfoLabel = "MCNEAL-ROOT-v1"

    // MARK: - Types

    public struct EphemeralKeyPair {
        public let privateKey: Curve25519.KeyAgreement.PrivateKey
        public let publicKey: Curve25519.KeyAgreement.PublicKey

        public init() {
            let priv = Curve25519.KeyAgreement.PrivateKey()
            self.privateKey = priv
            self.publicKey = priv.publicKey
        }

        public var publicKeyRaw: Data {
            publicKey.rawRepresentation
        }
    }

    // MARK: - Public API

    /// Generate a fresh ephemeral X25519 keypair.
    public static func generateEphemeralKeyPair() -> EphemeralKeyPair {
        EphemeralKeyPair()
    }

    ///
    /// IMPORTANT: Nonce ordering must match on both sides.
    /// We lock the ordering as: initiatorNonce first, responderNonce second.

    public static func deriveRootKey(
        localPrivateKey: Curve25519.KeyAgreement.PrivateKey,
        remotePublicKeyRaw: Data,
        initiatorNonce: Data,
        responderNonce: Data,
        psk: Data? = nil
    ) throws -> Data {

        try validateNonce(initiatorNonce, name: "initiatorNonce")
        try validateNonce(responderNonce, name: "responderNonce")

        let remotePub = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: remotePublicKeyRaw)
        let sharedSecret = try localPrivateKey.sharedSecretFromKeyAgreement(with: remotePub)

        // salt = SHA256( initiatorNonce || responderNonce || (pskBind?) )
        var saltMaterial = Data()
        saltMaterial.append(initiatorNonce)
        saltMaterial.append(responderNonce)

        if let psk, !psk.isEmpty {
            let bind = pskBind(psk: psk) // 32 bytes
            saltMaterial.append(bind)
        }

        let salt = Data(SHA256.hash(data: saltMaterial)) // 32 bytes

        let info = Data(rootInfoLabel.utf8)

        // HKDF over the shared secret → root key (32 bytes)
        let rootSymKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: salt,
            sharedInfo: info,
            outputByteCount: 32
        )

        return rootSymKey.withUnsafeBytes { Data($0) }
    }

    // MARK: - Helpers

    private static func pskBind(psk: Data) -> Data {
        let key = SymmetricKey(data: psk)
        let mac = HMAC<SHA256>.authenticationCode(for: Data(pskBindLabel.utf8), using: key)
        return Data(mac) // 32 bytes
    }

    private static func validateNonce(_ n: Data, name: String) throws {
        guard n.count == 32 else {
            throw NSError(
                domain: "McNealKeyAgreement",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "\(name) must be exactly 32 bytes (got \(n.count))"]
            )
        }
    }
}
