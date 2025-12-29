//
//  McNealAlphabetConfig.swift
//  McNealProtocol Reference Implementation
//
//  Copyright (c) 2025. Licensed under Apache-2.0.
//

import Foundation
import CryptoKit

public struct McNealAlphabetConfig {
    public let versionTag: String
    public let minHz: Double
    public let maxHz: Double
    public let symbols: [String]
    
    // Timing bounds (ms)
    public let minSliceMs: Int
    public let maxSliceMs: Int
    public let minFadeMs: Int
    public let maxFadeMs: Int
    public let packetJitterMaxMs: Int
    
    public init(
        versionTag: String = "MCNEAL-ALPHABET-v4-RATCHETED",
        minHz: Double = 300.0,
        maxHz: Double = 12000.0,
        symbols: [String] = McNealAlphabetDefaults.v1Symbols,
        minSliceMs: Int = 40,
        maxSliceMs: Int = 60,
        minFadeMs: Int = 3,
        maxFadeMs: Int = 6,
        packetJitterMaxMs: Int = 0
    ) {
        self.versionTag = versionTag
        self.minHz = minHz
        self.maxHz = maxHz
        self.symbols = symbols
        self.minSliceMs = minSliceMs
        self.maxSliceMs = maxSliceMs
        self.minFadeMs = minFadeMs
        self.maxFadeMs = maxFadeMs
        self.packetJitterMaxMs = packetJitterMaxMs
    }
}

public enum McNealAlphabetDefaults {
    
    /// Hard-coded symbol universe (v1).
    public static let v1Symbols: [String] = {
        var s: [String] = []
        
        // Lowercase + Uppercase
        s += (0..<26).map { String(UnicodeScalar(97 + $0)!) }  // a-z
        s += (0..<26).map { String(UnicodeScalar(65 + $0)!) }  // A-Z
        
        // Digits
        s += (0..<10).map { String($0) }
        
        // Whitespace tokens (explicit)
        s += [" ", "\n", "\t"]
        
        // Common punctuation / symbols
        s += Array("!@#$%^&*()-_=+[]{}|;:'\",.<>?/\\`~").map { String($0) }
        
        // A starter emoji set
        s += ["😀","😂","😅","😊","😎","🤔","😭","😡","❤️","👍","👎","🔒","🔐","📞","🎧","📁","📄","📊","💾","⚡️","🚀","🌐","🛰️","🧠","🧩"]
        
        // Protocol tokens
        s += ["⟦", "⟧", "⟨", "⟩"]
        
        // Remove duplicates while preserving order
        var seen = Set<String>()
        return s.filter { seen.insert($0).inserted }
    }()
}

// MARK: - McNeal Alphabet (Ratcheted per-message)

public final class McNealAlphabet {
    
    public let config: McNealAlphabetConfig
    
    /// Symbol order (never shuffled)
    public private(set) var shuffledSymbols: [String] = []
    
    /// symbol -> index in shuffledSymbols
    public private(set) var symbolToIndex: [String: Int] = [:]
    
    /// TRUE McNeal: Randomized frequency map derived from msgKey (RATCHETED!)
    public private(set) var frequencyMap: [Double] = []
    
    public private(set) var timing: Timing
    
    /// TRUE McNeal: Create alphabet from per-message key (RATCHETED!)
    /// Each message gets a DIFFERENT frequency mapping!
    public init(msgKey32: Data, config: McNealAlphabetConfig = .init()) throws {
        guard msgKey32.count == 32 else {
            throw NSError(
                domain: "McNealAlphabet",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "msgKey must be 32 bytes"]
            )
        }
        
        self.config = config
        
        // Derive timing from msgKey (changes per message!)
        self.timing = Self.deriveTiming(
            msgKey32: msgKey32,
            versionTag: config.versionTag,
            config: config
        )
        
        // NO SHUFFLE - use symbols in original order
        self.shuffledSymbols = config.symbols
        
        // TRUE McNeal: Generate randomized frequency mapping from msgKey (RATCHETED!)
        self.frequencyMap = Self.deriveFrequencyMapping(
            msgKey32: msgKey32,
            versionTag: config.versionTag,
            symbolCount: config.symbols.count,
            config: config
        )
        
