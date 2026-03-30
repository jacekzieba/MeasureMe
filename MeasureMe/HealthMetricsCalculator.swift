// HealthMetricsCalculator.swift
//
// **HealthMetricsCalculator**
// Health metrics calculator with risk categories.
//
// **Core Metrics:**
// - WHtR (waist-to-height ratio): Ratio of waist circumference to height
// - RFM (Relative Fat Mass): Relative fat mass estimate
// - BMI (Body Mass Index): Body mass index with age adjustment
//
// **Body Composition:**
// - Body Fat Percentage: Body fat percentage (from HealthKit)
// - Lean Body Mass: Lean body mass (from HealthKit)
//
// **Risk Indicators:**
// - ABSI (A Body Shape Index): Risk related to body shape
// - Conicity Index: Risk related to central fat distribution
//
// **BMI and age:**
// - Children/adolescents (< 18 years): Simplified ranges
// - Adults (18-65 years): Standard WHO ranges
// - Seniors (> 65 years): Slightly higher ranges
//
import Foundation
import Darwin

// MARK: - Gender

enum Gender: String, CaseIterable {
    case male = "male"
    case female = "female"
    case notSpecified = "notSpecified"
    
    var displayName: String {
        switch self {
        case .male: return AppLocalization.string("Male")
        case .female: return AppLocalization.string("Female")
        case .notSpecified: return AppLocalization.string("Not specified")
        }
    }
}

/// Evaluation wrapper for indicators that can require the user's gender.
enum GenderDependentResult<Value> {
    case value(Value)
    case requiresGender
}

// MARK: - Health Metrics Calculator

@MainActor
final class HealthMetricsCalculator {
    
    // MARK: - WHtR (waist-to-height ratio)
    
    struct WHtRResult {
        let ratio: Double
        let category: WHtRCategory
        
        enum WHtRCategory: String {
            case normal = "Normal weight"
            case increased = "Increased weight"
            case high = "High weight"
            
            var color: String {
                switch self {
                case .normal: return AppColorRoles.stateSuccessHex
                case .increased: return AppColorRoles.stateWarningHex
                case .high: return AppColorRoles.stateErrorHex
                }
            }
            
            var description: String {
                switch self {
                case .normal:
                    return "Your waist-to-height ratio is within the healthy range."
                case .increased:
                    return "Your waist-to-height ratio indicates increased health risks."
                case .high:
                    return "Your waist-to-height ratio indicates high health risks."
                }
            }
            
            static func fromRatio(_ ratio: Double) -> WHtRCategory {
                if ratio < 0.5 {
                    return .normal
                } else if ratio < 0.6 {
                    return .increased
                } else {
                    return .high
                }
            }
        }
    }
    
    /// Calculates WHtR (waist-to-height ratio)
    /// - Parameters:
    ///   - waistCm: Waist circumference in centimeters
    ///   - heightCm: Height in centimeters
    /// - Returns: Result with category or nil if data is missing
    static func calculateWHtR(waistCm: Double?, heightCm: Double?) -> WHtRResult? {
        guard let waist = waistCm, let height = heightCm, height > 0 else {
            return nil
        }
        
        let ratio = waist / height
        let category = WHtRResult.WHtRCategory.fromRatio(ratio)
        
        return WHtRResult(ratio: ratio, category: category)
    }
    
    // MARK: - RFM (Relative Fat Mass)
    
    struct RFMResult {
        let rfm: Double
        let category: RFMCategory
        let gender: Gender
        
        enum RFMCategory: String {
            case normal = "Normal fat level"
            case increased = "Increased fat level"
            case high = "High fat level"
            
            var color: String {
                switch self {
                case .normal: return AppColorRoles.stateSuccessHex
                case .increased: return AppColorRoles.stateWarningHex
                case .high: return AppColorRoles.stateErrorHex
                }
            }
            
            var description: String {
                switch self {
                case .normal:
                    return "Your relative fat mass is within a healthy range."
                case .increased:
                    return "Your relative fat mass indicates increased body fat."
                case .high:
                    return "Your relative fat mass indicates high body fat."
                }
            }
            
