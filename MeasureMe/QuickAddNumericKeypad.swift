import SwiftUI

struct QuickAddNumericKeypad: View {
    let title: String
    let unit: String
    let valueText: String
    let decimalSeparator: String
    let onDigit: (Int) -> Void
    let onDecimalSeparator: () -> Void
    let onDelete: () -> Void
    let onClear: () -> Void
    let onDone: () -> Void

    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        VStack(spacing: verticalSizeClass == .compact ? 6 : 8) {
            header

            LazyVGrid(columns: columns, spacing: verticalSizeClass == .compact ? 6 : 8) {
                ForEach(1...9, id: \.self) { digit in
                    digitKey(digit)
                }

                keypadButton(
                    label: decimalSeparator,
                    accessibilityLabel: AppLocalization.string("quickadd.keypad.decimal"),
                    accessibilityHint: AppLocalization.string("quickadd.keypad.decimal.hint")
                ) {
                    onDecimalSeparator()
                    Haptics.selection()
                }
                .accessibilityIdentifier("quickadd.keypad.decimal")

                digitKey(0)

                keypadButton(
                    systemImage: "delete.left",
                    accessibilityLabel: AppLocalization.string("Delete"),
                    accessibilityHint: AppLocalization.string("quickadd.keypad.delete.hint")
                ) {
                    onDelete()
                }
                .buttonRepeatBehavior(.enabled)
                .accessibilityAction(named: AppLocalization.string("quickadd.keypad.clear")) {
                    onClear()
                }
                .accessibilityIdentifier("quickadd.keypad.delete")
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, verticalSizeClass == .compact ? 6 : 10)
        .background(keypadBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(colorSchemeContrast == .increased ? AppColorRoles.borderStrong : AppColorRoles.borderSubtle)
                .frame(height: colorSchemeContrast == .increased ? 2 : 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(AppLocalization.string("quickadd.keypad.title"))
        .accessibilityIdentifier("quickadd.keypad")
    }

    private var keypadBackground: Color {
        if colorScheme == .dark {
            return colorSchemeContrast == .increased ? Color(uiColor: .black) : Color(uiColor: .systemGray6)
        }
        return colorSchemeContrast == .increased ? Color(uiColor: .systemGray3) : Color(uiColor: .systemGray4)
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColorRoles.textPrimary)
                    .lineLimit(1)

                Text("\(valueText.isEmpty ? "—" : valueText) \(unit)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AppColorRoles.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                Haptics.light()
                onDone()
            } label: {
                Text(AppLocalization.string("Done"))
                    .font(.body.weight(.semibold))
                    .frame(minWidth: 72, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.appAccent)
            .accessibilityHint(AppLocalization.string("quickadd.keypad.done.hint"))
            .accessibilityIdentifier("quickadd.keypad.done")
        }
        .frame(minHeight: 44)
    }

    private func digitKey(_ digit: Int) -> some View {
        keypadButton(
            label: String(digit),
            accessibilityLabel: String(digit),
            accessibilityHint: AppLocalization.string("quickadd.keypad.digit.hint")
        ) {
            onDigit(digit)
            Haptics.selection()
        }
        .accessibilityIdentifier("quickadd.keypad.digit.\(digit)")
    }

    private func keypadButton(
        label: String? = nil,
        systemImage: String? = nil,
        accessibilityLabel: String,
        accessibilityHint: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if let label {
                    Text(label)
                        .font(.title2.monospacedDigit().weight(.medium))
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.title3.weight(.medium))
                }
            }
        }
        .buttonStyle(KeypadKeyButtonStyle(minHeight: verticalSizeClass == .compact ? 44 : 52))
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }
}

private struct KeypadKeyButtonStyle: ButtonStyle {
    let minHeight: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

        configuration.label
            .foregroundStyle(AppColorRoles.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: minHeight)
            .background(
                shape.fill(keyBackground(isPressed: configuration.isPressed))
            )
            .overlay {
                shape.strokeBorder(
                    AppColorRoles.borderStrong.opacity(colorSchemeContrast == .increased ? 1 : 0.82),
                    lineWidth: colorSchemeContrast == .increased ? 2 : 1
                )
            }
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.32 : 0.14),
                radius: configuration.isPressed ? 1 : 2,
                x: 0,
                y: configuration.isPressed ? 0 : 1
            )
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.98)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: configuration.isPressed)
            .contentShape(Rectangle())
    }

    private func keyBackground(isPressed: Bool) -> Color {
        if colorScheme == .dark {
            if isPressed { return Color(uiColor: .systemGray4) }
            return Color(uiColor: colorSchemeContrast == .increased ? .systemGray2 : .systemGray3)
        }
        if isPressed { return Color(uiColor: .systemGray5) }
        return Color(uiColor: .systemBackground)
    }
}
