// ConicityDetailView.swift
//
// **ConicityDetailView**
// Szczegółowy widok dla Conicity Index - wskaźnika ryzyka zdrowotnego
// związanego z centralnym rozkładem tkanki tłuszczowej.
//
import SwiftUI

struct ConicityDetailView: View {
    let result: HealthMetricsCalculator.ConicityResult
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header Card
                VStack(alignment: .leading, spacing: 16) {
                    Text(AppLocalization.string("Central Fat Risk"))
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(.white)
                    
                    Text(String(format: "%.2f", result.conicity))
                        .font(AppTypography.displayLarge)
                        .foregroundStyle(.white)
                    
                Text(AppLocalization.string(result.category.rawValue))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color(hex: result.category.color), in: RoundedRectangle(cornerRadius: 8))
                    
                    Text(AppLocalization.string(result.category.description))
                        .font(AppTypography.body)
                        .foregroundStyle(.white.opacity(0.9))
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
                
                // What is Conicity?
                VStack(alignment: .leading, spacing: 12) {
                    Text(AppLocalization.string("What is Central Fat Risk?"))
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(.white)
                    
                    Text(AppLocalization.string("The Conicity Index is an indicator of central (abdominal) fat accumulation. It evaluates how your body mass is distributed around your waist relative to your height and weight."))
                        .font(AppTypography.body)
                        .foregroundStyle(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Text(AppLocalization.string("Higher values indicate more fat concentrated in the abdominal area, which is associated with increased risk of cardiovascular disease, type 2 diabetes, and metabolic syndrome."))
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
                        icon: "heart.fill",
                        title: AppLocalization.string("Central fat"),
                        description: AppLocalization.string("Conicity highlights abdominal fat linked to cardiometabolic risk.")
                    ),
                    WhyItMattersItem(
                        icon: "waveform.path.ecg",
                        title: AppLocalization.string("Risk insight"),
                        description: AppLocalization.string("It can reveal risk even when weight looks stable.")
                    ),
                    WhyItMattersItem(
                        icon: "target",
                        title: AppLocalization.string("Trackable"),
                        description: AppLocalization.string("Waist changes help move this index in a healthier direction.")
                    )
                ])
                
                // Ranges
                VStack(alignment: .leading, spacing: 12) {
                    Text(AppLocalization.string("Risk Categories"))
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(.white)
                    
                    VStack(spacing: 8) {
                        ForEach(conicityRanges, id: \.title) { range in
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
                        Image(systemName: "heart.text.square.fill")
                            .foregroundStyle(Color(hex: "#FCA311"))
                        
                        Text(AppLocalization.string("Health Note"))
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(.white)
                    }
                    
                    Text(AppLocalization.string("The Conicity Index is a screening tool and should be interpreted alongside other health indicators. It is not a medical diagnosis. Consult with healthcare professionals for comprehensive health assessments."))
                        .font(AppTypography.caption)
                        .foregroundStyle(.white.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color(hex: "#FCA311").opacity(0.15),
                    in: RoundedRectangle(cornerRadius: 10)
                )
            }
            .padding()
        }
        .background(Color.black.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
    
    private var conicityRanges: [(title: String, range: String, color: String)] {
        switch result.gender {
        case .male:
            return [
                ("Low risk", "< 1.20", "#22C55E"),
                ("Moderate risk", "1.20-1.30", "#FCA311"),
                ("High risk", "> 1.30", "#EF4444")
            ]
        case .female:
            return [
                ("Low risk", "< 1.15", "#22C55E"),
                ("Moderate risk", "1.15-1.25", "#FCA311"),
                ("High risk", "> 1.25", "#EF4444")
            ]
        case .notSpecified:
            return [
                ("Low risk", "< 1.20", "#22C55E"),
                ("Moderate risk", "1.20-1.30", "#FCA311"),
                ("High risk", "> 1.30", "#EF4444")
            ]
        }
    }
}

#Preview {
    NavigationStack {
        ConicityDetailView(
            result: HealthMetricsCalculator.ConicityResult(
                conicity: 1.25,
                category: .moderate,
                gender: .male
            )
        )
    }
}
