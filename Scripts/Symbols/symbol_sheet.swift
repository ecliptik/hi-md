import AppKit
import SwiftUI

// Renders a comparison sheet of the compiled `minidisc` symbols next to the sidebar's system symbols:
// every weight against `square`, the three scales, and 16-44 pt rows in light, dark and the gold tint.
//
// Usage (macOS), with the catalog compiled into a throwaway bundle:
//   mkdir -p /tmp/Sym.bundle/Contents/Resources
//   xcrun actool --compile /tmp/Sym.bundle/Contents/Resources --platform macosx \
//       --minimum-deployment-target 27.0 Minidisc/Assets.xcassets
//   swiftc -O -o /tmp/symbol_sheet Scripts/Symbols/symbol_sheet.swift
//   /tmp/symbol_sheet /tmp/Sym.bundle /tmp/minidisc-sheet.png
let bundlePath = CommandLine.arguments[1]
let output = CommandLine.arguments[2]
let bundle = Bundle(path: bundlePath)!
let gold = Color(red: 0.80, green: 0.62, blue: 0.24)

enum Glyph: Hashable {
    case system(String), custom(String), emoji
}

let family: [Glyph] = [.emoji, .custom("minidisc"), .custom("minidisc.fill"), .system("square.stack"), .system("square.stack.fill"),
                       .system("music.microphone"), .system("music.note"), .system("guitars"), .system("heart"),
                       .system("arrow.down.circle"), .system("clock"), .system("opticaldisc")]

struct GlyphView: View {
    let glyph: Glyph
    let size: CGFloat
    var body: some View {
        switch glyph {
        case .system(let n): Image(systemName: n)
        case .custom(let n): Image(n, bundle: bundle)
        case .emoji: Text("\u{1F4BD}").font(.system(size: size * 0.9))
        }
    }
}

struct Row: View {
    let size: CGFloat
    let weight: Font.Weight
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: size * 0.6) {
            Text("\(Int(size)) pt").font(.system(size: 11, design: .monospaced)).frame(width: 44, alignment: .leading)
            ForEach(family, id: \.self) { g in
                GlyphView(glyph: g, size: size).frame(minWidth: size * 1.3)
            }
            Text("Albums").font(.system(size: size, weight: weight))
        }
        .font(.system(size: size, weight: weight))
    }
}

struct Sidebar: View {
    let weight: Font.Weight
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Artists", systemImage: "music.microphone")
            Label("Albums", image: ImageResource(name: "minidisc", bundle: bundle))
            Label("Albums (old)", systemImage: "square.stack")
            Label("Songs", systemImage: "music.note")
            Label("Genres", systemImage: "guitars")
            Label("Favorites", systemImage: "heart")
            Label("Downloads", systemImage: "arrow.down.circle")
            Label("Recently Added", systemImage: "clock")
        }
        .font(.system(size: 13, weight: weight))
        .padding(10)
    }
}

struct Panel: View {
    let dark: Bool
    let tinted: Bool
    let weight: Font.Weight
    let title: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 13, weight: .bold))
            HStack(alignment: .top, spacing: 30) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach([16, 20, 28, 44] as [CGFloat], id: \.self) { Row(size: $0, weight: weight) }
                }
                Sidebar(weight: weight)
            }
        }
        .foregroundStyle(tinted ? gold : (dark ? Color.white : Color.black))
        .padding(16)
        .background(dark ? Color(white: 0.12) : Color.white)
        .environment(\.colorScheme, dark ? .dark : .light)
    }
}

struct Big: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 24) {
            ForEach([Font.Weight.ultraLight, .thin, .light, .regular, .medium, .semibold, .bold, .heavy, .black], id: \.self) { w in
                VStack(spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("H")
                        Image("minidisc", bundle: bundle)
                        Image(systemName: "square")
                    }
                    .font(.system(size: 64, weight: w))
                    .overlay(alignment: .bottom) { Rectangle().fill(.red.opacity(0.4)).frame(height: 1).offset(y: -15) }
                    HStack(spacing: 2) {
                        Image("minidisc.fill", bundle: bundle)
                        Image(systemName: "square.stack.fill")
                    }.font(.system(size: 40, weight: w))
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .foregroundStyle(.black)
    }
}

struct Scales: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 20) {
            ForEach([Image.Scale.small, .medium, .large], id: \.self) { s in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Albums")
                    Image("minidisc", bundle: bundle).imageScale(s)
                    Image(systemName: "square.stack").imageScale(s)
                    Image(systemName: "music.microphone").imageScale(s)
                    Image(systemName: "heart").imageScale(s)
                }
            }
        }
        .font(.system(size: 28))
        .padding(16)
        .background(Color.white)
        .foregroundStyle(.black)
    }
}

struct Sheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("minidisc custom symbol vs. the sidebar family. Columns: 💽, minidisc, minidisc.fill, square.stack, square.stack.fill, music.microphone, music.note, guitars, heart, arrow.down.circle, clock, opticaldisc")
                .font(.system(size: 12)).padding(16).foregroundStyle(.black).background(Color.white)
            Big()
            Scales()
            Panel(dark: false, tinted: false, weight: .regular, title: "Light · Regular")
            Panel(dark: false, tinted: false, weight: .semibold, title: "Light · Semibold")
            Panel(dark: true, tinted: false, weight: .regular, title: "Dark · Regular")
            Panel(dark: true, tinted: false, weight: .semibold, title: "Dark · Semibold")
            Panel(dark: false, tinted: true, weight: .regular, title: "Light · gold tint · Regular")
            Panel(dark: true, tinted: true, weight: .semibold, title: "Dark · gold tint · Semibold")
        }
        .background(Color.white)
        .fixedSize()
    }
}

MainActor.assumeIsolated {
    let renderer = ImageRenderer(content: Sheet())
    renderer.scale = 2
    guard let cg = renderer.cgImage else { fatalError("render failed") }
    let rep = NSBitmapImageRep(cgImage: cg)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
    print("wrote \(output) \(cg.width)x\(cg.height)")
}
