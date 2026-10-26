import Foundation
import Testing
@testable import Minidisc

@Suite("Add Music browser search")
struct MusicFolderFilterTests {
    private let english = Locale(identifier: "en_US")

    private func folders(_ names: [String]) -> [MusicFolderItem] {
        names.enumerated().map { index, name in
            MusicFolderItem(id: "f\(index)", name: name, kind: .folder(.directory(id: "f\(index)")))
        }
    }

    private func names(_ items: [MusicFolderItem]) -> [String] { items.map(\.name) }

    @Test func blankQueriesKeepEverythingInOrder() {
        let filter = MusicFolderFilter(items: folders(["ABBA", "Björk", "Can"]), locale: english)
        #expect(names(filter.matches("")) == ["ABBA", "Björk", "Can"])
        #expect(names(filter.matches("   ")) == ["ABBA", "Björk", "Can"])
        #expect(!MusicFolderFilter.isActive(" \t"))
        #expect(MusicFolderFilter.isActive(" a "))
    }

    @Test func ignoresCaseAndAccents() {
        let filter = MusicFolderFilter(items: folders(["Beyoncé", "BJÖRK", "Sigur Rós", "Motörhead", "Can"]), locale: english)
        #expect(names(filter.matches("beyonce")) == ["Beyoncé"])
        #expect(names(filter.matches("björk")) == ["BJÖRK"])
        #expect(names(filter.matches("ROS")) == ["Sigur Rós"])
        #expect(names(filter.matches("motorhead")) == ["Motörhead"])
        // An accent typed in the query is ignored too.
        #expect(names(filter.matches("ncé")) == ["Beyoncé"])
        #expect(names(filter.matches("é")) == ["Beyoncé", "Motörhead"])
    }

    @Test func matchesAnywhereInTheName() {
        let filter = MusicFolderFilter(items: folders(["1999 - Midnite Vultures", "Odelay", "Sea Change"]), locale: english)
        #expect(names(filter.matches("vult")) == ["1999 - Midnite Vultures"])
        #expect(names(filter.matches("change")) == ["Sea Change"])
        #expect(filter.matches("zzz").isEmpty)
    }

    @Test func everyWordMustMatch() {
        let filter = MusicFolderFilter(items: folders(["ABBA - Gold", "ABBA - Arrival", "Gold Panda"]), locale: english)
        #expect(names(filter.matches("abba gold")) == ["ABBA - Gold"])
        #expect(names(filter.matches("gold  abba")) == ["ABBA - Gold"])
        #expect(names(filter.matches("gold")) == ["ABBA - Gold", "Gold Panda"])
    }

    @Test func japaneseAndChineseNamesMatchAsTyped() {
        let filter = MusicFolderFilter(items: folders(["亜蘭知子", "竹内まりや", "山下達郎", "アラン", "王菲"]), locale: Locale(identifier: "ja_JP"))
        #expect(names(filter.matches("亜蘭")) == ["亜蘭知子"])
        #expect(names(filter.matches("まりや")) == ["竹内まりや"])
        #expect(names(filter.matches("王菲")) == ["王菲"])
        // Half-width katakana finds the full-width name.
        #expect(names(filter.matches("ｱﾗﾝ")) == ["アラン"])
        #expect(filter.matches("達郎 竹内").isEmpty)
    }

    @Test func fullWidthLatinMatches() {
        let filter = MusicFolderFilter(items: folders(["ＡＢＢＡ", "Can"]), locale: english)
        #expect(names(filter.matches("abba")) == ["ＡＢＢＡ"])
    }

    @Test func largeFoldersFilterQuickly() {
        let items = folders((0..<20_000).map { "Artist \($0) Ünïcödé" })
        let filter = MusicFolderFilter(items: items, locale: english)
        let clock = ContinuousClock()
        var count = 0
        let elapsed = clock.measure {
            for query in ["a", "ar", "art", "arti", "artist 1", "artist 19", "artist 199", "unicode"] {
                count += filter.matches(query).count
            }
        }
        #expect(count > 0)
        // Eight keystrokes over 20,000 names; generous so a slow simulator doesn't flake.
        #expect(elapsed < .seconds(2))
    }

    @Test func playAndAddTakeTheShownSelectionOrEverythingShown() {
        let shown = folders(["A", "B", "C"])
        #expect(names(MusicFolderFilter.chosen(from: shown, selection: [])) == ["A", "B", "C"])
        #expect(names(MusicFolderFilter.chosen(from: shown, selection: ["f1"])) == ["B"])
        #expect(MusicFolderFilter.chosen(from: shown, selection: [".."]).isEmpty)
        #expect(MusicFolderFilter.chosen(from: [], selection: []).isEmpty)
    }

    @Test func returnOpensTheSelectionOrTheFirstMatch() {
        let shown = folders(["A", "B", "C"])
        #expect(MusicFolderFilter.returnTarget(shown: shown, selection: []) == ["f0"])
        #expect(MusicFolderFilter.returnTarget(shown: shown, selection: ["f2"]) == ["f2"])
        #expect(MusicFolderFilter.returnTarget(shown: shown, selection: ["gone"]) == ["f0"])
        #expect(MusicFolderFilter.returnTarget(shown: [], selection: []) == nil)
    }

    @Test func arrowsMoveThroughTheShownRows() {
        let rows = ["..", "f0", "f1", "f2"]
        #expect(MusicFolderFilter.movedSelection(rowIDs: rows, selection: [], by: 1) == "..")
        #expect(MusicFolderFilter.movedSelection(rowIDs: rows, selection: [], by: -1) == "f2")
        #expect(MusicFolderFilter.movedSelection(rowIDs: rows, selection: ["f0"], by: 1) == "f1")
        #expect(MusicFolderFilter.movedSelection(rowIDs: rows, selection: ["f0"], by: -1) == "..")
        #expect(MusicFolderFilter.movedSelection(rowIDs: rows, selection: ["f2"], by: 1) == "f2")
        #expect(MusicFolderFilter.movedSelection(rowIDs: rows, selection: [".."], by: -1) == "..")
        #expect(MusicFolderFilter.movedSelection(rowIDs: rows, selection: ["f0", "f2"], by: -1) == "..")
        #expect(MusicFolderFilter.movedSelection(rowIDs: rows, selection: ["f0", "f1"], by: 1) == "f2")
        #expect(MusicFolderFilter.movedSelection(rowIDs: [], selection: [], by: 1) == nil)
    }
}
