import SwiftUI

/// A system font at a designed point size that follows Dynamic Type.
///
/// For the fixed-layout Wrapped cards and story slides: the text style is inferred from the
/// size, small text grows by at most `maximumGrowth` so a slide still fits, and display text of
/// 40 points or more keeps its size because it is already large.
struct ScaledSystemFont: ViewModifier {
    static let maximumGrowth: CGFloat = 1.6
    static let displayThreshold: CGFloat = 40

    private let size: CGFloat
    private let weight: Font.Weight?
    private let design: Font.Design?
    @ScaledMetric private var scaledSize: CGFloat

    init(size: CGFloat, weight: Font.Weight?, design: Font.Design?) {
        self.size = size
        self.weight = weight
        self.design = design
        _scaledSize = ScaledMetric(wrappedValue: size, relativeTo: Self.textStyle(for: size))
    }

    func body(content: Content) -> some View {
        content.font(.system(size: Self.resolvedSize(designed: size, scaled: scaledSize), weight: weight, design: design))
    }

    static func resolvedSize(designed: CGFloat, scaled: CGFloat) -> CGFloat {
        guard designed < displayThreshold else { return designed }
        return min(max(scaled, designed * 0.85), designed * maximumGrowth)
    }

    static func textStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<13: .caption
        case ..<15: .footnote
        case ..<17: .subheadline
        case ..<20: .body
        case ..<24: .title3
        case ..<28: .title2
        case ..<34: .title
        default: .largeTitle
        }
    }
}

extension View {
    func scaledFont(size: CGFloat, weight: Font.Weight? = nil, design: Font.Design? = nil) -> some View {
        modifier(ScaledSystemFont(size: size, weight: weight, design: design))
    }
}