        // Build reverse map
        var map: [String: Int] = [:]
        map.reserveCapacity(shuffledSymbols.count)
        for (i, sym) in shuffledSymbols.enumerated() {
            map[sym] = i
        }
        self.symbolToIndex = map
    }
    
    // MARK: - Mapping
    
    /// Use randomized frequency map
    public func hz(forSymbol symbol: String) throws -> Double {
        guard let idx = symbolToIndex[symbol] else {
            throw NSError(domain: "McNealAlphabet", code: 10,
                          userInfo: [NSLocalizedDescriptionKey: "Unknown symbol: \(symbol)"])
        }
        return frequencyMap[idx]
    }
    
    /// Find closest frequency in randomized map
    public func symbol(forHz hz: Double) throws -> String {
        var bestIdx = 0
        var bestDist = Double.infinity
        
        for (idx, freq) in frequencyMap.enumerated() {
            let dist = abs(freq - hz)
            if dist < bestDist {
                bestDist = dist
                bestIdx = idx
            }
        }
        
        // Tolerance: within 25 Hz
        guard bestDist < 25.0 else {
            throw NSError(domain: "McNealAlphabet", code: 12,
                          userInfo: [NSLocalizedDescriptionKey: "No symbol near \(hz) Hz (closest: \(frequencyMap[bestIdx]) Hz, dist: \(bestDist))"])
        }
        
        return shuffledSymbols[bestIdx]
    }
    
    // MARK: - Encoding text
    
    public func encodeToHz(_ text: String) throws -> [Double] {
        var out: [Double] = []
        out.reserveCapacity(text.count)
        for ch in text {
            let sym = String(ch)
            out.append(try hz(forSymbol: sym))
        }
        return out
    }
    
    public func decodeFromHz(_ hzValues: [Double]) throws -> String {
        var s = ""
        s.reserveCapacity(hzValues.count)
        for hz in hzValues {
            s.append(try symbol(forHz: hz))
        }
        return s
    }
    
    // MARK: - Compact transport
    
    public func encodeToIndices(_ text: String) throws -> [UInt16] {
        var out: [UInt16] = []
        out.reserveCapacity(text.count)
        for ch in text {
            let sym = String(ch)
            guard let idx = symbolToIndex[sym] else {
                throw NSError(domain: "McNealAlphabet", code: 20,
                              userInfo: [NSLocalizedDescriptionKey: "Unknown symbol: \(sym)"])
            }
            guard idx <= Int(UInt16.max) else {
                throw NSError(domain: "McNealAlphabet", code: 21,
                              userInfo: [NSLocalizedDescriptionKey: "Alphabet too large for UInt16"])
            }
            out.append(UInt16(idx))
        }
        return out
    }
    
    public func decodeFromIndices(_ indices: [UInt16]) throws -> String {
        var s = ""
        s.reserveCapacity(indices.count)
        for i in indices {
            let idx = Int(i)
            guard idx >= 0 && idx < shuffledSymbols.count else {
                throw NSError(domain: "McNealAlphabet", code: 22,
                              userInfo: [NSLocalizedDescriptionKey: "Index out of range: \(idx)"])
            }
            s.append(shuffledSymbols[idx])
        }
        return s
    }
    
    public func indicesToData(_ indices: [UInt16]) -> Data {
        var d = Data(capacity: indices.count * 2)
        for v in indices {
            var be = v.bigEndian
            d.append(Data(bytes: &be, count: 2))
        }
        return d
    }
    
    public func dataToIndices(_ data: Data) throws -> [UInt16] {
        guard data.count % 2 == 0 else {
            throw NSError(domain: "McNealAlphabet", code: 23,
                          userInfo: [NSLocalizedDescriptionKey: "Index data must be even length"])
        }
        var out: [UInt16] = []
        out.reserveCapacity(data.count / 2)
        var i = 0
        while i < data.count {
            let chunk = data.subdata(in: i..<(i+2))
            let v = chunk.withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
            out.append(v)
            i += 2
        }
        return out
    }
    
    // MARK: - Core Derivation: Per-Message Frequency Mapping
    
    /// Derive randomized frequency assignments from msgKey (RATCHETED!)
    /// Same msgKey -> same frequency map (deterministic)
    /// Different msgKey -> different frequency map (unpredictable)
    private static func deriveFrequencyMapping(
        msgKey32: Data,
        versionTag: String,
        symbolCount: Int,
        config: McNealAlphabetConfig
    ) -> [Double] {
        
        let sk = SymmetricKey(data: msgKey32)
        var msg = Data("MCNEAL-FREQ-MAP".utf8)
        msg.append(Data(versionTag.utf8))
        
        let mac = HMAC<SHA256>.authenticationCode(for: msg, using: sk)
        let seed = Data(mac)
        
        // Generate random frequencies with minimum spacing
        var frequencies: [Double] = []
        frequencies.reserveCapacity(symbolCount)
        
        let minSpacing = 15.0  // Minimum Hz between symbols
        let range = config.maxHz - config.minHz
        
        var counter: UInt64 = 0
        var attempts = 0
        let maxAttempts = symbolCount * 100
        
        while frequencies.count < symbolCount && attempts < maxAttempts {
            attempts += 1
            
            // Generate pseudo-random frequency
            let r = prngDouble(seed32: seed, counter: counter)
            counter &+= 1
            
            let hz = config.minHz + (r * range)
            
            // Check minimum spacing from existing frequencies
            var tooClose = false
            for existing in frequencies {
                if abs(hz - existing) < minSpacing {
                    tooClose = true
                    break
                }
            }
            
            if !tooClose {
                frequencies.append(hz)
            }
        }
        
        // If we couldn't generate enough with spacing, fill remaining with grid
        while frequencies.count < symbolCount {
            let idx = frequencies.count
            let hz = config.minHz + (Double(idx) * minSpacing * 2)
            frequencies.append(min(hz, config.maxHz))
        }
        
        return frequencies
    }
    
    // MARK: - Timing derivation
    
    private static func deriveTiming(
        msgKey32: Data,
        versionTag: String,
        config: McNealAlphabetConfig
    ) -> Timing {
        
        let sk = SymmetricKey(data: msgKey32)
        var msg = Data("MCNEAL-TIME-SLICE".utf8)
        msg.append(Data(versionTag.utf8))
        
        let mac = HMAC<SHA256>.authenticationCode(for: msg, using: sk)
        let seed = Data(mac)
        
        let sliceRange = max(1, config.maxSliceMs - config.minSliceMs + 1)
        let fadeRange  = max(1, config.maxFadeMs - config.minFadeMs + 1)
        
        let baseSliceMs = config.minSliceMs + Int(seed[0]) % sliceRange
        let fadeMs      = config.minFadeMs  + Int(seed[1]) % fadeRange
        
        return Timing(baseSliceMs: baseSliceMs, fadeMs: fadeMs)
    }
    
    public func sliceMsForPacket(msgKey32: Data) throws -> Int {
        guard msgKey32.count == 32 else {
            throw NSError(domain: "McNealAlphabet", code: 30,
                          userInfo: [NSLocalizedDescriptionKey: "msgKey must be 32 bytes"])
        }
        
        if config.packetJitterMaxMs <= 0 {
            return timing.baseSliceMs
        }
        
        let sk = SymmetricKey(data: msgKey32)
        let mac = HMAC<SHA256>.authenticationCode(
            for: Data("MCNEAL-PACKET-SLICE".utf8),
            using: sk
        )
        let out = Data(mac)
        
        let jitter = Int(out[0]) % (config.packetJitterMaxMs + 1)
        return timing.baseSliceMs + jitter
    }
    
    // MARK: - PRNG helpers
    
    private static func prngDouble(seed32: Data, counter: UInt64) -> Double {
        let sk = SymmetricKey(data: seed32)
        var msg = Data("MCNEAL-PRNG".utf8)
        var c = counter.bigEndian
        msg.append(Data(bytes: &c, count: 8))
        let mac = HMAC<SHA256>.authenticationCode(for: msg, using: sk)
        let out = Data(mac)
        let u64 = out.prefix(8).withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
        return Double(u64) / Double(UInt64.max)
    }
    
    public struct Timing {
        public let baseSliceMs: Int
        public let fadeMs: Int
    }
}
