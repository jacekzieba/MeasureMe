// LeanMassDetailView.swift
//
// **LeanMassDetailView**
// Szczegółowy widok dla beztłuszczowej masy ciała z HealthKit.
// Wyświetla LBM jako procent całkowitej masy ciała z kategoriami zależnymi od wieku.
//
import SwiftUI

struct LeanMassDetailView: View {
    let value: Double // w kilogramach
    let percentage: Double? // LBM jako % całkowitej masy ciała
    let totalWeight: Double? // całkowita waga w kg
    let age: Int?
    let unitsSystem: String
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Karta naglowka
                VStack(alignment: .leading, spacing: 16) {
                    Text(AppLocalization.string("Lean Body Mass"))
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(.white)
                    
                    // Główna wartość - procent LBM (jeśli dostępny)
                    if let percentage = percentage {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(String(format: "%.1f", percentage))
                                .font(AppTypography.displayLarge)
                                .foregroundStyle(.white)
                            
                            Text(AppLocalization.string("%"))
                                .font(AppTypography.bodyEmphasis)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        
                        // Kategoria
                        Text(AppLocalization.string(category.name))
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color(hex: category.color), in: RoundedRectangle(cornerRadius: 8))
                        
                        // Masa w kg/lb jako info dodatkowe
                        Text(AppLocalization.string("leanmass.value", formattedValue.value, formattedValue.unit))
                            .font(AppTypography.body)
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.top, 4)
                    } else {
                        // Jeśli nie ma procentu, pokaż tylko masę
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(formattedValue.value)
                                .font(AppTypography.displayLarge)
                                .foregroundStyle(.white)
                            
                            Text(formattedValue.unit)
                                .font(AppTypography.bodyEmphasis)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        
                        Text(AppLocalization.string("From HealthKit"))
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color(hex: "#3B82F6"), in: RoundedRectangle(cornerRadius: 8))
                    }
                    
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .font(AppTypography.caption)
                        Text(AppLocalization.string("Synced from Health app"))
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
                
                // Czym jest Lean Body Mass?
                VStack(alignment: .leading, spacing: 12) {
                    Text(AppLocalization.string("What is Lean Body Mass?"))
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(.white)
                    
                    Text(AppLocalization.string("Lean body mass is your total body weight minus body fat. It includes muscle, bone, organs, and water - everything except fat tissue."))
                        .font(AppTypography.body)
                        .foregroundStyle(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                    
                    if percentage != nil {
                        Text(AppLocalization.string("LBM percentage represents how much of your total body weight is lean mass. Higher percentages generally indicate better muscle mass and metabolic health."))
                            .font(AppTypography.body)
                            .foregroundStyle(.white.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                
                // Reference Ranges (jeśli mamy procent)
                if percentage != nil {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(AppLocalization.string("reference.ranges.with.age", ageGroupText))
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(.white)
                        
                        VStack(spacing: 8) {
                            ForEach(referenceRanges, id: \.title) { range in
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
                }
                
                // Why it matters
                VStack(alignment: .leading, spacing: 12) {
                    Text(AppLocalization.string("Why It Matters"))
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(.white)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        BenefitRow(
                            icon: "flame.fill",
                            title: "Metabolic Health",
                            description: "Lean mass burns more calories at rest, supporting a healthy metabolism."
                        )
                        
                        BenefitRow(
                            icon: "figure.strengthtraining.traditional",
                            title: "Strength & Function",
                            description: "Muscle mass supports physical performance and daily activities."
                        )
                        
                        BenefitRow(
                            icon: "heart.fill",
                            title: "Overall Health",
                            description: "Higher lean mass is associated with better long-term health outcomes."
                        )
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
                        
                        Text(AppLocalization.string("Data Source"))
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(.white)
                    }
                    
                    if percentage == nil, totalWeight == nil {
                        Text(AppLocalization.string("To see your LBM percentage, please add your weight measurements. This helps provide more accurate health insights."))
                            .font(AppTypography.caption)
                            .foregroundStyle(.white.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(AppLocalization.string("This data comes from the Health app. Lean body mass measurements can vary based on the device and method used. For tracking progress, use the same measurement method consistently."))
                            .font(AppTypography.caption)
                            .foregroundStyle(.white.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                    }
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
        .toolbarBackground(.hidden, for: .navigationBar)
    }
    
    private var formattedValue: (value: String, unit: String) {
        if unitsSystem == "imperial" {
            let lbs = value * 2.20462
            return (String(format: "%.1f", lbs), "lb")
        } else {
            return (String(format: "%.1f", value), "kg")
        }
    }
    
    private var category: (name: String, color: String) {
        guard let percentage = percentage else {
            return ("From HealthKit", "#3B82F6")
        }
        
        guard let age = age else {
            // Bez wieku używamy zakresów dla młodych dorosłych
            if percentage >= 80 && percentage <= 92 { return ("Optimal", "#22C55E") }
            else if percentage > 92 { return ("High", "#3B82F6") }
            else { return ("Low", "#EF4444") }
        }
        
        // Zakresy zależą od wieku
        if age >= 19 && age <= 39 {
            if percentage >= 80 && percentage <= 92 { return ("Optimal", "#22C55E") }
            else if percentage > 92 { return ("High", "#3B82F6") }
            else { return ("Low", "#EF4444") }
        } else if age >= 40 && age <= 59 {
            if percentage >= 78 && percentage <= 89 { return ("Optimal", "#22C55E") }
            else if percentage > 89 { return ("High", "#3B82F6") }
            else { return ("Low", "#EF4444") }
        } else if age >= 60 && age <= 79 {
            if percentage >= 75 && percentage <= 87 { return ("Optimal", "#22C55E") }
            else if percentage > 87 { return ("High", "#3B82F6") }
            else { return ("Low", "#EF4444") }
        } else {
            if percentage >= 75 && percentage <= 87 { return ("Optimal", "#22C55E") }
            else if percentage > 87 { return ("High", "#3B82F6") }
            else { return ("Low", "#EF4444") }
        }
    }
    
    private var ageGroupText: String {
        guard let age = age else { return "" }
        
        if age >= 19 && age <= 39 {
            return AppLocalization.string("age.range.19_39")
        } else if age >= 40 && age <= 59 {
            return AppLocalization.string("age.range.40_59")
        } else if age >= 60 && age <= 79 {
            return AppLocalization.string("age.range.60_79")
        } else {
            return ""
        }
    }
    
    private var referenceRanges: [(title: String, range: String, color: String)] {
        guard let age = age else {
            return [
                ("Optimal", "80-92%", "#22C55E"),
                ("High", "> 92%", "#3B82F6"),
                ("Low", "< 80%", "#EF4444")
            ]
        }
        
        if age >= 19 && age <= 39 {
            return [
                ("Optimal", "80-92%", "#22C55E"),
                ("High", "> 92%", "#3B82F6"),
                ("Low", "< 80%", "#EF4444")
            ]
        } else if age >= 40 && age <= 59 {
            return [
                ("Optimal", "78-89%", "#22C55E"),
                ("High", "> 89%", "#3B82F6"),
                ("Low", "< 78%", "#EF4444")
            ]
        } else if age >= 60 && age <= 79 {
            return [
                ("Optimal", "75-87%", "#22C55E"),
                ("High", "> 87%", "#3B82F6"),
                ("Low", "< 75%", "#EF4444")
            ]
        } else {
            return [
                ("Optimal", "75-87%", "#22C55E"),
                ("High", "> 87%", "#3B82F6"),
                ("Low", "< 75%", "#EF4444")
            ]
        }
    }
}

// MARK: - Benefit Row

private struct BenefitRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(AppTypography.metricValue)
                .foregroundStyle(Color(hex: "#FCA311"))
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(.white)
                
                Text(description)
                    .font(AppTypography.caption)
                    .foregroundStyle(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    NavigationStack {
        LeanMassDetailView(
            value: 61.1,
            percentage: 81.5,
            totalWeight: 75.0,
            age: 30,
            unitsSystem: "metric"
        )
    }
}
#Preview("Without Percentage") {
    NavigationStack {
        LeanMassDetailView(
            value: 61.1,
            percentage: nil,
            totalWeight: nil,
            age: 30,
            unitsSystem: "metric"
        )
    }
}
