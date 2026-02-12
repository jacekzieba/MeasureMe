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
    
    var body: some View {
        ZStack(alignment: .top) {
            AppScreenBackground()
            
            // Zawartość
            ScrollView {
                VStack(spacing: 32) {
                    // Brakujące dane (jeśli są)
                    if !missingMetrics.isEmpty {
                        missingDataBanner
                    }
                    
                    // WHtR Section
                    whtrSection
                    
                    // WHR Section
                    whrSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 24)
            }
        }
        .navigationTitle(AppLocalization.string("Health Metrics"))
        .navigationBarTitleDisplayMode(.large)
    }
    
    // MARK: - Missing Data Banner
    
    private var missingDataBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(Color(hex: "#FCA311"))
                
                Text(AppLocalization.string("Missing measurements"))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(.white)
            }
            
            Text(AppLocalization.string("Some health metrics cannot be calculated because the following measurements are missing:"))
                .font(AppTypography.body)
                .foregroundStyle(.white.opacity(0.8))
            
            VStack(alignment: .leading, spacing: 6) {
                ForEach(missingMetrics, id: \.self) { metric in
                    HStack(spacing: 8) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(Color(hex: "#FCA311"))
                        
                        Text(metric)
                            .font(AppTypography.body)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color(hex: "#FCA311").opacity(0.15),
                    Color(hex: "#FCA311").opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: "#FCA311").opacity(0.4), lineWidth: 1.5)
        )
    }
    
    // MARK: - WHtR Section
    
    private var whtrSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Nagłówek
            VStack(alignment: .leading, spacing: 8) {
                Text(AppLocalization.string("Waist-to-Height Ratio"))
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(.white)
                
                Text(AppLocalization.string("WHtR"))
                    .font(AppTypography.body)
                    .foregroundStyle(Color(hex: "#FCA311"))
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
                    .foregroundStyle(.white)
                
                Text(AppLocalization.string("WHR"))
                    .font(AppTypography.body)
                    .foregroundStyle(Color(hex: "#FCA311"))
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
        VStack(alignment: .leading, spacing: 16) {
            // Wartość i kategoria
            HStack(alignment: .bottom, spacing: 16) {
                Text(String(format: "%.2f", value))
                    .font(AppTypography.displayMedium)
                    .foregroundStyle(.white)
                
                Spacer()
                
                Text(AppLocalization.string(category))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(hex: categoryColor), in: RoundedRectangle(cornerRadius: 10))
            }
            
            // Opis kategorii
            Text(AppLocalization.string(description))
                .font(AppTypography.body)
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color(hex: "#14213D").opacity(0.5),
                    Color(hex: "#000000").opacity(0.3)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: categoryColor).opacity(0.3), lineWidth: 1.5)
        )
    }
    
    private func unavailableCard(reason: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.6))
                
                Text(AppLocalization.string("Not available"))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(.white)
            }
            
            Text(AppLocalization.string(reason))
                .font(AppTypography.body)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color(hex: "#14213D").opacity(0.3),
                    Color(hex: "#000000").opacity(0.2)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        )
    }
    
    private func descriptionCard(text: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(Color(hex: "#FCA311"))
                
                Text(AppLocalization.string("About this metric"))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(.white)
            }
            
            Text(AppLocalization.string(text))
                .font(AppTypography.body)
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color(hex: "#14213D").opacity(0.4),
                    Color(hex: "#000000")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: "#FCA311").opacity(0.2), lineWidth: 1)
        )
    }
    
    private func legendCard(title: String, ranges: [(title: String, range: String, description: String)]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(Color(hex: "#FCA311"))
                
                Text(AppLocalization.string(title))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(.white)
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
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color(hex: "#14213D").opacity(0.4),
                    Color(hex: "#000000")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: "#FCA311").opacity(0.2), lineWidth: 1)
        )
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
                    .foregroundStyle(.white)
                
                Spacer()
                
                // Zakres
                Text(range)
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(hex: "#14213D").opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            }
            
            // Opis
            Text(AppLocalization.string(description))
                .font(AppTypography.caption)
                .foregroundStyle(.white.opacity(0.7))
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "person.fill.questionmark")
                    .foregroundStyle(Color(hex: "#FCA311"))
                
                Text(AppLocalization.string("Gender not specified"))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(.white)
            }
            
            Text(AppLocalization.string("WHR thresholds differ between males and females. Set your gender in Settings for more accurate ranges."))
                .font(AppTypography.caption)
                .foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
            
            Text(AppLocalization.string("Currently showing female ranges (more conservative)."))
                .font(AppTypography.caption)
                .foregroundStyle(.white.opacity(0.6))
                .italic()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(hex: "#FCA311").opacity(0.1),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(hex: "#FCA311").opacity(0.3), lineWidth: 1)
        )
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
