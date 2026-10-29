import XCTest
@testable import OneTapHeadacheTracker

final class LocalizationTests: XCTestCase {
    private let languages = ["de", "ja", "es", "it", "pl", "hu", "fi", "nb", "da", "ru", "pt-PT", "uk", "fr"]

    private func bundle(_ language: String) -> Bundle? {
        for host in [Bundle.main] + Bundle.allBundles {
            if let path = host.path(forResource: language, ofType: "lproj"),
               let localized = Bundle(path: path) {
                return localized
            }
        }
        return nil
    }

    func testEveryLanguageShips() {
        for language in languages {
            XCTAssertNotNil(bundle(language), "\(language).lproj is missing")
        }
    }

    func testRussianPluralForms() throws {
        let russian = try XCTUnwrap(bundle("ru"))
        let locale = Locale(identifier: "ru")
        let one = 1
        let few = 3
        let many = 5
        XCTAssertEqual(String(localized: "You have logged \(one) headaches.", bundle: russian, locale: locale), "Вы записали 1 приступ головной боли.")
        XCTAssertEqual(String(localized: "You have logged \(few) headaches.", bundle: russian, locale: locale), "Вы записали 3 приступа головной боли.")
        XCTAssertEqual(String(localized: "You have logged \(many) headaches.", bundle: russian, locale: locale), "Вы записали 5 приступов головной боли.")
    }

    func testGermanPrimaryActionIsTranslated() throws {
        let german = try XCTUnwrap(bundle("de"))
        XCTAssertEqual(String(localized: "Log headache", bundle: german), "Kopfschmerzen erfassen")
    }
}
