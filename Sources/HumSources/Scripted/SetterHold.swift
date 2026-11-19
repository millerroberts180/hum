import Foundation
import HumCore

/// What Hum just set in a scripted app, held against the app's replies for a
/// moment.
///
/// Spotify answers a shuffle, repeat, volume or position command before it
/// takes the new value, so a read in the next half second can still report the
/// old one, and the player would flick back to it (§13.34). Each value Hum set
/// stands in for the app's until a reply agrees with it or `duration` passes,
/// when the app's word is final.
public struct SetterHold: Equatable, Sendable {
    /// How long a set value outlasts replies that disagree with it.
    public static let duration: TimeInterval = 1.5
    /// A reported position this close to where the seek should have got to
    /// agrees with it.
    public static let seekTolerance: TimeInterval = 1.5
    /// A reported volume this close to the set one agrees with it: the apps
    /// keep whole percents.
    public static let volumeTolerance = 0.015

    struct Held<Value: Equatable & Sendable>: Equatable, Sendable {
        var value: Value
        var at: Date
    }

    struct Seek: Equatable, Sendable {
        var track: TrackID?
        var position: TimeInterval
    }

    private var shuffle: Held<Bool>?
    private var repeatMode: Held<RepeatMode>?
    private var volume: Held<Double>?
    private var seek: Held<Seek>?

    public init() {}

    /// Nothing is held.
    public var isEmpty: Bool {
        shuffle == nil && repeatMode == nil && volume == nil && seek == nil
    }

    /// The app accepted `command` at `date`, with `track` playing.
    public mutating func record(_ command: PlaybackCommand, track: TrackID?, at date: Date) {
        switch command {
        case .setShuffle(let value): shuffle = Held(value: value, at: date)
        case .setRepeat(let mode): repeatMode = Held(value: mode, at: date)
        case .setVolume(let value): volume = Held(value: value, at: date)
        case .seek(let position): seek = Held(value: Seek(track: track, position: position), at: date)
        default: break
        }
    }

    /// `reply` with each held value in place of the app's, judged at the
    /// reply's own time. A reply that agrees, or comes after `duration`, lets
    /// that value go; a new song lets the position go.
    public mutating func apply(to reply: PlaybackSnapshot) -> PlaybackSnapshot {
        var reply = reply
        let date = reply.timestamp
        if let held = live(shuffle, at: date), reply.shuffle != held.value {
            reply.shuffle = held.value
        } else {
            shuffle = nil
        }
        if let held = live(repeatMode, at: date), reply.repeatMode != held.value {
            reply.repeatMode = held.value
        } else {
            repeatMode = nil
        }
        if let held = live(volume, at: date), abs((reply.volume ?? -1) - held.value) > Self.volumeTolerance {
            reply.volume = held.value
        } else {
            volume = nil
        }
        if let held = live(seek, at: date), held.value.track == reply.track?.id {
            let elapsed = reply.status.isPlaying ? max(0, date.timeIntervalSince(held.at)) : 0
            let expected = held.value.position + elapsed
            if let position = reply.position, abs(position - expected) <= Self.seekTolerance {
                seek = nil
            } else {
                reply.position = expected
            }
        } else {
            seek = nil
        }
        return reply
    }

    private func live<Value>(_ held: Held<Value>?, at date: Date) -> Held<Value>? {
        guard let held, date.timeIntervalSince(held.at) <= Self.duration else { return nil }
        return held
    }
}
