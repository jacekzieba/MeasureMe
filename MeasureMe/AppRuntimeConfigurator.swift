import SwiftUI
import UIKit
import RevenueCat

enum AppRuntimeConfigurator {
    @MainActor
    static func configureInitialServices(
        isRunningXCTest: Bool,
        isUnitTestHostMode: Bool,
        configureUITestDefaults: () -> Void,
        registerBackgroundTasks: () -> Void
    ) {
        if !isRunningXCTest {
            CrashReporter.shared.install()
        }

        if !isUnitTestHostMode {
            configureUITestDefaults()
            registerBackgroundTasks()
        }

        configureGlobalAppearance()
        installTextFieldSelectionBehaviorIfNeeded(isUnitTestHostMode: isUnitTestHostMode)
    }

    @MainActor
    static func configureDeferredServicesIfNeeded() {
        guard !didConfigureDeferredServices else { return }
        didConfigureDeferredServices = true

        let isRunningXCTest = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        configureRevenueCatIfNeeded(isRunningXCTest: isRunningXCTest)

        if !isRunningXCTest {
            Analytics.shared.setup()
            Analytics.shared.track(.appLaunched)
        }
    }

    @MainActor
    private static var didConfigureDeferredServices = false

    private enum RevenueCatConfig {
        #if DEBUG
        static let testStoreAPIKey = "test_IqhDylvTOfSwcULqzOlKpGIXmEa"
        #endif
        static let appStoreAPIKey = "appl_wTCpVzaoTfaUEHWONdHdqWyBnsr"

        static var apiKey: String {
            #if DEBUG
            let useTestStore = ProcessInfo.processInfo.environment["MEASUREME_RC_TEST_STORE"] == "1"
            if useTestStore { return testStoreAPIKey }
            #endif
            return appStoreAPIKey
        }
    }

    private static func configureRevenueCatIfNeeded(isRunningXCTest: Bool) {
        guard !isRunningXCTest, !Purchases.isConfigured else { return }
        #if DEBUG
        Purchases.logLevel = .debug
        #endif
        Purchases.configure(withAPIKey: RevenueCatConfig.apiKey)
    }

    private static func installTextFieldSelectionBehaviorIfNeeded(isUnitTestHostMode: Bool) {
        guard !isUnitTestHostMode else { return }

        NotificationCenter.default.addObserver(
            forName: UITextField.textDidBeginEditingNotification,
            object: nil,
            queue: .main
        ) { notification in
            if let textField = notification.object as? UITextField {
                DispatchQueue.main.async { textField.selectAll(nil) }
            }
        }
    }

    private static func configureGlobalAppearance() {
        let navTitleBase = UIFont.systemFont(ofSize: 17, weight: .semibold)
        let navLargeBase = UIFont.systemFont(ofSize: 34, weight: .bold)
        let navTitleFont = navTitleBase.fontDescriptor.withDesign(.rounded)
            .map { UIFont(descriptor: $0, size: navTitleBase.pointSize) } ?? navTitleBase
        let navLargeFont = navLargeBase.fontDescriptor.withDesign(.rounded)
            .map { UIFont(descriptor: $0, size: navLargeBase.pointSize) } ?? navLargeBase

        configureGlobalUIKitAppearance()
        configureNavigationAppearance(
            titleFont: navTitleFont,
            largeTitleFont: navLargeFont
        )
    }

    private static func configureGlobalUIKitAppearance() {
        let segmentedFont = UIFont.systemFont(ofSize: 13, weight: .semibold).withMonospacedDigits()
        let segmented = UISegmentedControl.appearance()
        segmented.backgroundColor = UIColor(AppColorRoles.surfaceInteractive)
        segmented.setTitleTextAttributes(
            [.font: segmentedFont, .foregroundColor: UIColor(AppColorRoles.textSecondary)],
            for: .normal
        )
        segmented.setTitleTextAttributes(
            [.font: segmentedFont, .foregroundColor: UIColor(AppColorRoles.textOnAccent)],
            for: .selected
        )
        segmented.selectedSegmentTintColor = UIColor(Color.appAccent)

        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        tabBarAppearance.backgroundColor = UIColor(AppColorRoles.surfaceChrome)
        tabBarAppearance.shadowColor = UIColor(AppColorRoles.borderSubtle)

        let selectedItemColor = UIColor(Color.appAccent)
        let normalItemColor = UIColor(AppColorRoles.textTertiary)
        let itemAppearances = [
            tabBarAppearance.stackedLayoutAppearance,
            tabBarAppearance.inlineLayoutAppearance,
            tabBarAppearance.compactInlineLayoutAppearance
        ]
        for itemAppearance in itemAppearances {
            itemAppearance.normal.iconColor = normalItemColor
            itemAppearance.normal.titleTextAttributes = [.foregroundColor: normalItemColor]
            itemAppearance.selected.iconColor = selectedItemColor
            itemAppearance.selected.titleTextAttributes = [.foregroundColor: selectedItemColor]
        }

        let tabBar = UITabBar.appearance()
        tabBar.standardAppearance = tabBarAppearance
        tabBar.scrollEdgeAppearance = tabBarAppearance
        tabBar.tintColor = selectedItemColor
        tabBar.unselectedItemTintColor = normalItemColor
    }

    private static func configureNavigationAppearance(
        titleFont: UIFont,
        largeTitleFont: UIFont
    ) {
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithOpaqueBackground()
        navAppearance.backgroundEffect = nil
        navAppearance.backgroundColor = UIColor(AppColorRoles.surfaceChrome)
        navAppearance.shadowColor = UIColor(AppColorRoles.borderSubtle)
        navAppearance.titleTextAttributes = [
            .font: titleFont,
            .foregroundColor: UIColor(AppColorRoles.textPrimary)
        ]
        navAppearance.largeTitleTextAttributes = [
            .font: largeTitleFont,
            .foregroundColor: UIColor(AppColorRoles.textPrimary)
        ]

        let navBar = UINavigationBar.appearance()
        navBar.standardAppearance = navAppearance
        navBar.scrollEdgeAppearance = navAppearance
        navBar.compactAppearance = navAppearance
        navBar.compactScrollEdgeAppearance = navAppearance
        navBar.tintColor = UIColor(Color.appAccent)
        navBar.titleTextAttributes = navAppearance.titleTextAttributes
        navBar.largeTitleTextAttributes = navAppearance.largeTitleTextAttributes
        navBar.shadowImage = UIImage()
    }
}
