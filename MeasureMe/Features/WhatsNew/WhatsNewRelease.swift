// WhatsNewRelease.swift
//
// **WhatsNewRelease**
// The catalogue of "what we shipped" entries, one per marketing version.
//
// Adding a release means adding an entry here plus its `whatsNew.<version>.*`
// strings in every `Localizable.strings`. A version with no entry shows nothing —
// that is the intended behaviour for patch releases nobody needs to be told about.
//
import Foundation

/// `nonisolated` for the same reason as `WhatsNewGate`: the target defaults to `@MainActor`,
/// which would isolate the `Equatable` conformance and make it unusable off the main actor —
/// a hard error under the Swift 6 language mode.
nonisolated struct WhatsNewRelease: Equatable, Sendable, Identifiable {
    var id: String { version }
    /// Marketing version this entry describes, matching `CFBundleShortVersionString`.
    let version: String
    let highlights: [Highlight]

    struct Highlight: Equatable, Sendable, Identifiable {
        /// Stable across launches so `ForEach` does not rebuild rows on every render.
        var id: String { titleKey }
        let systemImage: String
        let titleKey: String
        let messageKey: String
    }

    /// Newest first. Only the entry matching the running version is ever presented.
    static let catalogue: [WhatsNewRelease] = [
        WhatsNewRelease(
            version: "1.5.4",
            highlights: [
                Highlight(
                    systemImage: "figure.stand",
                    titleKey: "whatsNew.1_5_4.bodyModel.title",
                    messageKey: "whatsNew.1_5_4.bodyModel.message"
                ),
                Highlight(
                    systemImage: "arrow.left.and.right",
                    titleKey: "whatsNew.1_5_4.compare.title",
                    messageKey: "whatsNew.1_5_4.compare.message"
                ),
                Highlight(
                    systemImage: "checkmark.seal",
                    titleKey: "whatsNew.1_5_4.accuracy.title",
                    messageKey: "whatsNew.1_5_4.accuracy.message"
                )
            ]
        )
    ]

    static func release(for version: String) -> WhatsNewRelease? {
        catalogue.first { $0.version == version }
    }
}