            static func fromRFM(_ rfm: Double, gender: Gender) -> RFMCategory {
                switch gender {
                case .male:
                    if rfm < 20 {
                        return .normal
                    } else if rfm < 25 {
                        return .increased
                    } else {
                        return .high
                    }
                case .female:
                    // Higher thresholds for women (naturally higher fat %)
                    if rfm < 30 {
                        return .normal
                    } else if rfm < 35 {
                        return .increased
                    } else {
                        return .high
                    }
                case .notSpecified:
                    // Using male thresholds as more conservative
                    if rfm < 20 {
                        return .normal
                    } else if rfm < 25 {
                        return .increased
                    } else {
                        return .high
                    }
                }
            }
        }
    }
    
    /// Calculates RFM (Relative Fat Mass) - estimated body fat percentage
    /// - Parameters:
    ///   - waistCm: Waist circumference in centimeters
    ///   - heightCm: Height in centimeters
    ///   - gender: User's gender
    /// - Returns: Result with category or nil if data is missing
    static func calculateRFM(waistCm: Double?, heightCm: Double?, gender: Gender) -> RFMResult? {
        guard let waist = waistCm, let height = heightCm, height > 0 else {
            return nil
        }
        
        let rfm: Double
        switch gender {
        case .male:
            rfm = 64 - (20 * height / waist)
        case .female:
            rfm = 76 - (20 * height / waist)
        case .notSpecified:
            // Using the male formula
            rfm = 64 - (20 * height / waist)
        }
        
        let category = RFMResult.RFMCategory.fromRFM(rfm, gender: gender)
        return RFMResult(rfm: rfm, category: category, gender: gender)
    }
    
    // MARK: - WHR (waist-to-hip ratio)
    
    struct WHRResult {
        let ratio: Double
        let category: WHRCategory
        let gender: Gender
        
        enum WHRCategory: String {
            case lowRisk = "Low risk"
            case increasedRisk = "Increased risk"
            
            var color: String {
                switch self {
                case .lowRisk: return AppColorRoles.stateSuccessHex
                case .increasedRisk: return AppColorRoles.stateWarningHex
                }
            }
            
            var description: String {
                switch self {
                case .lowRisk:
                    return "Your waist-to-hip ratio is within the low-risk range."
                case .increasedRisk:
                    return "Your waist-to-hip ratio is above the low-risk threshold."
                }
            }
            
            static func fromRatio(_ ratio: Double, gender: Gender) -> WHRCategory {
                switch gender {
                case .male:
                    return ratio < 0.90 ? .lowRisk : .increasedRisk
                case .female:
                    return ratio < 0.85 ? .lowRisk : .increasedRisk
                case .notSpecified:
                    // Fallback to male threshold (consistent with RFM/ABSI/Conicity); production paths use the requiresGender wrapper.
                    return ratio < 0.90 ? .lowRisk : .increasedRisk
                }
            }
        }
    }
    
    /// Calculates WHR (waist-to-hip ratio)
    /// - Parameters:
    ///   - waistCm: Waist circumference in centimeters
    ///   - hipsCm: Hip circumference in centimeters
    ///   - gender: User's gender (affects category thresholds)
    /// - Returns: Result with category or nil if data is missing
    static func calculateWHR(waistCm: Double?, hipsCm: Double?, gender: Gender) -> WHRResult? {
        guard let waist = waistCm, let hips = hipsCm, hips > 0 else {
            return nil
        }
        
        let ratio = waist / hips
        let category = WHRResult.WHRCategory.fromRatio(ratio, gender: gender)
        
        return WHRResult(ratio: ratio, category: category, gender: gender)
    }
    
    // MARK: - BMI (Body Mass Index)
    
    struct BMIResult {
        let bmi: Double
        let category: BMICategory
        let age: Int?
        let ageGroup: AgeGroup
        
        enum AgeGroup {
            case child          // < 18 lat
            case adult          // 18-65 lat
            case senior         // > 65 lat
            
            static func from(age: Int?) -> AgeGroup {
                guard let age = age else { return .adult }
                if age < 18 { return .child }
                if age > 65 { return .senior }
                return .adult
            }
            
            var displayName: String {
                switch self {
                case .child: return AppLocalization.string("Child/Adolescent")
                case .adult: return AppLocalization.string("Adult")
                case .senior: return AppLocalization.string("Senior")
                }
            }
        }
        
        enum BMICategory: String {
            case underweight = "Underweight"
            case normal = "Normal weight"
            case overweight = "Overweight"
            case obese = "Obese"
            
