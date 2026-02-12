// BMIDetailView.swift
//
// **BMIDetailView**
// Szczegółowy widok wskaźnika BMI (Body Mass Index).
//
import SwiftUI

struct BMIDetailView: View {
    let result: HealthMetricsCalculator.BMIResult
    
    var body: some View {
        ZStack(alignment: .top) {
            AppScreenBackground()
            
            // Zawartość
            ScrollView {
                VStack(spacing: 32) {
                    // Nagłówek
                    VStack(alignment: .leading, spacing: 8) {
                        Text(AppLocalization.string("Body Mass Index"))
                            .font(AppTypography.sectionTitle)
                            .foregroundStyle(.white)
                        
                        Text(AppLocalization.string("BMI"))
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
                            icon: "chart.line.uptrend.xyaxis",
                            title: AppLocalization.string("Quick context"),
                            description: AppLocalization.string("BMI gives a fast, broad view of weight status over time.")
                        ),
                        WhyItMattersItem(
                            icon: "heart.fill",
                            title: AppLocalization.string("Risk signal"),
                            description: AppLocalization.string("Large shifts can correlate with cardiometabolic risk.")
                        ),
                        WhyItMattersItem(
                            icon: "figure.strengthtraining.traditional",
                            title: AppLocalization.string("Use with context"),
                            description: AppLocalization.string("Pair it with waist and body fat for a fuller picture.")
                        )
                    ])
                    
                    // Legenda
                    legendCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 24)
            }
        }
        .navigationTitle(AppLocalization.string("BMI"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
    
    // MARK: - Components
    
    private var currentValueCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Wartość i kategoria
            HStack(alignment: .bottom, spacing: 16) {
                Text(String(format: "%.1f", result.bmi))
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
            
            // Informacja o grupie wiekowej
            if let age = result.age {
                HStack(spacing: 6) {
                    Image(systemName: "person.fill")
                        .font(AppTypography.caption)
                    let ageGroupName = AppLocalization.string(result.ageGroup.displayName)
                    Text(AppLocalization.string("bmi.age.group", age, ageGroupName))
                        .font(AppTypography.caption)
                }
                .foregroundStyle(.white.opacity(0.7))
            }
            
            // Opis kategorii
            Text(AppLocalization.string(result.category.description(for: result.ageGroup)))
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
                
                Text(AppLocalization.string("About BMI"))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(.white)
            }
            
            Text(AppLocalization.string("health.bmi.description"))
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
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(AppLocalization.string("BMI Ranges"))
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(.white)
                    
                    Text(AppLocalization.string("bmi.for.agegroup", AppLocalization.string(result.ageGroup.displayName)))
                        .font(AppTypography.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            
            VStack(spacing: 12) {
                ForEach(HealthMetricsReference.bmiRanges(for: result.ageGroup), id: \.title) { item in
                    LegendRow(
                        title: item.title,
                        range: item.range,
                        description: item.description
                    )
                }
            }
            
            // Disclaimer dla dzieci
            if result.ageGroup == .child {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .font(AppTypography.caption)
                        .foregroundStyle(Color(hex: "#FCA311"))
                    
                    Text(AppLocalization.string("Note: For children and adolescents, BMI interpretation should ideally use age and gender-specific percentile charts. These simplified ranges are approximations."))
                        .font(AppTypography.micro)
                        .foregroundStyle(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)
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
