import XCTest

final class LocalizationConsistencyTests: XCTestCase {
    private let supportedLanguages = ["en", "pl", "es", "pt-BR"]

    func testEnglishLocalizationMatchesAllSupportedLocalizations() throws {
        let english = try parseStringsFile(named: "en")

        for languageCode in supportedLanguages where languageCode != "en" {
            let localized = try parseStringsFile(named: languageCode)

            let missingInEnglish = Set(localized.values.keys).subtracting(english.values.keys).sorted()
            let missingInLocalized = Set(english.values.keys).subtracting(localized.values.keys).sorted()

            XCTAssertTrue(
                missingInEnglish.isEmpty,
                "Missing English localization keys for \(languageCode): \(missingInEnglish.joined(separator: ", "))"
            )
            XCTAssertTrue(
                missingInLocalized.isEmpty,
                "Missing \(languageCode) localization keys: \(missingInLocalized.joined(separator: ", "))"
            )
        }
    }

    func testSupportedLocalizationsHaveNoDuplicateKeys() throws {
        for languageCode in supportedLanguages {
            let localization = try parseStringsFile(named: languageCode)
            XCTAssertTrue(
                localization.duplicates.isEmpty,
                "Duplicate \(languageCode) keys: \(localization.duplicates)"
            )
        }
    }

    private func parseStringsFile(named languageCode: String) throws -> ParsedStrings {
        if let sourceURL = sourceStringsFileURL(for: languageCode),
           let sourceContents = try? String(contentsOf: sourceURL, encoding: .utf8) {
            return try parseTextualStrings(sourceContents)
        }

        let stringsURL = try bundledStringsFileURL(for: languageCode)
        let data = try Data(contentsOf: stringsURL)
        if let textualContents = String(data: data, encoding: .utf8) {
            return try parseTextualStrings(textualContents)
        }

        // On physical devices, Localizable.strings in app bundle may be compiled as a binary plist.
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard let dictionary = plist as? [String: Any] else {
            throw NSError(
                domain: "LocalizationConsistencyTests",
                code: 260,
                userInfo: [
                    NSLocalizedDescriptionKey: "Unsupported Localizable.strings format for language '\(languageCode)' at \(stringsURL.path)"
                ]
            )
        }
        let values = Dictionary(uniqueKeysWithValues: dictionary.keys.map { ($0, $0) })
        return ParsedStrings(values: values, duplicates: [])
    }

    private func parseTextualStrings(_ contents: String) throws -> ParsedStrings {
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

    private func sourceStringsFileURL(for languageCode: String) -> URL? {
        let fm = FileManager.default
        let sourceFileURL = URL(fileURLWithPath: #filePath)
        let inferredProjectRoot = sourceFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let candidateURLs = [
            inferredProjectRoot.appendingPathComponent("MeasureMe/\(languageCode).lproj/Localizable.strings"),
            URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)
                .appendingPathComponent("MeasureMe/\(languageCode).lproj/Localizable.strings")
        ]

        return candidateURLs.first(where: { fm.fileExists(atPath: $0.path) })
    }

    private func bundledStringsFileURL(for languageCode: String) throws -> URL {
        let subdirectory = "\(languageCode).lproj"
        var checkedBundlePaths: [String] = []
        var seenBundlePaths = Set<String>()
        let bundlesToCheck: [Bundle] = [Bundle.main, Bundle(for: Self.self)] + Bundle.allBundles + Bundle.allFrameworks

        for bundle in bundlesToCheck {
            let bundlePath = bundle.bundlePath
            guard seenBundlePaths.insert(bundlePath).inserted else { continue }
            checkedBundlePaths.append(bundlePath)

            if let resourceURL = bundle.url(
                forResource: "Localizable",
                withExtension: "strings",
                subdirectory: subdirectory
            ) {
                return resourceURL
            }
        }

        let preview = checkedBundlePaths.prefix(10).joined(separator: " | ")
        throw NSError(
            domain: "LocalizationConsistencyTests",
            code: 404,
            userInfo: [
                NSLocalizedDescriptionKey: "Could not find \(subdirectory)/Localizable.strings in loaded bundles. Checked: \(preview)"
            ]
        )
    }

    private struct ParsedStrings {
        let values: [String: String]
        let duplicates: [String]
    }
}