            var color: String {
                switch self {
                case .underweight: return AppColorRoles.stateInfoHex
                case .normal: return AppColorRoles.stateSuccessHex
                case .overweight: return AppColorRoles.stateWarningHex
                case .obese: return AppColorRoles.stateErrorHex
                }
            }
            
            func description(for ageGroup: AgeGroup) -> String {
                switch self {
                case .underweight:
                    return ageGroup == .child 
                        ? "BMI is below the typical range for this age."
                        : "Your BMI is below the healthy range."
                case .normal:
                    return ageGroup == .child
                        ? "BMI is within the typical range for this age."
                        : "Your BMI is within the healthy range."
                case .overweight:
                    return ageGroup == .child
                        ? "BMI is above the typical range for this age."
                        : "Your BMI indicates overweight."
                case .obese:
                    return ageGroup == .child
                        ? "BMI is significantly above the typical range for this age."
                        : "Your BMI indicates obesity."
                }
            }
            
            static func fromBMI(_ bmi: Double, ageGroup: AgeGroup) -> BMICategory {
                switch ageGroup {
                case .child:
                    // For children BMI is more complex (percentiles)
                    // Using simplified thresholds - ideally percentile tables are needed
                    if bmi < 16.0 {
                        return .underweight
                    } else if bmi < 23.0 {
                        return .normal
                    } else if bmi < 27.0 {
                        return .overweight
                    } else {
                        return .obese
                    }
                    
                case .adult:
                    // Standard WHO thresholds for adults
                    if bmi < 18.5 {
                        return .underweight
                    } else if bmi < 25.0 {
                        return .normal
                    } else if bmi < 30.0 {
                        return .overweight
                    } else {
                        return .obese
                    }
                    
                case .senior:
                    // For seniors thresholds are slightly higher
                    // Mild overweight may be protective in older age
                    if bmi < 20.0 {
                        return .underweight
                    } else if bmi < 27.0 {
                        return .normal
                    } else if bmi < 32.0 {
                        return .overweight
                    } else {
                        return .obese
                    }
                }
            }
        }
    }
    
    /// Calculates BMI (Body Mass Index)
    /// - Parameters:
    ///   - weightKg: Weight in kilograms
    ///   - heightCm: Height in centimeters
    ///   - age: User's age (optional, affects interpretation)
    /// - Returns: Result with category or nil if data is missing
    static func calculateBMI(weightKg: Double?, heightCm: Double?, age: Int? = nil) -> BMIResult? {
        guard let weight = weightKg, let height = heightCm, height > 0 else {
            return nil
        }
        
        let heightM = height / 100.0
        let bmi = weight / (heightM * heightM)
        let ageGroup = BMIResult.AgeGroup.from(age: age)
        let category = BMIResult.BMICategory.fromBMI(bmi, ageGroup: ageGroup)
        
        return BMIResult(bmi: bmi, category: category, age: age, ageGroup: ageGroup)
    }

    // MARK: - Central Fat Risk (CFR)

    struct CentralFatRiskResult {
        let score: Double
        let category: Category

        enum Category: String {
            case low = "Low risk"
            case moderate = "Moderate risk"
            case high = "High risk"

            var color: String {
                switch self {
                case .low: return AppColorRoles.stateSuccessHex
                case .moderate: return AppColorRoles.stateWarningHex
                case .high: return AppColorRoles.stateErrorHex
                }
            }
        }
    }

    /// CFR = WHtR / 0.50 where 1.00 is the primary threshold.
    static func calculateCentralFatRisk(waistCm: Double?, heightCm: Double?) -> CentralFatRiskResult? {
        guard let whtr = calculateWHtR(waistCm: waistCm, heightCm: heightCm) else {
            return nil
        }
        let score = whtr.ratio / 0.50
        let category: CentralFatRiskResult.Category
        if score < 1.0 {
            category = .low
        } else if score <= 1.2 {
            category = .moderate
        } else {
            category = .high
        }
        return CentralFatRiskResult(score: score, category: category)
    }

    // MARK: - Waist Circumference Risk

    struct WaistRiskResult {
        let waistCm: Double
        let category: Category
        let gender: Gender

        enum Category: String {
            case low = "Low risk"
            case moderate = "Moderate risk"
            case high = "High risk"

            var color: String {
                switch self {
                case .low: return AppColorRoles.stateSuccessHex
                case .moderate: return AppColorRoles.stateWarningHex
                case .high: return AppColorRoles.stateErrorHex
                }
            }
        }
    }

