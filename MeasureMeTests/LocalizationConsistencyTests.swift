import XCTest

final class LocalizationConsistencyTests: XCTestCase {
    private let supportedLanguages = ["en", "pl", "es", "de", "fr", "pt-BR"]
    private let tablePaths: [String: String] = [
        "app.localizable": "MeasureMe/%@.lproj/Localizable.strings",
        "app.intents": "MeasureMe/%@.lproj/AppIntents.strings",
        "app.shortcuts": "MeasureMe/%@.lproj/AppShortcuts.strings",
        "app.infoPlist": "MeasureMe/%@.lproj/InfoPlist.strings",
        "widget.localizable": "MeasureMeWidget/%@.lproj/Localizable.strings",
        "watch.watch": "MeasureMeWatch Watch App/%@.lproj/Watch.strings",
        "complication.localizable": "MeasureMeWatchComplications/%@.lproj/Localizable.strings"
    ]

    func testEnglishLocalizationMatchesAllSupportedLocalizationsAcrossAllTables() throws {
        for table in tablePaths.keys.sorted() {
            let english = try parseStringsFile(named: "en", table: table)

            for languageCode in supportedLanguages where languageCode != "en" {
                let localized = try parseStringsFile(named: languageCode, table: table)

                let missingInLocalized = Set(english.values.keys).subtracting(localized.values.keys).sorted()

                XCTAssertTrue(
                    missingInLocalized.isEmpty,
                    "Missing \(languageCode) localization keys for \(table): \(missingInLocalized.joined(separator: ", "))"
                )
            }
        }
    }

    func testSupportedLocalizationsHaveNoDuplicateKeysAcrossAllTables() throws {
        for table in tablePaths.keys.sorted() {
            for languageCode in supportedLanguages {
                let localization = try parseStringsFile(named: languageCode, table: table)
                XCTAssertTrue(
                    localization.duplicates.isEmpty,
                    "Duplicate \(languageCode) keys in \(table): \(localization.duplicates)"
                )
            }
        }
    }

    func testSharedKeysUseConsistentTranslationsAcrossTables() throws {
        let allowedInconsistentKeys: Set<String> = [
            // "Metric" is used both as a unit system label and as a noun for a tracked measurement.
            "Metric"
        ]

        for languageCode in supportedLanguages where languageCode != "en" {
            var translationsByKey: [String: [String: String]] = [:]

            for table in tablePaths.keys.sorted() {
                let localization = try parseStringsFile(named: languageCode, table: table)
                for (key, value) in localization.values {
                    guard !allowedInconsistentKeys.contains(key) else { continue }
                    translationsByKey[key, default: [:]][table] = normalizedConsistencyValue(value)
                }
            }

            for key in translationsByKey.keys.sorted() {
                let valuesByTable = translationsByKey[key, default: [:]]
                let distinctValues = Set(valuesByTable.values)
                guard distinctValues.count > 1 else { continue }

                let rendered = valuesByTable
                    .sorted(by: { $0.key < $1.key })
                    .map { "\($0.key)=\($0.value)" }
                    .joined(separator: " | ")

                XCTFail("Inconsistent \(languageCode) translations for shared key '\(key)': \(rendered)")
            }
        }
    }

    private func parseStringsFile(named languageCode: String, table: String) throws -> ParsedStrings {
        if let sourceURL = sourceStringsFileURL(for: languageCode, table: table),
           let sourceContents = try? String(contentsOf: sourceURL, encoding: .utf8) {
            return try parseTextualStrings(sourceContents)
        }

        let stringsURL = try bundledStringsFileURL(for: languageCode, table: table)
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
        let values = Dictionary(uniqueKeysWithValues: dictionary.map { key, value in
            let normalizedKey = normalizedLocalizationKey(key)
            let normalizedValue = normalizedConsistencyValue(String(describing: value))
            return (normalizedKey, normalizedValue)
        })
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
            let rawKey = String(line[keyRange])
            let key = normalizedLocalizationKey(rawKey)
            let rawValue = if let valueRange = Range(match.range(at: 2), in: line) {
                String(line[valueRange])
            } else {
                rawKey
            }
            values[key] = normalizedConsistencyValue(rawValue)
            occurrences[rawKey, default: 0] += 1
        }

        let duplicates = occurrences.compactMap { key, count in
            count > 1 ? key : nil
        }.sorted()

        return ParsedStrings(values: values, duplicates: duplicates)
    }

    private func sourceStringsFileURL(for languageCode: String, table: String) -> URL? {
        let fm = FileManager.default
        let sourceFileURL = URL(fileURLWithPath: #filePath)
        let inferredProjectRoot = sourceFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        guard let template = tablePaths[table] else { return nil }
        let relativePath = String(format: template, languageCode)

        let candidateURLs = [
            inferredProjectRoot.appendingPathComponent(relativePath),
            URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)
                .appendingPathComponent(relativePath)
        ]

        return candidateURLs.first(where: { fm.fileExists(atPath: $0.path) })
    }

    private func bundledStringsFileURL(for languageCode: String, table: String) throws -> URL {
        let subdirectory = "\(languageCode).lproj"
        let resourceName: String
        switch table {
        case "app.intents":
            resourceName = "AppIntents"
        case "app.shortcuts":
            resourceName = "AppShortcuts"
        case "app.infoPlist":
            resourceName = "InfoPlist"
        case "watch.watch":
            resourceName = "Watch"
        default:
            resourceName = "Localizable"
        }
        var checkedBundlePaths: [String] = []
        var seenBundlePaths = Set<String>()
        let bundlesToCheck: [Bundle] = [Bundle.main, Bundle(for: Self.self)] + Bundle.allBundles + Bundle.allFrameworks

        for bundle in bundlesToCheck {
            let bundlePath = bundle.bundlePath
            guard seenBundlePaths.insert(bundlePath).inserted else { continue }
            checkedBundlePaths.append(bundlePath)

            if let resourceURL = bundle.url(
                forResource: resourceName,
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
                NSLocalizedDescriptionKey: "Could not find \(subdirectory)/\(resourceName).strings in loaded bundles. Checked: \(preview)"
            ]
        )
    }

    private func normalizedLocalizationKey(_ key: String) -> String {
        var best = key

        while let repaired = repairedMojibakeVariant(for: best),
              suspiciousCharacterScore(for: repaired) < suspiciousCharacterScore(for: best) {
            best = repaired
        }

        return best
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
            .replacingOccurrences(of: "–", with: "—")
            .replacingOccurrences(of: "‑", with: "-")
    }

    private func repairedMojibakeVariant(for string: String) -> String? {
        let encodings: [String.Encoding] = [.windowsCP1252, .isoLatin1]

        for encoding in encodings {
            guard let data = string.data(using: encoding),
                  let repaired = String(data: data, encoding: .utf8),
                  repaired != string else {
                continue
            }
            return repaired
        }

        return nil
    }

    private func suspiciousCharacterScore(for string: String) -> Int {
        let suspiciousTokens = ["Ã", "Â", "â", "ð", "�"]
        return suspiciousTokens.reduce(into: 0) { score, token in
            score += string.components(separatedBy: token).count - 1
        }
    }

    private func normalizedConsistencyValue(_ value: String) -> String {
        normalizedLocalizationKey(value)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct ParsedStrings {
        let values: [String: String]
        let duplicates: [String]
    }
}
