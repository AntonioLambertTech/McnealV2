//
//  McNealAEAD.swift
//  MCNEALProtocol
//
//  Created by Antonio Lambert on 12/18/25.
//


import Foundation
import CryptoKit

public enum McNealAEAD {

    /// Build a 12-byte nonce deterministically from sid + epoch + seq.
    /// ChaChaPoly.Nonce is 12 bytes.
    ///
    /// nonce = SHA256( "MCNEAL-NONCE" || sid(16) || epoch(4) || seq(8) )[0..<12]
    public static func nonce(sid: UUID, epoch: UInt32, seq: UInt64) throws -> ChaChaPoly.Nonce {
        var material = Data("MCNEAL-NONCE".utf8)
        material.append(sid.uuidBytes)
        material.append(u32be(epoch))
        material.append(u64be(seq))

        let hash = Data(SHA256.hash(data: material))
        let n12 = hash.prefix(12)
        return try ChaChaPoly.Nonce(data: n12)
    }

    /// Encrypt plaintext -> ciphertext + tag (16 bytes).
    /// AAD is authenticated but not encrypted (we use header bytes).
    public static func seal(
        plaintext: Data,
        msgKey32: Data,
        nonce: ChaChaPoly.Nonce,
        aad: Data
    ) throws -> (ciphertext: Data, tag: Data) {
        guard msgKey32.count == 32 else { throw err("msgKey must be 32 bytes") }
        let key = SymmetricKey(data: msgKey32)
        let sealed = try ChaChaPoly.seal(plaintext, using: key, nonce: nonce, authenticating: aad)
        return (sealed.ciphertext, sealed.tag)
    }

    /// Decrypt ciphertext + tag -> plaintext.
    public static func open(
        ciphertext: Data,
        tag: Data,
        msgKey32: Data,
        nonce: ChaChaPoly.Nonce,
        aad: Data
    ) throws -> Data {
        guard msgKey32.count == 32 else { throw err("msgKey must be 32 bytes") }
        guard tag.count == 16 else { throw err("tag must be 16 bytes") }

        let key = SymmetricKey(data: msgKey32)
        let box = try ChaChaPoly.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        return try ChaChaPoly.open(box, using: key, authenticating: aad)
    }

    // MARK: - helpers

    private static func u32be(_ x: UInt32) -> Data {
        var v = x.bigEndian
        return Data(bytes: &v, count: 4)
    }

    private static func u64be(_ x: UInt64) -> Data {
        var v = x.bigEndian
        return Data(bytes: &v, count: 8)
    }

    private static func err(_ msg: String) -> NSError {
        NSError(domain: "McNealAEAD", code: 1, userInfo: [NSLocalizedDescriptionKey: msg])
    }
}

private extension UUID {
    var uuidBytes: Data { withUnsafeBytes(of: uuid) { Data($0) } }
}
