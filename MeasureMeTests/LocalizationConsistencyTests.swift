import XCTest

final class LocalizationConsistencyTests: XCTestCase {
    func testEnglishAndPolishLocalizationsHaveMatchingKeys() throws {
        let en = try parseStringsFile(named: "en")
        let pl = try parseStringsFile(named: "pl")

        let missingInEnglish = Set(pl.values.keys).subtracting(en.values.keys).sorted()
        let missingInPolish = Set(en.values.keys).subtracting(pl.values.keys).sorted()

        XCTAssertTrue(
            missingInEnglish.isEmpty,
            "Missing English localization keys: \(missingInEnglish.joined(separator: ", "))"
        )
        XCTAssertTrue(
            missingInPolish.isEmpty,
            "Missing Polish localization keys: \(missingInPolish.joined(separator: ", "))"
        )
    }

    func testEnglishAndPolishLocalizationsHaveNoDuplicateKeys() throws {
        let en = try parseStringsFile(named: "en")
        let pl = try parseStringsFile(named: "pl")

        XCTAssertTrue(en.duplicates.isEmpty, "Duplicate English keys: \(en.duplicates)")
        XCTAssertTrue(pl.duplicates.isEmpty, "Duplicate Polish keys: \(pl.duplicates)")
    }

    private func parseStringsFile(named languageCode: String) throws -> ParsedStrings {
        let path = "/Users/jacek/Desktop/MeasureMe/MeasureMe/\(languageCode).lproj/Localizable.strings"
        let contents = try String(contentsOfFile: path, encoding: .utf8)
        let regex = try XCTUnwrap(
            NSRegularExpression(pattern: "^\"((?:\\\\.|[^\"\\\\])*)\"\\s*=\\s*\"((?:\\\\.|[^\"\\\\])*)\";", options: [])
        )

        var values: [String: String] = [:]
        var occurrences: [String: Int] = [:]

        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = regex.firstMatch(in: line, options: [], range: range),
                  let keyRange = Range(match.range(at: 1), in: line) else { continue }
            let key = String(line[keyRange])
            values[key] = key
            occurrences[key, default: 0] += 1
        }

        let duplicates = occurrences.compactMap { key, count in
            count > 1 ? key : nil
        }.sorted()

        return ParsedStrings(values: values, duplicates: duplicates)
    }

    private struct ParsedStrings {
        let values: [String: String]
        let duplicates: [String]
    }
}
