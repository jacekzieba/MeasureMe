import SwiftUI

struct HealthMetricsSectionCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Nagłówek sekcji
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(Color(hex: "#FCA311"))
                
                Text(title)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(.white)
            }
            
            // Metryki
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(hex: "#1C1C1E"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Health Metric Row

struct HealthMetricRow<Destination: View>: View {
    let title: String
    let value: String
    let category: String
    let categoryColor: String
    let destination: Destination
    
    var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 12) {
                // Lewa strona - tytuł
                VStack(alignment: .leading, spacing: 4) {
                    ViewThatFits(in: .vertical) {
                        Text(title)
                            .font(AppTypography.body)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(title)
                            .font(AppTypography.body)
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    Text(category)
                        .font(AppTypography.micro)
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(hex: categoryColor), in: RoundedRectangle(cornerRadius: 4))
                }
                
                Spacer()
                
                // Prawa strona - wartość
                HStack(spacing: 4) {
                    Text(value)
                        .font(AppTypography.metricValue)
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    
                    Image(systemName: "chevron.right")
                        .font(AppTypography.micro)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(minHeight: 44)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.05))
            )
        }
        .contentShape(Rectangle())
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview("Health Metrics - Complete") {
    NavigationStack {
        ZStack {
            Color.black.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 32) {
                    HealthMetricsSection(
                        latestWaist: 85.0,
                        latestHeight: 180.0,
                        latestWeight: 75.0,
                        latestBodyFat: 18.5,
                        latestLeanMass: 61.1
                    )
                }
                .padding()
            }
        }
    }
    .onAppear {
        UserDefaults.standard.set(30, forKey: "userAge")
        UserDefaults.standard.set("male", forKey: "userGender")
    }
}

#Preview("Health Metrics - Missing Data") {
    NavigationStack {
        ZStack {
            Color.black.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 32) {
                    HealthMetricsSection(
                        latestWaist: nil,
                        latestHeight: 180.0,
                        latestWeight: nil,
                        latestBodyFat: nil,
                        latestLeanMass: nil
                    )
                }
                .padding()
            }
        }
    }
}

#Preview("Health Metrics - No Metrics Enabled") {
    NavigationStack {
        ZStack {
            Color.black.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 32) {
                    HealthMetricsSection(
                        latestWaist: 85.0,
                        latestHeight: 180.0,
                        latestWeight: 75.0,
                        latestBodyFat: 18.5,
                        latestLeanMass: 61.1
                    )
                }
                .padding()
            }
        }
    }
    .onAppear {
        UserDefaults.standard.set(false, forKey: "showBMIOnHome")
        UserDefaults.standard.set(false, forKey: "showWHtROnHome")
        UserDefaults.standard.set(false, forKey: "showRFMOnHome")
        UserDefaults.standard.set(false, forKey: "showBodyFatOnHome")
        UserDefaults.standard.set(false, forKey: "showLeanMassOnHome")
        UserDefaults.standard.set(false, forKey: "showABSIOnHome")
        UserDefaults.standard.set(false, forKey: "showConicityOnHome")
    }
}
