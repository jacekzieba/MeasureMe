// HealthMetricsDetailView.swift
//
// **HealthMetricsDetailView**
// Szczegółowy widok wskaźników zdrowotnych (WHtR, WHR).
//
// **Funkcje:**
// - Wyświetlanie aktualnych wartości WHtR i WHR
// - Opis wskaźników na podstawie danych z Wikipedii
// - Legendy z zakresami dla różnych kategorii
// - Informacje o brakujących danych
//
import SwiftUI

struct HealthMetricsDetailView: View {
    let whtrResult: HealthMetricsCalculator.WHtRResult?
    let whrResult: HealthMetricsCalculator.WHRResult?
    let missingMetrics: [String]
    let userGender: Gender
    private let theme = FeatureTheme.health
    
    var body: some View {
        SettingsScrollDetailScaffold(title: AppLocalization.string("Health Metrics"), theme: .health) {
                    // Brakujące dane (jeśli są)
                    if !missingMetrics.isEmpty {
                        missingDataBanner
                    }
                    
                    // WHtR Section
                    whtrSection
                    
                    // WHR Section
                    whrSection
        }
    }
    
    // MARK: - Missing Data Banner
    
    private var missingDataBanner: some View {
        HealthInsightNoteCard(accent: AppColorRoles.accentPrimary) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundStyle(AppColorRoles.accentPrimary)
                    
                    Text(AppLocalization.string("Missing measurements"))
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(AppColorRoles.textPrimary)
                }
                
