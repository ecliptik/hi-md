import Testing
@testable import Minidisc

@Suite("AppIconChoice")
struct AppIconChoiceTests {
    @Test func goldIsThePrimaryIcon() {
        #expect(AppIconChoice.gold.alternateIconName == nil)
        #expect(AppIconChoice(alternateIconName: nil) == .gold)
    }

    @Test func alternatesMatchTheAssetCatalogNames() {
        // These must stay in step with ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES and the .icon files.
        #expect(AppIconChoice.dark.alternateIconName == "AppIconDark")
        #expect(AppIconChoice.light.alternateIconName == "AppIconLight")
    }

    @Test func roundTripsEveryChoice() {
        for choice in AppIconChoice.allCases {
            #expect(AppIconChoice(alternateIconName: choice.alternateIconName) == choice)
        }
    }

    @Test func unknownIconNameFallsBackToGold() {
        #expect(AppIconChoice(alternateIconName: "AppIconRemovedLater") == .gold)
    }
}
