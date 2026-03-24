import SwiftUI

struct SFSymbolPickerView: View {
    @Binding var selectedSymbol: String
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(filteredCategories) { category in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(category.name)
                                .font(AppTypography.captionEmphasis)
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .padding(.horizontal, 16)

                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(category.symbols, id: \.self) { symbol in
                                    Button {
                                        selectedSymbol = symbol
                                        dismiss()
                                    } label: {
                                        Image(systemName: symbol)
                                            .font(.title3)
                                            .frame(width: 44, height: 44)
                                            .background(
                                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                    .fill(selectedSymbol == symbol
                                                          ? Color.appAccent.opacity(0.2)
                                                          : Color.secondary.opacity(0.1))
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                    .stroke(selectedSymbol == symbol
                                                            ? Color.appAccent
                                                            : Color.clear, lineWidth: 2)
                                            )
                                            .foregroundStyle(selectedSymbol == symbol
                                                             ? Color.appAccent
                                                             : .primary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }
                .padding(.vertical, 16)
            }
            .searchable(text: $searchText, prompt: AppLocalization.string("custom.metric.icon.search"))
            .navigationTitle(AppLocalization.string("custom.metric.icon.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("Cancel")) { dismiss() }
                }
            }
        }
    }

    private var filteredCategories: [SFSymbolCategory] {
        if searchText.isEmpty {
            return SFSymbolCategory.allCategories
        }
        let query = searchText.lowercased()
        let filtered = SFSymbolCategory.allCategories.compactMap { category -> SFSymbolCategory? in
            let matchingSymbols = category.symbols.filter { $0.lowercased().contains(query) }
            if matchingSymbols.isEmpty { return nil }
            return SFSymbolCategory(name: category.name, symbols: matchingSymbols)
        }
        return filtered
    }
}

// MARK: - Symbol Categories

struct SFSymbolCategory: Identifiable {
    let name: String
    let symbols: [String]
    var id: String { name }

    static let allCategories: [SFSymbolCategory] = [
        SFSymbolCategory(name: "Body & Fitness", symbols: [
            "figure", "figure.walk", "figure.run", "figure.stand",
            "figure.cooldown", "figure.strengthtraining.traditional",
            "figure.arms.open", "figure.mixed.cardio",
            "figure.martial.arts", "figure.yoga", "figure.pilates",
            "figure.flexibility", "figure.core.training",
            "figure.cross.training", "figure.dance",
            "figure.hiking", "figure.climbing",
            "figure.swimming", "figure.water.fitness",
            "figure.surfing", "figure.skiing.downhill",
            "figure.elliptical", "figure.step.training",
            "figure.stair.stepper",
        ]),
        SFSymbolCategory(name: "Health", symbols: [
            "heart.fill", "heart.text.square.fill",
            "bolt.heart.fill", "waveform.path.ecg",
            "lungs.fill", "brain.head.profile",
            "ear.fill", "eye.fill",
            "mouth.fill", "nose.fill",
            "hand.raised.fill", "allergens",
            "cross.case.fill", "pills.fill",
            "syringe.fill", "ivfluid.bag.fill",
            "staroflife.fill", "medical.thermometer.fill",
            "bandage.fill", "stethoscope",
        ]),
        SFSymbolCategory(name: "Food & Drink", symbols: [
            "cup.and.saucer.fill", "mug.fill",
            "wineglass.fill", "waterbottle.fill",
            "takeoutbag.and.cup.and.straw.fill",
            "fork.knife", "carrot.fill",
            "birthday.cake.fill",
            "drop.fill", "flame.fill",
        ]),
        SFSymbolCategory(name: "Measurement", symbols: [
            "ruler.fill", "scalemass.fill",
            "timer", "stopwatch.fill",
            "gauge.with.needle.fill",
            "speedometer", "barometer",
            "thermometer.medium",
            "percent", "number",
            "plusminus", "sum",
            "chart.bar.fill", "chart.line.uptrend.xyaxis",
            "chart.pie.fill",
        ]),
        SFSymbolCategory(name: "Nature & Weather", symbols: [
            "sun.max.fill", "moon.fill",
            "cloud.fill", "snowflake",
            "wind", "tornado",
            "leaf.fill", "tree.fill",
            "mountain.2.fill", "water.waves",
            "pawprint.fill",
        ]),
        SFSymbolCategory(name: "Sport", symbols: [
            "sportscourt.fill", "soccerball",
            "basketball.fill", "football.fill",
            "tennis.racket", "baseball.fill",
            "figure.bowling", "figure.golf",
            "figure.badminton", "figure.boxing",
            "figure.fencing",
            "dumbbell.fill", "trophy.fill",
            "medal.fill", "flag.checkered",
        ]),
        SFSymbolCategory(name: "Objects", symbols: [
            "bed.double.fill", "alarm.fill",
            "bag.fill", "cart.fill",
            "creditcard.fill", "gift.fill",
            "backpack.fill", "suitcase.fill",
            "book.fill", "pencil",
            "doc.fill", "folder.fill",
            "paperclip", "scissors",
            "hammer.fill", "wrench.fill",
            "paintbrush.fill",
        ]),
        SFSymbolCategory(name: "Shapes & Symbols", symbols: [
            "circle.fill", "square.fill",
            "triangle.fill", "diamond.fill",
            "hexagon.fill", "star.fill",
            "bolt.fill", "bell.fill",
            "tag.fill", "pin.fill",
            "mappin", "location.fill",
            "flag.fill", "bookmark.fill",
            "checkmark.seal.fill", "xmark.seal.fill",
            "target", "scope",
            "circle.dotted", "sparkles",
        ]),
        SFSymbolCategory(name: "Arrows & Controls", symbols: [
            "arrow.up", "arrow.down",
            "arrow.up.arrow.down",
            "arrow.clockwise", "arrow.counterclockwise",
            "repeat", "infinity",
            "plus.circle.fill", "minus.circle.fill",
            "equal.circle.fill",
        ]),
    ]
}