                Text(AppLocalization.string("Some health metrics cannot be calculated because the following measurements are missing:"))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColorRoles.textSecondary)
                
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(missingMetrics, id: \.self) { metric in
                        HStack(spacing: 8) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 6))
                                .foregroundStyle(AppColorRoles.accentPrimary)
                            
                            Text(metric)
                                .font(AppTypography.body)
                                .foregroundStyle(AppColorRoles.textPrimary)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }
    
    // MARK: - WHtR Section
    
    private var whtrSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Nagłówek
            VStack(alignment: .leading, spacing: 8) {
                Text(AppLocalization.string("Waist-to-Height Ratio"))
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(AppColorRoles.textPrimary)
                
                Text(AppLocalization.string("WHtR"))
                    .font(AppTypography.body)
                    .foregroundStyle(theme.accent)
                    .textCase(.uppercase)
            }
            
            // Aktualna wartość
            if let whtr = whtrResult {
                currentValueCard(
                    value: whtr.ratio,
                    category: whtr.category.rawValue,
                    categoryColor: whtr.category.color,
                    description: whtr.category.description
                )
            } else {
                unavailableCard(reason: "Missing waist or height measurement")
            }
            
            // Opis
            descriptionCard(text: "health.whtr.description")
            
            // Legenda
            legendCard(
                title: "WHtR Ranges",
                ranges: HealthMetricsReference.whtrRanges
            )
        }
    }
    
    // MARK: - WHR Section
    
    private var whrSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Nagłówek
            VStack(alignment: .leading, spacing: 8) {
                Text(AppLocalization.string("Waist-to-Hip Ratio"))
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(AppColorRoles.textPrimary)
                
                Text(AppLocalization.string("WHR"))
                    .font(AppTypography.body)
                    .foregroundStyle(theme.accent)
                    .textCase(.uppercase)
            }
            
            // Aktualna wartość
            if let whr = whrResult {
                currentValueCard(
                    value: whr.ratio,
                    category: whr.category.rawValue,
                    categoryColor: whr.category.color,
                    description: whr.category.description
                )
            } else {
                unavailableCard(reason: "Missing waist or hip measurement")
            }
            
            // Opis
            descriptionCard(text: "health.whr.description")
            
            // Legenda (z podziałem na płeć)
            if userGender == .male {
                legendCard(
                    title: "WHR Ranges (Male)",
                    ranges: HealthMetricsReference.whrRangesMale
                )
            } else {
                legendCard(
                    title: "WHR Ranges (Female)",
                    ranges: HealthMetricsReference.whrRangesFemale
                )
            }
            
            // Informacja o płci
            if userGender == .notSpecified {
                genderNoticeCard
            }
        }
    }
    
    // MARK: - Supporting Cards
    
    private func currentValueCard(value: Double, category: String, categoryColor: String, description: String) -> some View {
        HealthInsightHeroCard(accent: Color(hex: categoryColor)) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .bottom, spacing: 16) {
                    Text(String(format: "%.2f", value))
                        .font(AppTypography.displayMedium)
                        .foregroundStyle(AppColorRoles.textPrimary)
                    
                    Spacer()
                    
                    Text(AppLocalization.string(category))
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(Color.bestAccessibleTextColor(onHex: categoryColor))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color(hex: categoryColor), in: RoundedRectangle(cornerRadius: 10))
                }
                
                Text(AppLocalization.string(description))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColorRoles.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    private func unavailableCard(reason: String) -> some View {
        HealthInsightCard(tint: theme.softTint) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(AppColorRoles.textTertiary)
                    
                    Text(AppLocalization.string("Not available"))
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(AppColorRoles.textPrimary)
                }
                
                Text(AppLocalization.string(reason))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColorRoles.textSecondary)
            }
        }
    }
    
    private func descriptionCard(text: String) -> some View {
        HealthInsightCard(tint: theme.softTint) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(AppColorRoles.accentPrimary)
                    
                    Text(AppLocalization.string("About this metric"))
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(AppColorRoles.textPrimary)
                }
                
                Text(AppLocalization.string(text))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColorRoles.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    private func legendCard(title: String, ranges: [(title: String, range: String, description: String)]) -> some View {
        HealthInsightCard(tint: theme.softTint) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "chart.bar.fill")
                        .foregroundStyle(AppColorRoles.accentPrimary)
                    
                    Text(AppLocalization.string(title))
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(AppColorRoles.textPrimary)
                }
                
                VStack(spacing: 12) {
                    ForEach(ranges, id: \.title) { item in
                        legendRow(
                            title: item.title,
                            range: item.range,
                            description: item.description
                        )
                    }
                }
            }
        }
    }
    
    private func legendRow(title: String, range: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                // Kolorowa kropka
                Circle()
                    .fill(colorForCategory(title))
                    .frame(width: 10, height: 10)
                
                // Nazwa kategorii
                Text(AppLocalization.string(title))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColorRoles.textPrimary)
                
                Spacer()
                
                // Zakres
                Text(range)
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(AppColorRoles.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(AppColorRoles.surfaceInteractive, in: RoundedRectangle(cornerRadius: 6))
            }
            
            // Opis
            Text(AppLocalization.string(description))
                .font(AppTypography.caption)
                .foregroundStyle(AppColorRoles.textSecondary)
                .padding(.leading, 22)
        }
    }
    
    private func colorForCategory(_ category: String) -> Color {
        if category.contains("Normal") {
            return Color(hex: "#22C55E")
        } else if category.contains("Overweight") || category.contains("Increased") {
            return Color(hex: "#FCA311")
        } else {
            return Color(hex: "#EF4444")
        }
    }
    
    private var genderNoticeCard: some View {
        HealthInsightNoteCard(accent: AppColorRoles.accentPrimary) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "person.fill.questionmark")
                        .foregroundStyle(AppColorRoles.accentPrimary)
                    
                    Text(AppLocalization.string("Gender not specified"))
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(AppColorRoles.textPrimary)
                }
                
                Text(AppLocalization.string("WHR thresholds differ between males and females. Set your gender in Settings for more accurate ranges."))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColorRoles.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                Text(AppLocalization.string("Currently showing female ranges (more conservative)."))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColorRoles.textTertiary)
                    .italic()
            }
        }
    }
}

// MARK: - Preview

#Preview("Health Metrics Detail - Complete") {
    NavigationStack {
        HealthMetricsDetailView(
            whtrResult: HealthMetricsCalculator.calculateWHtR(waistCm: 85, heightCm: 180),
            whrResult: HealthMetricsCalculator.calculateWHR(waistCm: 85, hipsCm: 95, gender: .male),
            missingMetrics: [],
            userGender: .male
        )
    }
}

#Preview("Health Metrics Detail - Missing Data") {
    NavigationStack {
        HealthMetricsDetailView(
            whtrResult: nil,
            whrResult: nil,
            missingMetrics: ["Waist circumference", "Hip circumference"],
            userGender: .notSpecified
        )
    }
}
