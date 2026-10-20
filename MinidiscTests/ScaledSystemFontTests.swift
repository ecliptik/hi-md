import SwiftUI
import Testing
@testable import Minidisc

@Suite("Scaled Wrapped fonts")
struct ScaledSystemFontTests {
    @Test func smallTextGrowsWithinLimits() {
        #expect(ScaledSystemFont.resolvedSize(designed: 14, scaled: 14) == 14)
        #expect(ScaledSystemFont.resolvedSize(designed: 14, scaled: 18) == 18)
        #expect(ScaledSystemFont.resolvedSize(designed: 14, scaled: 40) == 14 * ScaledSystemFont.maximumGrowth)
        #expect(ScaledSystemFont.resolvedSize(designed: 20, scaled: 10) == 17)
    }

    @Test func displayTextKeepsItsSize() {
        #expect(ScaledSystemFont.resolvedSize(designed: 96, scaled: 200) == 96)
        #expect(ScaledSystemFont.resolvedSize(designed: 40, scaled: 60) == 40)
    }

    @Test func textStylesFollowSize() {
        #expect(ScaledSystemFont.textStyle(for: 12) == .caption)
        #expect(ScaledSystemFont.textStyle(for: 16) == .subheadline)
        #expect(ScaledSystemFont.textStyle(for: 22) == .title3)
        #expect(ScaledSystemFont.textStyle(for: 30) == .title)
    }
}
