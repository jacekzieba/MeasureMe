// WHtRDetailView.swift
//
// **WHtRDetailView**
// Szczegółowy widok wskaźnika WHtR (Waist-to-Height Ratio).
//
import SwiftUI

struct WHtRDetailView: View {
    let result: HealthMetricsCalculator.WHtRResult
    
    var body: some View {
        ZStack(alignment: .top) {
            AppScreenBackground()
            
            // Zawartość
            ScrollView {
                VStack(spacing: 32) {
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Aktualna wartość
                    currentValueCard
                    
                    // Opis
                    descriptionCard

                    WhyItMattersCard(items: [
                        WhyItMattersItem(
                            icon: "heart.fill",
                            title: AppLocalization.string("Cardio health"),
                            description: AppLocalization.string("WHtR reflects central fat, a strong signal for cardiovascular risk.")
                        ),
                        WhyItMattersItem(
                            icon: "bolt.heart.fill",
                            title: AppLocalization.string("Metabolic risk"),
                            description: AppLocalization.string("Higher ratios are linked to insulin resistance and metabolic strain.")
                        ),
                        WhyItMattersItem(
                            icon: "target",
                            title: AppLocalization.string("Actionable"),
                            description: AppLocalization.string("Waist changes can move this ratio quickly, making it useful for progress.")
                        )
                    ])
                    
                    // Legenda
                    legendCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 24)
            }
        }
        .navigationTitle(AppLocalization.string("WHtR"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
    
    // MARK: - Components
    
    private var currentValueCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Wartość i kategoria
            HStack(alignment: .bottom, spacing: 16) {
                Text(String(format: "%.2f", result.ratio))
                    .font(AppTypography.displayLarge)
                    .foregroundStyle(.white)
                
                Spacer()
                
                Text(AppLocalization.string(result.category.rawValue))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(hex: result.category.color), in: RoundedRectangle(cornerRadius: 10))
            }
            
            // Opis kategorii
            Text(result.category.description)
                .font(AppTypography.body)
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
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
                .stroke(Color(hex: result.category.color).opacity(0.3), lineWidth: 1.5)
        )
    }
    
    private var descriptionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(Color(hex: "#FCA311"))
                
                Text(AppLocalization.string("About WHtR"))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(.white)
            }
            
            Text(AppLocalization.string("health.whtr.description"))
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
    
    private var legendCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(Color(hex: "#FCA311"))
                
                Text(AppLocalization.string("WHtR Ranges"))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(.white)
            }
            
            VStack(spacing: 12) {
                ForEach(HealthMetricsReference.whtrRanges, id: \.title) { item in
                    LegendRow(
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
}

// MARK: - Legend Row (Reusable)

struct LegendRow: View {
    let title: String
    let range: String
    let description: String
    
    var body: some View {
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
        } else if category.contains("Underweight") {
            return Color(hex: "#3B82F6")
        } else {
            return Color(hex: "#EF4444")
        }
    }
}
