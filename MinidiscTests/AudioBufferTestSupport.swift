import AudioToolbox
import AVFoundation
#if targetEnvironment(macCatalyst)
import CoreAudio
#endif
import Foundation
import Testing
@testable import Minidisc

/// Non-interleaved float channels wrapped in an AudioBufferList, as an audio tap sees them.
nonisolated final class TestBuffers {
    let channels: [UnsafeMutablePointer<Float>]
    let frames: Int
    let list: UnsafeMutableAudioBufferListPointer

    init(channels count: Int, frames: Int, fill: (_ channel: Int, _ frame: Int) -> Float) {
        self.frames = frames
        channels = (0..<count).map { channel in
            let pointer = UnsafeMutablePointer<Float>.allocate(capacity: frames)
            for frame in 0..<frames { pointer[frame] = fill(channel, frame) }
            return pointer
        }
        list = AudioBufferList.allocate(maximumBuffers: count)
        for (index, pointer) in channels.enumerated() {
            list[index] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(frames * 4), mData: pointer)
        }
    }

    deinit {
        channels.forEach { $0.deallocate() }
        free(list.unsafeMutablePointer)
    }

    func samples(_ channel: Int) -> [Float] { (0..<frames).map { channels[channel][$0] } }
}