    static func calculateWaistRisk(waistCm: Double?, gender: Gender) -> GenderDependentResult<WaistRiskResult>? {
        guard let waist = waistCm, waist > 0 else { return nil }
        guard gender != .notSpecified else { return .requiresGender }

        let category: WaistRiskResult.Category
        switch gender {
        case .male:
            if waist <= 94 {
                category = .low
            } else if waist <= 102 {
                category = .moderate
            } else {
                category = .high
            }
        case .female:
            if waist <= 80 {
                category = .low
            } else if waist <= 88 {
                category = .moderate
            } else {
                category = .high
            }
        case .notSpecified:
            return .requiresGender
        }

        return .value(WaistRiskResult(waistCm: waist, category: category, gender: gender))
    }

    // MARK: - Gender-dependent wrappers

    static func calculateRFMWithGenderRequirement(
        waistCm: Double?,
        heightCm: Double?,
        gender: Gender
    ) -> GenderDependentResult<RFMResult>? {
        guard waistCm != nil, heightCm != nil else { return nil }
        guard gender != .notSpecified else { return .requiresGender }
        guard let result = calculateRFM(waistCm: waistCm, heightCm: heightCm, gender: gender) else { return nil }
        return .value(result)
    }

    static func calculateWHRWithGenderRequirement(
        waistCm: Double?,
        hipsCm: Double?,
        gender: Gender
    ) -> GenderDependentResult<WHRResult>? {
        guard waistCm != nil, hipsCm != nil else { return nil }
        guard gender != .notSpecified else { return .requiresGender }
        guard let result = calculateWHR(waistCm: waistCm, hipsCm: hipsCm, gender: gender) else { return nil }
        return .value(result)
    }

    static func calculateABSIWithGenderRequirement(
        waistCm: Double?,
        heightCm: Double?,
        weightKg: Double?,
        gender: Gender
    ) -> GenderDependentResult<ABSIResult>? {
        guard waistCm != nil, heightCm != nil, weightKg != nil else { return nil }
        guard gender != .notSpecified else { return .requiresGender }
        guard let result = calculateABSI(waistCm: waistCm, heightCm: heightCm, weightKg: weightKg, gender: gender) else { return nil }
        return .value(result)
    }

    // MARK: - ABSI (A Body Shape Index)
    
    struct ABSIResult {
        let absi: Double
        let category: ABSICategory
        let gender: Gender
        
        enum ABSICategory: String {
            case low = "Low risk"
            case moderate = "Moderate risk"
            case high = "High risk"
            
            var color: String {
                switch self {
                case .low: return AppColorRoles.stateSuccessHex
                case .moderate: return AppColorRoles.stateWarningHex
                case .high: return AppColorRoles.stateErrorHex
                }
            }
            
            var description: String {
                switch self {
                case .low:
                    return "Your body shape indicates low health risk from abdominal fat distribution."
                case .moderate:
                    return "Your body shape indicates moderate health risk from abdominal fat distribution."
                case .high:
                    return "Your body shape indicates high health risk from abdominal fat distribution."
                }
            }
            
            static func fromABSI(_ absi: Double, gender: Gender) -> ABSICategory {
                switch gender {
                case .male:
                    if absi < 0.075 {
                        return .low
                    } else if absi < 0.085 {
                        return .moderate
                    } else {
                        return .high
                    }
                case .female:
                    // Women have slightly different thresholds
                    if absi < 0.070 {
                        return .low
                    } else if absi < 0.080 {
                        return .moderate
                    } else {
                        return .high
                    }
                case .notSpecified:
                    // Using male thresholds
                    if absi < 0.075 {
                        return .low
                    } else if absi < 0.085 {
                        return .moderate
                    } else {
                        return .high
                    }
                }
            }
        }
    }
    
