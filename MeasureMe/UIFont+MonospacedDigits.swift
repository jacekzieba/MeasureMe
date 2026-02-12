import UIKit

extension UIFont {
    func withMonospacedDigits() -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([
            .featureSettings: [
                [
                    UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                    UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector
                ]
            ]
        ])
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
