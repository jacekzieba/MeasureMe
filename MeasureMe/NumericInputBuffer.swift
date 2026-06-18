import Foundation

/// Editable, locale-aware decimal input used by Quick Add's custom keypad.
struct NumericInputBuffer: Equatable {
    private(set) var text: String
    let decimalSeparator: String
    private(set) var replacesInitialValue: Bool
    let maximumFractionDigits: Int

    init(
        value: Double?,
        locale: Locale = .current,
        replaceOnFirstInput: Bool? = nil,
        maximumFractionDigits: Int = 2
    ) {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maximumFractionDigits

        decimalSeparator = formatter.decimalSeparator ?? "."
        text = value.flatMap { formatter.string(from: NSNumber(value: $0)) } ?? ""
        replacesInitialValue = replaceOnFirstInput ?? (value != nil)
        self.maximumFractionDigits = maximumFractionDigits
    }

    var value: Double? {
        guard !text.isEmpty, text != decimalSeparator else { return nil }
        let normalized = text.replacingOccurrences(of: decimalSeparator, with: ".")
        return Double(normalized)
    }

    mutating func appendDigit(_ digit: Int) {
        guard (0...9).contains(digit) else { return }
        let character = String(digit)

        if replacesInitialValue {
            text = character
            replacesInitialValue = false
            return
        }

        if let separatorRange = text.range(of: decimalSeparator) {
            let fraction = text[separatorRange.upperBound...]
            guard fraction.count < maximumFractionDigits else { return }
        } else if text == "0" {
            if digit == 0 { return }
            text = character
            return
        }

        text.append(character)
    }

    mutating func appendDecimalSeparator() {
        if replacesInitialValue {
            text = "0\(decimalSeparator)"
            replacesInitialValue = false
            return
        }

        guard !text.contains(decimalSeparator) else { return }
        if text.isEmpty {
            text = "0\(decimalSeparator)"
        } else {
            text.append(decimalSeparator)
        }
    }

    mutating func deleteBackward() {
        replacesInitialValue = false
        guard !text.isEmpty else { return }
        text.removeLast()
    }

    mutating func clear() {
        text = ""
        replacesInitialValue = false
    }
}

enum QuickAddFieldID: Hashable {
    case metric(MetricKind)
    case custom(String)

    func value(
        metricInputs: [MetricKind: Double?],
        customInputs: [String: Double?]
    ) -> Double? {
        switch self {
        case .metric(let kind):
            return metricInputs[kind] ?? nil
        case .custom(let id):
            return customInputs[id] ?? nil
        }
    }

    func wasEdited(metricKinds: Set<MetricKind>, customIDs: Set<String>) -> Bool {
        switch self {
        case .metric(let kind):
            return metricKinds.contains(kind)
        case .custom(let id):
            return customIDs.contains(id)
        }
    }

    func markEdited(metricKinds: inout Set<MetricKind>, customIDs: inout Set<String>) {
        switch self {
        case .metric(let kind):
            metricKinds.insert(kind)
        case .custom(let id):
            customIDs.insert(id)
        }
    }
}
