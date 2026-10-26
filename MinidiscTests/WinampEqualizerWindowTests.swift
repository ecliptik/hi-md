import CoreGraphics
import Foundation
import Testing
@testable import Minidisc

// MARK: - Equaliser

@Suite("Winamp equaliser")
struct WinampEqualizerTests {
    @Test func slidersDriveTheEngineBandsInOrder() {
        #expect(WinampEqualizerBands.count == Equalizer.bandCount)
        for slider in 0..<WinampEqualizerBands.count {
            #expect(WinampEqualizerBands.engineBand(forSlider: slider) == slider)
            #expect(WinampEqualizerBands.slider(forEngineBand: slider) == slider)
        }
        #expect(WinampEqualizerBands.engineBand(forSlider: 10) == nil)
        #expect(WinampEqualizerBands.sliderGains(fromEngine: [1, 2, 3]) == [1, 2, 3, 0, 0, 0, 0, 0, 0, 0])
        #expect(WinampEqualizerBands.engineFrequencies.first == 31)
        #expect(WinampEqualizerBands.winampFrequencies.first == 60)
    }

    @Test func sliderGeometryCoversTwelveDecibelsEachWay() {
        #expect(WinampEqualizerSlider.thumbOffset(for: 12) == 0)
        #expect(WinampEqualizerSlider.thumbOffset(for: -12) == 51)
        #expect(WinampEqualizerSlider.thumbOffset(for: 0) == 26)
        #expect(WinampEqualizerSlider.backgroundFrame(for: -12) == 0)
        #expect(WinampEqualizerSlider.backgroundFrame(for: 12) == 27)
        #expect(WinampEqualizerSlider.backgroundFrame(for: 40) == 27)
        #expect(WinampEqualizerSlider.fraction(for: .nan) == 0.5)
    }

    @Test func draggingSetsAValueAndSnapsToTheMiddle() {
        #expect(WinampEqualizerSlider.dB(pointerY: 0, grabOffset: 0) == 12)
        #expect(WinampEqualizerSlider.dB(pointerY: 51, grabOffset: 0) == -12)
        #expect(WinampEqualizerSlider.dB(pointerY: 200, grabOffset: 0) == -12)
        #expect(WinampEqualizerSlider.dB(pointerY: 26, grabOffset: 0) == 0)
        #expect(WinampEqualizerSlider.dB(pointerY: 31.5, grabOffset: 5.5) == 0)
        let grab = WinampEqualizerSlider.grabOffset(pointerY: 30, currentDB: 0)
        #expect(grab == 4)
        #expect(WinampEqualizerSlider.dB(pointerY: 30, grabOffset: grab) == 0)
    }

    @Test func hitTestingFindsTheSliders() {
        #expect(WinampEqualizerLayout.control(at: CGPoint(x: 25, y: 60), hasShade: true) == .preamp)
        #expect(WinampEqualizerLayout.control(at: CGPoint(x: 80, y: 60), hasShade: true) == .band(0))
        #expect(WinampEqualizerLayout.control(at: CGPoint(x: 245, y: 60), hasShade: true) == .band(9))
        #expect(WinampEqualizerLayout.control(at: CGPoint(x: 20, y: 22), hasShade: true) == .on)
        #expect(WinampEqualizerLayout.control(at: CGPoint(x: 50, y: 22), hasShade: true) == .auto)
        #expect(WinampEqualizerLayout.control(at: CGPoint(x: 230, y: 22), hasShade: true) == .presets)
        #expect(WinampEqualizerLayout.control(at: CGPoint(x: 258, y: 6), hasShade: true) == .shade)
        #expect(WinampEqualizerLayout.control(at: CGPoint(x: 258, y: 6), hasShade: false) == .titleBar)
        #expect(WinampEqualizerLayout.control(at: CGPoint(x: 268, y: 6), hasShade: false) == .close)
        #expect(WinampEqualizerLayout.shadeControl(at: CGPoint(x: 100, y: 5)) == .titleBar)
        #expect(WinampEqualizerLayout.shadeControl(at: CGPoint(x: 258, y: 6)) == .shade)
    }

    @Test func eqfBytesRunFromBoostToCut() {
        #expect(WinampEQF.byte(for: 12) == 0)
        #expect(WinampEQF.byte(for: -12) == 63)
        #expect(WinampEQF.dB(for: 0) == 12)
        #expect(WinampEQF.dB(for: 63) == -12)
        #expect(WinampEQF.dB(for: 200) == -12)
        for byte in UInt8(0)...63 {
            #expect(WinampEQF.byte(for: WinampEQF.dB(for: byte)) == byte)
        }
    }

    @Test func presetsRoundTripThroughAnEQFFile() throws {
        let presets = [
            WinampEqualizerPreset(name: "Rock", preamp: -4, gains: EqualizerPreset.rock.gains),
            WinampEqualizerPreset(name: "Mine – ünïcode", preamp: 0, gains: [12, -12, 0, 3, -3, 6, -6, 1.5, -1.5, 0]),
        ]
        let data = WinampEQF.encode(presets)
        #expect(data.count == WinampEQF.header.count + 2 * WinampEQF.presetLength)
        let decoded = try #require(WinampEQF.decode(data))
        #expect(decoded.map(\.name) == presets.map(\.name))
        for (read, written) in zip(decoded, presets) {
            #expect(abs(read.preamp - written.preamp) <= 0.2)
            for (a, b) in zip(read.gains, written.gains) { #expect(abs(a - b) <= 0.2) }
        }
        // A second pass changes nothing: the file's steps are exact.
        #expect(WinampEQF.encode(decoded) == data)
    }

    @Test func eqfReadingRefusesOtherFiles() {
        #expect(WinampEQF.decode(Data("#EXTM3U\n".utf8)) == nil)
        #expect(WinampEQF.decode(Data(WinampEQF.header)) == [])
        var truncated = WinampEQF.encode([WinampEqualizerPreset(name: "A", preamp: 0, gains: [])])
        truncated.removeLast()
        #expect(WinampEQF.decode(truncated) == [])
    }

    @Test func graphFollowsTheCurve() {
        let flat = WinampEqualizerGraph.curve(gains: Array(repeating: 0, count: 10))
        #expect(flat.count == WinampEqualizerGraph.width)
        #expect(Set(flat) == [9])
        let boosted = WinampEqualizerGraph.curve(gains: Array(repeating: 12, count: 10))
        #expect(Set(boosted) == [0])
        let tilt = WinampEqualizerGraph.curve(gains: [-12, -12, -12, -12, -12, 12, 12, 12, 12, 12])
        #expect(tilt.first == 18)
        #expect(tilt.last == 0)
        #expect(tilt.allSatisfy { (0...18).contains($0) })
        #expect(WinampEqualizerGraph.row(for: 0) == 9)
    }

    @Test func autoPicksAPresetFromTheGenre() {
        #expect(WinampAutoEqualizer.preset(forGenre: "Alternative Rock") == .rock)
        #expect(WinampAutoEqualizer.preset(forGenre: "HIP-HOP") == .hipHop)
        #expect(WinampAutoEqualizer.preset(forGenre: "Musique Classique") == .classical)
        #expect(WinampAutoEqualizer.preset(forGenre: "Deep House") == .electronic)
        #expect(WinampAutoEqualizer.preset(forGenre: "Gregorian chant") == nil)
        #expect(WinampAutoEqualizer.preset(forGenre: nil) == nil)
    }
}