    /// Calculates ABSI (A Body Shape Index) - weight-independent body shape index
    /// - Parameters:
    ///   - waistCm: Waist circumference in centimeters
    ///   - heightCm: Height in centimeters
    ///   - weightKg: Weight in kilograms
    ///   - gender: User's gender
    /// - Returns: Result with category or nil if data is missing
    static func calculateABSI(waistCm: Double?, heightCm: Double?, weightKg: Double?, gender: Gender) -> ABSIResult? {
        guard let waist = waistCm, 
              let height = heightCm, 
              let weight = weightKg,
              height > 0,
              weight > 0 else {
            return nil
        }
        
        // Convert to meters
        let waistM = waist / 100.0
        let heightM = height / 100.0

        // BMI
        let bmi = weight / (heightM * heightM)

        // ABSI = waist / (BMI^(2/3) × height^(1/2))
        let absi = waistM / (pow(bmi, 2.0/3.0) * sqrt(heightM))
        
        let category = ABSIResult.ABSICategory.fromABSI(absi, gender: gender)
        return ABSIResult(absi: absi, category: category, gender: gender)
    }

    // MARK: - Body Shape Risk (standardized ABSI z-score)

    struct BodyShapeRiskResult {
        let score: Double
        let zScore: Double
        let category: Category
        let gender: Gender
        let absi: Double

        enum Category: String {
            case low = "Low risk"
            case moderate = "Moderate risk"
            case high = "High risk"

            var color: String {
                switch self {
                case .low: return AppColorRoles.stateSuccessHex
                case .moderate: return AppColorRoles.stateWarningHex
                case .high: return AppColorRoles.stateErrorHex
                }
            }
        }
    }

    /// ABSI reference constants used to standardize to z-score.
    /// Source baseline: Krakauer et al. population-level ABSI distributions.
    private struct ABSIReference {
        let mean: Double
        let stdDev: Double

        static func forGender(_ gender: Gender) -> ABSIReference? {
            switch gender {
            case .male:
                return ABSIReference(mean: 0.0807, stdDev: 0.0053)
            case .female:
                return ABSIReference(mean: 0.0799, stdDev: 0.0057)
            case .notSpecified:
                return nil
            }
        }
    }

    static func calculateBodyShapeRisk(
        waistCm: Double?,
        heightCm: Double?,
        weightKg: Double?,
        gender: Gender
    ) -> GenderDependentResult<BodyShapeRiskResult>? {
        guard waistCm != nil, heightCm != nil, weightKg != nil else { return nil }
        guard gender != .notSpecified else { return .requiresGender }
        guard let absi = calculateABSI(waistCm: waistCm, heightCm: heightCm, weightKg: weightKg, gender: gender)?.absi,
              let reference = ABSIReference.forGender(gender),
              reference.stdDev > 0 else {
            return nil
        }

        let zScore = (absi - reference.mean) / reference.stdDev
        let category: BodyShapeRiskResult.Category
        if zScore < -0.272 {
            category = .low
        } else if zScore <= 0.229 {
            category = .moderate
        } else {
            category = .high
        }

        let score = max(0.0, min(2.0, 1.0 + (zScore / 2.0)))
        return .value(
            BodyShapeRiskResult(
                score: score,
                zScore: zScore,
                category: category,
                gender: gender,
                absi: absi
            )
        )
    }

    // MARK: - Conicity Index
    
    struct ConicityResult {
        let conicity: Double
        let category: ConicityCategory
        let gender: Gender
        
        enum ConicityCategory: String {
            case low = "Low risk"
            case moderate = "Moderate risk"
            case high = "High risk"
            
            var color: String {
                switch self {
                case .low: return AppColorRoles.stateSuccessHex
                case .moderate: return AppColorRoles.stateWarningHex
                case .high: return AppColorRoles.stateErrorHex
                }
            }
            
            var description: String {
                switch self {
                case .low:
                    return "Your central fat distribution indicates low health risk."
                case .moderate:
                    return "Your central fat distribution indicates moderate health risk."
                case .high:
                    return "Your central fat distribution indicates high health risk."
                }
            }
            
            static func fromConicity(_ conicity: Double, gender: Gender) -> ConicityCategory {
                switch gender {
                case .male:
                    if conicity < 1.20 {
                        return .low
                    } else if conicity < 1.30 {
                        return .moderate
                    } else {
                        return .high
                    }
                case .female:
                    // Women have slightly lower thresholds
                    if conicity < 1.15 {
                        return .low
                    } else if conicity < 1.25 {
                        return .moderate
                    } else {
                        return .high
                    }
                case .notSpecified:
                    // Using male thresholds
                    if conicity < 1.20 {
                        return .low
                    } else if conicity < 1.30 {
                        return .moderate
                    } else {
                        return .high
                    }
                }
            }
        }
    }
    
