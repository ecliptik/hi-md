import AudioToolbox
import AVFoundation
#if targetEnvironment(macCatalyst)
import CoreAudio // UnsafeMutableAudioBufferListPointer on the Mac
#endif
import Foundation
import Synchronization

/// Whether multichannel audio is folded down to stereo, readable from the render thread.
///
/// The Subsonic API has no channel option and Navidrome's stock transcodings keep every channel,
/// so the fold-down happens here, in the audio tap, for originals and conversions alike.
nonisolated final class DownmixParameters: Sendable {
    static let shared = DownmixParameters()
    static let didChange = Notification.Name("minidisc.downmixDidChange")

    private let enabledValue = Atomic<Bool>(true)

    var isEnabled: Bool {
        get { enabledValue.load(ordering: .relaxed) }
        set {
            let previous = enabledValue.exchange(newValue, ordering: .relaxed)
            guard previous != newValue else { return }
            NotificationCenter.default.post(name: Self.didChange, object: self)
        }
    }
}

/// How much of each source channel goes to the left and right outputs.
nonisolated struct DownmixMatrix: Equatable, Sendable {
    static let maxChannels = 8
    private static let half: Float = 0.7071

    /// Left and right coefficients per input channel.
    let left: [Float]
    let right: [Float]

    var channelCount: Int { left.count }

    /// The ITU fold-down (centre and surrounds at -3 dB, LFE dropped), scaled so that the output
    /// can't exceed the loudest input: the louder side's coefficients add up to 1.
    init(labels: [AudioChannelLabel]) {
        var left: [Float] = []
        var right: [Float] = []
        for label in labels.prefix(Self.maxChannels) {
            let pair = Self.coefficients(for: label)
            left.append(pair.left)
            right.append(pair.right)
        }
        let scale = 1 / max(1, left.reduce(0, +), right.reduce(0, +))
        self.left = left.map { $0 * scale }
        self.right = right.map { $0 * scale }
    }

    /// The usual decoded order when a file states no layout: L R C LFE Ls Rs Lb Rb, as in WAVE.
    static func defaultLabels(channels: Int) -> [AudioChannelLabel] {
        let wave: [AudioChannelLabel] = [
            kAudioChannelLabel_Left, kAudioChannelLabel_Right, kAudioChannelLabel_Center, kAudioChannelLabel_LFEScreen,
            kAudioChannelLabel_LeftSurround, kAudioChannelLabel_RightSurround,
            kAudioChannelLabel_RearSurroundLeft, kAudioChannelLabel_RearSurroundRight,
        ]
        switch channels {
        case 3: return [kAudioChannelLabel_Left, kAudioChannelLabel_Right, kAudioChannelLabel_Center]
        case 4: return [kAudioChannelLabel_Left, kAudioChannelLabel_Right,
                        kAudioChannelLabel_LeftSurround, kAudioChannelLabel_RightSurround]
        case 5: return [kAudioChannelLabel_Left, kAudioChannelLabel_Right, kAudioChannelLabel_Center,
                        kAudioChannelLabel_LeftSurround, kAudioChannelLabel_RightSurround]
        default: return Array(wave.prefix(max(0, channels)))
        }
    }

    private static func coefficients(for label: AudioChannelLabel) -> (left: Float, right: Float) {
        switch label {
        case kAudioChannelLabel_Left, kAudioChannelLabel_LeftWide, kAudioChannelLabel_LeftCenter:
            (1, 0)
        case kAudioChannelLabel_Right, kAudioChannelLabel_RightWide, kAudioChannelLabel_RightCenter:
            (0, 1)
        case kAudioChannelLabel_Center, kAudioChannelLabel_Mono:
            (half, half)
        case kAudioChannelLabel_LFEScreen, kAudioChannelLabel_LFE2:
            (0, 0)
        case kAudioChannelLabel_LeftSurround, kAudioChannelLabel_LeftSurroundDirect, kAudioChannelLabel_RearSurroundLeft,
             kAudioChannelLabel_VerticalHeightLeft, kAudioChannelLabel_TopBackLeft:
            (half, 0)
        case kAudioChannelLabel_RightSurround, kAudioChannelLabel_RightSurroundDirect, kAudioChannelLabel_RearSurroundRight,
             kAudioChannelLabel_VerticalHeightRight, kAudioChannelLabel_TopBackRight:
            (0, half)
        default:
            (half / 2, half / 2)
        }
    }

    /// The channel order a track's format description declares, or nil when it declares none.
    /// Called while installing the tap, never on the render thread.
    static func channelLabels(of description: CMAudioFormatDescription) -> [AudioChannelLabel]? {
        var size = 0
        guard let layout = CMAudioFormatDescriptionGetChannelLayout(description, sizeOut: &size) else { return nil }
        return channelLabels(of: layout)
    }

    static func channelLabels(of layout: UnsafePointer<AudioChannelLayout>) -> [AudioChannelLabel]? {
        let tag = layout.pointee.mChannelLayoutTag
        if tag == kAudioChannelLayoutTag_UseChannelDescriptions {
            return descriptionLabels(of: layout)
        }
        var specifier = tag == kAudioChannelLayoutTag_UseChannelBitmap ? layout.pointee.mChannelBitmap.rawValue : tag
        let property = tag == kAudioChannelLayoutTag_UseChannelBitmap
            ? kAudioFormatProperty_ChannelLayoutForBitmap
            : kAudioFormatProperty_ChannelLayoutForTag
        let specifierSize = UInt32(MemoryLayout<UInt32>.size)
        var dataSize: UInt32 = 0
        guard AudioFormatGetPropertyInfo(property, specifierSize, &specifier, &dataSize) == noErr,
              Int(dataSize) >= MemoryLayout<AudioChannelLayout>.size else { return nil }
        let expanded = UnsafeMutableRawPointer.allocate(byteCount: Int(dataSize), alignment: MemoryLayout<AudioChannelLayout>.alignment)
        defer { expanded.deallocate() }
        guard AudioFormatGetProperty(property, specifierSize, &specifier, &dataSize, expanded) == noErr else { return nil }
        // The expanded layout lists its descriptions even when it keeps the original tag.
        return descriptionLabels(of: UnsafePointer(expanded.assumingMemoryBound(to: AudioChannelLayout.self)))
    }

    private static func descriptionLabels(of layout: UnsafePointer<AudioChannelLayout>) -> [AudioChannelLabel]? {
        let count = Int(layout.pointee.mNumberChannelDescriptions)
        guard count > 0, let offset = MemoryLayout<AudioChannelLayout>.offset(of: \.mChannelDescriptions) else { return nil }
        let descriptions = UnsafeRawPointer(layout).advanced(by: offset).assumingMemoryBound(to: AudioChannelDescription.self)
        return (0..<count).map { descriptions[$0].mChannelLabel }
    }
}

