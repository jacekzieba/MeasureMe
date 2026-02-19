import SwiftUI

let settingsCardCornerRadius: CGFloat = 18
let settingsRowInsets = EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)

enum LegalLinks {
    static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacyPolicy = URL(string: "https://jacekzieba.pl/privacy.html")!
    static let accessibility = URL(string: "https://jacekzieba.pl/accessibility")!
    static let about = URL(string: "https://jacekzieba.pl/measureme")!
    static let featureRequest = URL(string: "https://measureme.userjot.com/")!
}