    /// Calculates Conicity Index - central fat distribution indicator
    /// - Parameters:
    ///   - waistCm: Waist circumference in centimeters
    ///   - heightCm: Height in centimeters
    ///   - weightKg: Weight in kilograms
    ///   - gender: User's gender
    /// - Returns: Result with category or nil if data is missing
    static func calculateConicity(waistCm: Double?, heightCm: Double?, weightKg: Double?, gender: Gender) -> ConicityResult? {
        guard let waist = waistCm,
              let height = heightCm,
              let weight = weightKg,
              height > 0,
              weight > 0 else {
            return nil
        }
        
        // Convert to meters
        let waistM = waist / 100.0
        let heightM = height / 100.0

        // Conicity = waist / (0.109 × sqrt(weight / height))
        let conicity = waistM / (0.109 * sqrt(weight / heightM))
        
        let category = ConicityResult.ConicityCategory.fromConicity(conicity, gender: gender)
        return ConicityResult(conicity: conicity, category: category, gender: gender)
    }
    
    // MARK: - Missing Data Helper
    
    /// Checks which data is missing for calculating indicators
    /// - Parameters:
    ///   - waist: Waist circumference (optional)
    ///   - height: Height (optional)
    ///   - weight: Weight (optional)
    ///   - bodyFat: Body fat percentage (optional)
    ///   - leanMass: Lean body mass (optional)
    /// - Returns: List of missing metrics
    static func missingMetrics(
        waist: Double?,
        height: Double?,
        weight: Double?,
        bodyFat: Double? = nil,
        leanMass: Double? = nil
    ) -> [String] {
        var missing: [String] = []
        
        if waist == nil {
            missing.append("Waist circumference")
        }
        if height == nil {
            missing.append("Height")
        }
        if weight == nil {
            missing.append("Weight")
        }
        
        return missing
    }
    
    /// Checks whether Body Composition data is available
    static func hasBodyComposition(bodyFat: Double?, leanMass: Double?) -> Bool {
        bodyFat != nil || leanMass != nil
    }
}

// MARK: - Health Metrics Reference Data

struct HealthMetricsReference {
    
    // MARK: - WHtR Reference

    static let whtrRanges: [(title: String, range: String, description: String)] = [
        ("Normal weight", "< 0.5", "Low health risk"),
        ("Increased weight", "0.5 - 0.6", "Increased health risk"),
        ("High weight", "> 0.6", "High health risk")
    ]
    
    // MARK: - WHR Reference

    static let whrRangesMale: [(title: String, range: String, description: String)] = [
        ("Low risk", "< 0.90", "Low health risk"),
        ("Increased risk", ">= 0.90", "Moderate health risk")
    ]
    
    static let whrRangesFemale: [(title: String, range: String, description: String)] = [
        ("Low risk", "< 0.85", "Low health risk"),
        ("Increased risk", ">= 0.85", "Moderate health risk")
    ]
    
    // MARK: - BMI Reference

    static let bmiRangesAdult: [(title: String, range: String, description: String)] = [
        ("Underweight", "< 18.5", "Below healthy weight"),
        ("Normal weight", "18.5 - 25.0", "Healthy weight range"),
        ("Overweight", "25.0 - 30.0", "Above healthy weight"),
        ("Obese", "> 30.0", "High health risk")
    ]
    
    static let bmiRangesSenior: [(title: String, range: String, description: String)] = [
        ("Underweight", "< 20.0", "Below healthy weight"),
        ("Normal weight", "20.0 - 27.0", "Healthy weight range"),
        ("Overweight", "27.0 - 32.0", "Above healthy weight"),
        ("Obese", "> 32.0", "High health risk")
    ]
    
    static let bmiRangesChild: [(title: String, range: String, description: String)] = [
        ("Underweight", "< 16.0", "Below typical range"),
        ("Normal weight", "16.0 - 23.0", "Typical range"),
        ("Overweight", "23.0 - 27.0", "Above typical range"),
        ("Obese", "> 27.0", "Significantly above range")
    ]
    
    static func bmiRanges(for ageGroup: HealthMetricsCalculator.BMIResult.AgeGroup) -> [(title: String, range: String, description: String)] {
        switch ageGroup {
        case .child: return bmiRangesChild
        case .adult: return bmiRangesAdult
        case .senior: return bmiRangesSenior
        }
    }
}
