// BodyFatDetailView.swift
//
// **BodyFatDetailView**
// Szczegółowy widok dla procentu tkanki tłuszczowej z HealthKit.
//
import SwiftUI

struct BodyFatDetailView: View {
    let value: Double
    let gender: Gender
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header Card
                VStack(alignment: .leading, spacing: 16) {
                    Text(AppLocalization.string("Body Fat Percentage"))
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(.white)
                    
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(String(format: "%.1f", value))
                            .font(AppTypography.displayLarge)
                            .foregroundStyle(.white)
                        
                        Text(AppLocalization.string("%"))
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    
                    Text(AppLocalization.string(category.name))
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color(hex: category.color), in: RoundedRectangle(cornerRadius: 8))
                    
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .font(AppTypography.caption)
                        Text(AppLocalization.string("From HealthKit"))
                            .font(AppTypography.caption)
                    }
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.top, 4)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(
                        colors: [
                            Color(hex: "#14213D").opacity(0.6),
                            Color(hex: "#000000")
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color(hex: "#FCA311").opacity(0.3), lineWidth: 1)
                )
                
                // What is Body Fat %?
                VStack(alignment: .leading, spacing: 12) {
                    Text(AppLocalization.string("What is Body Fat Percentage?"))
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(.white)
                    
                    Text(AppLocalization.string("Body fat percentage is the proportion of your body weight that is fat tissue. It provides a more accurate picture of your body composition than weight or BMI alone."))
                        .font(AppTypography.body)
                        .foregroundStyle(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Text(AppLocalization.string("This data is sourced from the Health app, which may collect it from compatible scales, fitness devices, or manual entries."))
                        .font(AppTypography.body)
                        .foregroundStyle(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))

                WhyItMattersCard(items: [
                    WhyItMattersItem(
                        icon: "figure.walk",
                        title: AppLocalization.string("Composition focus"),
                        description: AppLocalization.string("Body fat percentage shows how weight is split between fat and lean mass.")
                    ),
                    WhyItMattersItem(
                        icon: "heart.fill",
                        title: AppLocalization.string("Metabolic health"),
                        description: AppLocalization.string("Very high levels can add cardiometabolic strain over time.")
                    ),
                    WhyItMattersItem(
                        icon: "target",
                        title: AppLocalization.string("Progress clarity"),
                        description: AppLocalization.string("It helps track recomposition even when scale weight is steady.")
                    )
                ])
                
                // Ranges
                VStack(alignment: .leading, spacing: 12) {
                    Text(AppLocalization.string("reference.ranges.gender", AppLocalization.string(gender.displayName)))
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(.white)
                    
                    VStack(spacing: 8) {
                        ForEach(bodyFatRanges, id: \.title) { range in
                            HStack {
                                Circle()
                                    .fill(Color(hex: range.color))
                                    .frame(width: 12, height: 12)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(AppLocalization.string(range.title))
                                        .font(AppTypography.bodyEmphasis)
                                        .foregroundStyle(.white)
                                    
                                    Text(range.range)
                                        .font(AppTypography.caption)
                                        .foregroundStyle(.white.opacity(0.7))
                                }
                                
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                
                // Important Note
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(Color(hex: "#3B82F6"))
                        
                        Text(AppLocalization.string("Important"))
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(.white)
                    }
                    
                    Text(AppLocalization.string("Body fat percentage measurements can vary depending on the measurement method. For the most accurate assessment, use the same device consistently and measure under similar conditions."))
                        .font(AppTypography.caption)
                        .foregroundStyle(.white.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color(hex: "#3B82F6").opacity(0.15),
                    in: RoundedRectangle(cornerRadius: 10)
                )
            }
            .padding()
        }
        .background(Color.black.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var category: (name: String, color: String) {
        switch gender {
        case .male:
            if value < 10 { return ("Essential", "#3B82F6") }
            else if value < 20 { return ("Athletic", "#22C55E") }
            else if value < 25 { return ("Fitness", "#FCA311") }
            else { return ("High", "#EF4444") }
        case .female:
            if value < 20 { return ("Essential", "#3B82F6") }
            else if value < 30 { return ("Athletic", "#22C55E") }
            else if value < 35 { return ("Fitness", "#FCA311") }
            else { return ("High", "#EF4444") }
        case .notSpecified:
            if value < 15 { return ("Low", "#3B82F6") }
            else if value < 25 { return ("Normal", "#22C55E") }
            else if value < 30 { return ("Elevated", "#FCA311") }
            else { return ("High", "#EF4444") }
        }
    }
    
    private var bodyFatRanges: [(title: String, range: String, color: String)] {
        switch gender {
        case .male:
            return [
                ("Essential", "< 10%", "#3B82F6"),
                ("Athletic", "10-20%", "#22C55E"),
                ("Fitness", "20-25%", "#FCA311"),
                ("High", "> 25%", "#EF4444")
            ]
        case .female:
            return [
                ("Essential", "< 20%", "#3B82F6"),
                ("Athletic", "20-30%", "#22C55E"),
                ("Fitness", "30-35%", "#FCA311"),
                ("High", "> 35%", "#EF4444")
            ]
        case .notSpecified:
            return [
                ("Low", "< 15%", "#3B82F6"),
                ("Normal", "15-25%", "#22C55E"),
                ("Elevated", "25-30%", "#FCA311"),
                ("High", "> 30%", "#EF4444")
            ]
        }
    }
}

#Preview {
    NavigationStack {
        BodyFatDetailView(value: 18.5, gender: .male)
    }
}
