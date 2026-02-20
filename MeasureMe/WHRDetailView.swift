// WHRDetailView.swift
//
// **WHRDetailView**
// Szczegółowy widok wskaźnika WHR (stosunek talii do bioder).
//
import SwiftUI

struct WHRDetailView: View {
    let result: HealthMetricsCalculator.WHRResult
    let gender: Gender
    
    var body: some View {
        ZStack(alignment: .top) {
            AppScreenBackground()
            
            // Zawartość
            ScrollView {
                VStack(spacing: 32) {
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Aktualna wartość
                    currentValueCard
                    
                    // Opis
                    descriptionCard
                    
                    // Legenda (z podziałem na płeć)
                    legendCard
                    
                    // Informacja o płci
                    if gender == .notSpecified {
                        genderNoticeCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 24)
            }
        }
        .navigationTitle(AppLocalization.string("WHR"))
        .navigationBarTitleDisplayMode(.inline)
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
            Text(AppLocalization.string(result.category.description))
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
                
                Text(AppLocalization.string("About WHR"))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(.white)
            }
            
            Text(AppLocalization.string("health.whr.description"))
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
                
                Text(gender == .male
                    ? AppLocalization.string("WHR Ranges (Male)")
                    : AppLocalization.string("WHR Ranges (Female)"))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(.white)
            }
            
            VStack(spacing: 12) {
                let ranges = gender == .male ? HealthMetricsReference.whrRangesMale : HealthMetricsReference.whrRangesFemale
                
                ForEach(ranges, id: \.title) { item in
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
