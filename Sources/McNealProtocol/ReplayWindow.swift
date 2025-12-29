//
//  ReplayWindow.swift
//  MCNEALProtocol
//
//  Created by Antonio Lambert on 12/18/25.
//


import Foundation

/// Sliding anti-replay window for monotonically increasing sequence numbers.
/// - Accepts out-of-order packets within `windowSize`.
/// - Rejects duplicates.
/// - Rejects packets older than (maxSeen - windowSize + 1).
///
/// Typical use:
///   var win = ReplayWindow(windowSize: 256)
///   switch win.observe(seq) { case .acceptNew, .acceptOutOfOrder: ...; default: drop }
public struct ReplayWindow: Sendable, Codable {

    public enum Decision: Equatable, Sendable {
        /// Sequence advanced `maxSeen` forward (new highest seq).
        case acceptNew
        /// Accepted within window, but not the highest (out-of-order).
        case acceptOutOfOrder
        /// Sequence already received (duplicate).
        case rejectDuplicate
        /// Sequence is too old (outside window).
        case rejectTooOld
    }

    /// Number of sequence numbers to track (must be >= 1).
    public let windowSize: Int

    /// Highest sequence number seen so far.
    public private(set) var maxSeen: UInt64

    /// Bitset marking which sequences in [maxSeen-windowSize+1 ... maxSeen] have been seen.
    /// Least significant bit (bit 0) corresponds to maxSeen itself.
    private var bits: [UInt64]

    /// Create a replay window.
    /// - Parameters:
    ///   - windowSize: how many recent seq values to remember. (Suggested: 128–1024)
    ///   - initialMaxSeen: if you already have a baseline; otherwise 0.
    public init(windowSize: Int = 256, initialMaxSeen: UInt64 = 0) {
        precondition(windowSize >= 1, "windowSize must be >= 1")
        self.windowSize = windowSize
        self.maxSeen = initialMaxSeen

        let wordCount = (windowSize + 63) / 64
        self.bits = Array(repeating: 0, count: max(1, wordCount))

        // If you set initialMaxSeen, mark it as seen? Usually no.
        // We'll leave it unmarked; first observe() will set bits accordingly.
    }

    /// Observe a sequence number and update window state.
    /// Returns whether to accept or reject it.
    @discardableResult
    public mutating func observe(_ seq: UInt64) -> Decision {
        // If this is the first meaningful packet, allow anything and set maxSeen.
        if maxSeen == 0 && isEmptyBits() {
            maxSeen = seq
            setSeen(offsetFromMax: 0)
            return .acceptNew
        }

        if seq > maxSeen {
            let delta = seq - maxSeen
            advanceWindow(by: Int(delta))
            maxSeen = seq
            setSeen(offsetFromMax: 0)
            return .acceptNew
        }

        // seq <= maxSeen: check if within window
        let back = maxSeen - seq  // how far behind max
        if back >= UInt64(windowSize) {
            return .rejectTooOld
        }

        // back is within [0 .. windowSize-1]
        if isSeen(offsetFromMax: Int(back)) {
            return .rejectDuplicate
        } else {
            setSeen(offsetFromMax: Int(back))
            // If back == 0 it means same as maxSeen, but we handled seq>maxSeen earlier.
            return (back == 0) ? .acceptNew : .acceptOutOfOrder
        }
    }

    /// Whether a seq would be considered too old right now (without mutating).
    public func isTooOld(_ seq: UInt64) -> Bool {
        if maxSeen == 0 && isEmptyBits() { return false }
        if seq > maxSeen { return false }
        let back = maxSeen - seq
        return back >= UInt64(windowSize)
    }

    /// Reset window state (e.g., on session restart).
    public mutating func reset(initialMaxSeen: UInt64 = 0) {
        self.maxSeen = initialMaxSeen
        for i in bits.indices { bits[i] = 0 }
    }

    // MARK: - Internal bitset ops

    private func isEmptyBits() -> Bool {
        for w in bits where w != 0 { return false }
        return true
    }

    private func isSeen(offsetFromMax: Int) -> Bool {
        // offsetFromMax = 0 means maxSeen
        let bitIndex = offsetFromMax
        let word = bitIndex / 64
        let bit = bitIndex % 64
        let mask = UInt64(1) << UInt64(bit)
        return (bits[word] & mask) != 0
    }

    private mutating func setSeen(offsetFromMax: Int) {
        let bitIndex = offsetFromMax
        let word = bitIndex / 64
        let bit = bitIndex % 64
        let mask = UInt64(1) << UInt64(bit)
        bits[word] |= mask
    }

    private mutating func advanceWindow(by delta: Int) {
        // We are shifting the whole bitset "right" by delta,
        // because what used to be maxSeen becomes older relative to new max.
        // After shifting, we clear the newest bits (offset 0..delta-1).
        if delta <= 0 { return }

        if delta >= windowSize {
            // Everything falls out of window; clear entirely.
            for i in bits.indices { bits[i] = 0 }
            return
        }

        shiftRightBits(by: delta)

        // Clear the top delta offsets: offsets 0..delta-1 are "new max slots"
        for offset in 0..<delta {
            clearSeen(offsetFromMax: offset)
        }
    }

    private mutating func clearSeen(offsetFromMax: Int) {
        let bitIndex = offsetFromMax
        let word = bitIndex / 64
        let bit = bitIndex % 64
        let mask = ~(UInt64(1) << UInt64(bit))
        bits[word] &= mask
    }

    private mutating func shiftRightBits(by shift: Int) {
        // Shift the entire [UInt64] bit-array right by `shift` bits.
        // bit 0 is maxSeen (newest), larger offsets are older.
        let wordShift = shift / 64
        let bitShift = shift % 64

        if wordShift > 0 {
            for i in stride(from: bits.count - 1, through: 0, by: -1) {
                let src = i + wordShift
                bits[i] = (src < bits.count) ? bits[src] : 0
            }
        }

        if bitShift > 0 {
            for i in 0..<bits.count {
                let high = bits[i] >> UInt64(bitShift)
                let carry: UInt64
                if i + 1 < bits.count {
                    carry = bits[i + 1] << UInt64(64 - bitShift)
                } else {
                    carry = 0
                }
                bits[i] = high | carry
            }
        }
    }
}