/// Folds one tap's multichannel audio into its first two channels and silences the rest, so the
/// system mixer outputs plain stereo. Stereo and mono pass through untouched. Coefficients are
/// copied into fixed storage in `prepare`, so `process` neither allocates nor locks.
nonisolated final class StereoDownmixProcessor: @unchecked Sendable {
    private let parameters: DownmixParameters
    /// The order the track declared; used when its channel count matches the tap's.
    private let declaredLabels: [AudioChannelLabel]?
    private var channels = 2
    private var interleaved = false
    private var left = SIMD8<Float>(repeating: 0)
    private var right = SIMD8<Float>(repeating: 0)

    init(labels: [AudioChannelLabel]?, parameters: DownmixParameters = .shared) {
        self.parameters = parameters
        declaredLabels = labels
    }

    var isMultichannel: Bool { channels > 2 }

    func prepare(channels: Int, interleaved: Bool) {
        self.channels = max(1, min(channels, DownmixMatrix.maxChannels))
        self.interleaved = interleaved
        guard self.channels > 2 else { return }
        let labels = if let declaredLabels, declaredLabels.count == self.channels {
            declaredLabels
        } else {
            DownmixMatrix.defaultLabels(channels: self.channels)
        }
        let matrix = DownmixMatrix(labels: labels)
        left = SIMD8(repeating: 0)
        right = SIMD8(repeating: 0)
        for channel in 0..<matrix.channelCount {
            left[channel] = matrix.left[channel]
            right[channel] = matrix.right[channel]
        }
    }

    func process(_ buffers: UnsafeMutableAudioBufferListPointer, frames: Int) {
        guard channels > 2, parameters.isEnabled else { return }
        if interleaved {
            guard let data = buffers.first?.mData else { return }
            let samples = data.assumingMemoryBound(to: Float.self)
            for frame in 0..<frames {
                let base = frame * channels
                var l: Float = 0
                var r: Float = 0
                for channel in 0..<channels {
                    l += samples[base + channel] * left[channel]
                    r += samples[base + channel] * right[channel]
                }
                samples[base] = l
                samples[base + 1] = r
                for channel in 2..<channels { samples[base + channel] = 0 }
            }
        } else {
            guard buffers.count >= channels else { return }
            for frame in 0..<frames {
                var l: Float = 0
                var r: Float = 0
                for channel in 0..<channels {
                    guard let data = buffers[channel].mData else { continue }
                    let sample = data.assumingMemoryBound(to: Float.self)[frame]
                    l += sample * left[channel]
                    r += sample * right[channel]
                }
                for channel in 0..<channels {
                    guard let data = buffers[channel].mData else { continue }
                    data.assumingMemoryBound(to: Float.self)[frame] = channel == 0 ? l : (channel == 1 ? r : 0)
                }
            }
        }
    }
}
