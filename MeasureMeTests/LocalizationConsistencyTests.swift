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

    func testEverySupportedLocalizationHasExactlyTheEnglishKeySetAcrossAllTables() throws {
        for table in tablePaths.keys.sorted() {
            let english = try parseStringsFile(named: "en", table: table)
            let englishKeys = Set(english.values.keys)

            for languageCode in supportedLanguages where languageCode != "en" {
                let localized = try parseStringsFile(named: languageCode, table: table)
                let localizedKeys = Set(localized.values.keys)

                let missing = englishKeys.subtracting(localizedKeys).sorted()
                let unexpected = localizedKeys.subtracting(englishKeys).sorted()

                XCTAssertTrue(
                    missing.isEmpty && unexpected.isEmpty,
                    """
                    Localization coverage mismatch for \(languageCode) in \(table).
                    Missing: \(missing.joined(separator: ", "))
                    Unexpected: \(unexpected.joined(separator: ", "))
                    """
                )
            }
        }
    }

    func testSupportedLocalizationsHaveNoEmptyValuesAcrossAllTables() throws {
        for table in tablePaths.keys.sorted() {
            for languageCode in supportedLanguages {
                let localization = try parseStringsFile(named: languageCode, table: table)
                let emptyKeys = localization.values.compactMap { key, value in
                    value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? key : nil
                }.sorted()

                XCTAssertTrue(
                    emptyKeys.isEmpty,
                    "Empty \(languageCode) translations in \(table): \(emptyKeys.joined(separator: ", "))"
                )
            }
        }
    }

    func testLocalizedFormatArgumentsMatchEnglishAcrossAllTables() throws {
        for table in tablePaths.keys.sorted() {
            let english = try parseStringsFile(named: "en", table: table)

            for languageCode in supportedLanguages where languageCode != "en" {
                let localized = try parseStringsFile(named: languageCode, table: table)

                for key in english.values.keys.sorted() {
                    let englishValue = try XCTUnwrap(english.values[key])
                    let localizedValue = try XCTUnwrap(localized.values[key])
                    let englishSignature = try formatArgumentSignature(in: englishValue)
                    let localizedSignature = try formatArgumentSignature(in: localizedValue)

                    XCTAssertEqual(
                        localizedSignature,
                        englishSignature,
                        """
                        Format arguments differ for \(languageCode) key '\(key)' in \(table).
                        English: \(englishValue)
                        Localized: \(localizedValue)
                        """
                    )
                }
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

    /// `configurationDisplayName` / `description` take a literal that WidgetKit localizes
    /// through the extension's own bundle. Parity testing cannot see a key that is missing
    /// from every locale at once, so check the source literals against the catalog directly.
    func testWidgetGalleryLiteralsExistInEveryLocalization() throws {
        let bundleSource = try String(
            contentsOf: try sourceTreeRootOrSkip().appendingPathComponent("MeasureMeWidget/MeasureMeWidgetBundle.swift"),
            encoding: .utf8
        )

        let pattern = #"\.(?:configurationDisplayName|description)\("([^"]+)"\)"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(bundleSource.startIndex..., in: bundleSource)
        let literals = regex.matches(in: bundleSource, range: range).compactMap { match -> String? in
            guard let r = Range(match.range(at: 1), in: bundleSource) else { return nil }
            return String(bundleSource[r])
        }

        XCTAssertEqual(literals.count, 6, "Expected three widgets \u{00D7} (name + description).")

        for languageCode in supportedLanguages {
            let catalog = try parseStringsFile(named: languageCode, table: "widget.localizable")
            let missing = literals.filter { catalog.values[$0] == nil }.sorted()
            XCTAssertTrue(
                missing.isEmpty,
                "Widget gallery strings missing from \(languageCode): \(missing.joined(separator: " | "))"
            )
        }
    }

    /// The two source-scanning tests read the checked-out tree, which only exists when the
    /// test host can see the Mac filesystem. On a physical device those paths are absent, so
    /// resolve the root defensively and let the caller skip instead of failing.
    /// Returns nil rather than unwrapping: `XCTUnwrap` records a failure before it throws,
    /// which would defeat the skip below.
    private func repositoryRoot() -> URL? {
        // .../MeasureMeTests/LocalizationConsistencyTests.swift -> repository root
        let fm = FileManager.default
        let candidates = [
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent(),
            URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)
        ]
        return candidates.first { fm.fileExists(atPath: $0.appendingPathComponent("MeasureMeTests").path) }
    }

    private func sourceTreeRootOrSkip() throws -> URL {
        guard let root = repositoryRoot() else {
            throw XCTSkip("Repository sources are not reachable from this test host.")
        }
        return root
    }


    /// Every key the app asks for as a literal must exist in the catalog. Without this,
    /// deleting an orphaned key — or renaming one — silently ships the raw key text as UI.
    func testEveryLiteralKeyRequestedByTheAppExistsInEnglish() throws {
        // Format fragments and interpolated keys, which are resolved elsewhere or by design.
        let expectedMisses: Set<String> = [
            "%", "%@ (%@)", "0", "\u{2014}",
            "streak.detail.motivational.\\(motivationalTier).title",
            "streak.detail.motivational.\\(motivationalTier).body",
            "Send diagnostics to measureme.approve254@passmail.net"
        ]

        let sourceRoot = try sourceTreeRootOrSkip()
        let sourceRoots = ["MeasureMe", "MeasureMeWidget", "MeasureMeWatch Watch App", "MeasureMeWatchComplications"]
        var requested = Set<String>()
        let callPattern = try NSRegularExpression(
            pattern: #"AppLocalization\.(?:string|plural)\(\s*"((?:[^"\\]|\\.)*)""#
        )

        for root in sourceRoots {
            let rootURL = sourceRoot.appendingPathComponent(root)
            guard let walker = FileManager.default.enumerator(at: rootURL, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker where url.pathExtension == "swift" {
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                let range = NSRange(text.startIndex..., in: text)
                for match in callPattern.matches(in: text, range: range) {
                    if let r = Range(match.range(at: 1), in: text) {
                        // The catalog parser folds typographic punctuation, so the requested
                        // keys have to go through the same normalisation to compare.
                        requested.insert(normalizedLocalizationKey(String(text[r])))
                    }
                }
            }
        }

        XCTAssertGreaterThan(requested.count, 900, "Key extraction looks broken, not the catalog.")

        let english = try parseStringsFile(named: "en", table: "app.localizable")
        let missing = requested.subtracting(english.values.keys).subtracting(expectedMisses).sorted()

        XCTAssertTrue(missing.isEmpty, "Keys requested in code but absent from en.lproj: \(missing.joined(separator: " | "))")
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
        // Key normalization (apostrophe/dash unification, mojibake repair) can map two
        // distinct raw keys onto the same normalized key. Merge last-wins to mirror the
        // textual parser instead of trapping like `Dictionary(uniqueKeysWithValues:)`.
        let values = Dictionary(
            dictionary.map { key, value in
                let normalizedKey = normalizedLocalizationKey(key)
                let normalizedValue = normalizedConsistencyValue(String(describing: value))
                return (normalizedKey, normalizedValue)
            },
            uniquingKeysWith: { _, latest in latest }
        )
        return ParsedStrings(values: values, duplicates: [])
    }

    private func parseTextualStrings(_ contents: String) throws -> ParsedStrings {
        let regex = try XCTUnwrap(
            NSRegularExpression(
                pattern: "^\"((?:\\\\.|[^\"\\\\])*)\"\\s*=\\s*\"((?:\\\\.|[^\"\\\\])*)\";",
                options: [.anchorsMatchLines, .dotMatchesLineSeparators]
            )
        )

        var values: [String: String] = [:]
        var occurrences: [String: Int] = [:]

        let range = NSRange(contents.startIndex..<contents.endIndex, in: contents)
        regex.enumerateMatches(in: contents, options: [], range: range) { match, _, _ in
            guard let match,
                  let keyRange = Range(match.range(at: 1), in: contents) else { return }
            let rawKey = String(contents[keyRange])
            let key = normalizedLocalizationKey(rawKey)
            let rawValue = if let valueRange = Range(match.range(at: 2), in: contents) {
                String(contents[valueRange])
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

        if let nestedResourceURL = nestedBundledStringsFileURL(
            languageCode: languageCode,
            resourceName: resourceName,
            table: table
        ) {
            return nestedResourceURL
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

    private func nestedBundledStringsFileURL(
        languageCode: String,
        resourceName: String,
        table: String
    ) -> URL? {
        let suffix = "/\(languageCode).lproj/\(resourceName).strings"
        let roots = [Bundle.main.bundleURL, Bundle(for: Self.self).bundleURL]
        var candidates: [URL] = []

        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for case let url as URL in enumerator where url.path.hasSuffix(suffix) {
                candidates.append(url)
            }
        }

        return candidates
            .filter { nestedResourceMatchesTable($0, table: table) }
            .sorted { $0.path < $1.path }
            .first
    }

    private func nestedResourceMatchesTable(_ url: URL, table: String) -> Bool {
        let path = url.path
        switch table {
        case "widget.localizable":
            return path.contains("MeasureMeWidget.appex/")
        case "watch.watch":
            return path.contains("/Watch/") && path.contains(".app/")
        case "complication.localizable":
            return path.contains("MeasureMeWatchComplicationsExtension.appex/")
        default:
            return !path.contains(".appex/") && !path.contains("/Watch/")
        }
    }

    private func normalizedLocalizationKey(_ key: String) -> String {
        var best = key

        while let repaired = repairedMojibakeVariant(for: best),
              suspiciousCharacterScore(for: repaired) < suspiciousCharacterScore(for: best) {
            best = repaired
        }

        return best
            .replacingOccurrences(of: "\\n", with: "\n")
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

    private func formatArgumentSignature(in value: String) throws -> [String] {
        let regex = try XCTUnwrap(
            NSRegularExpression(
                pattern: "(?<!%)%(?!%)(?:\\d+\\$)?[-+#0]*(?:\\*|\\d+)?(?:\\.(?:\\*|\\d+))?((?:hh|h|ll|l|q|z|t|j)?[@diuoxXfFeEgGaAcCsSp])"
            )
        )
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.matches(in: value, range: range).compactMap { match in
            guard let tokenRange = Range(match.range(at: 1), in: value) else { return nil }
            return String(value[tokenRange]).lowercased()
        }.sorted()
    }

    private struct ParsedStrings {
        let values: [String: String]
        let duplicates: [String]
    }
}
