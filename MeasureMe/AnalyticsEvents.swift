import Foundation

nonisolated struct AnalyticsEvent: Equatable {
    let name: String
    let parameters: [String: String]
}

nonisolated enum AnalyticsBool {
    static func string(_ value: Bool) -> String {
        value ? "true" : "false"
    }
}

nonisolated enum AnalyticsEventName {
    enum Onboarding {
        static let sessionStarted = "com.jacekzieba.measureme.onboarding.session_started"
        static let stepViewed = "com.jacekzieba.measureme.onboarding.step_viewed"
        static let stepCompleted = "com.jacekzieba.measureme.onboarding.step_completed"
        static let stepSkipped = "com.jacekzieba.measureme.onboarding.step_skipped"
        static let prioritySelected = "com.jacekzieba.measureme.onboarding.priority_selected"
        static let metricPackApplied = "com.jacekzieba.measureme.onboarding.metric_pack_applied"
        static let healthPermissionPrompted = "com.jacekzieba.measureme.onboarding.health_permission_prompted"
        static let healthPermissionResolved = "com.jacekzieba.measureme.onboarding.health_permission_resolved"
        static let completed = "com.jacekzieba.measureme.onboarding.completed"
    }

    enum Activation {
        static let taskViewed = "com.jacekzieba.measureme.activation.task_viewed"
        static let taskStarted = "com.jacekzieba.measureme.activation.task_started"
        static let taskCompleted = "com.jacekzieba.measureme.activation.task_completed"
        static let taskSkipped = "com.jacekzieba.measureme.activation.task_skipped"
        static let completed = "com.jacekzieba.measureme.activation.completed"
    }

    enum Checklist {
        static let itemViewed = "com.jacekzieba.measureme.checklist.item_viewed"
        static let itemStarted = "com.jacekzieba.measureme.checklist.item_started"
        static let itemCompleted = "com.jacekzieba.measureme.checklist.item_completed"
    }

    enum Measurement {
        static let saved = "com.jacekzieba.measureme.measurement.saved"
    }

    enum Photo {
        static let addStarted = "com.jacekzieba.measureme.photo.add_started"
        static let addCompleted = "com.jacekzieba.measureme.photo.add_completed"
    }

    enum Paywall {
        static let presented = "com.jacekzieba.measureme.paywall.presented"
        static let slideSeen = "com.jacekzieba.measureme.paywall.slide_seen"
        static let planSelected = "com.jacekzieba.measureme.paywall.plan_selected"
        static let ctaTapped = "com.jacekzieba.measureme.paywall.cta_tapped"
        static let closed = "com.jacekzieba.measureme.paywall.closed"
        static let restoreTapped = "com.jacekzieba.measureme.paywall.restore_tapped"
        static let purchaseStarted = "com.jacekzieba.measureme.paywall.purchase_started"
        static let purchaseCancelled = "com.jacekzieba.measureme.paywall.purchase_cancelled"
    }

    enum PremiumPrompt {
        static let softPromptSeen = "com.jacekzieba.measureme.premium.soft_prompt_seen"
        static let softPromptDismissed = "com.jacekzieba.measureme.premium.soft_prompt_dismissed"
    }

    enum Notifications {
        static let permissionPrompted = "com.jacekzieba.measureme.notifications.permission_prompted"
        static let permissionResolved = "com.jacekzieba.measureme.notifications.permission_resolved"
    }

    enum Reminders {
        static let seeded = "com.jacekzieba.measureme.reminders.seeded"
    }

    enum AIInsight {
        static let generated = "com.jacekzieba.measureme.ai_insight.generated"
        static let fallback = "com.jacekzieba.measureme.ai_insight.fallback"
        static let refreshed = "com.jacekzieba.measureme.ai_insight.refreshed"
        static let expanded = "com.jacekzieba.measureme.ai_insight.expanded"
    }
}

nonisolated enum AIInsightKind: String {
    case metric
    case health
    case section
}

/// Why a generated insight was replaced by a deterministic fallback.
nonisolated enum AIInsightFallbackReason: String {
    case insufficientSamples = "insufficient_samples"
    case timeout
    case generationError = "generation_error"
    case validationEmpty = "validation_empty"
    case validationLength = "validation_length"
    case validationDisallowedLanguage = "validation_disallowed_language"
    case validationHallucinatedNumber = "validation_hallucinated_number"
    case validationContradiction = "validation_contradiction"
    case validationNoSpecifics = "validation_no_specifics"
}

nonisolated enum MeasurementTelemetrySource: String {
    case onboarding
    case activation
    case quickAdd = "quick_add"
    case widget
    case watch
    case intent
}

nonisolated enum PhotoTelemetrySource: String {
    case activation
    case photos
    case multiImport = "multi_import"
}

nonisolated enum PaywallTelemetrySource: String {
    case onboarding
    case activation
    case checklist
    case settings
    case feature
}

nonisolated enum NotificationTelemetrySource: String {
    case activation
    case checklist
}

nonisolated enum ReminderTelemetrySource: String {
    case activation
}

nonisolated enum AnalyticsEvents {
    static let onboardingFlowVersion = "4"

    static func onboardingSessionStarted(entrypoint: String, restoredState: Bool) -> AnalyticsEvent {
        AnalyticsEvent(
            name: AnalyticsEventName.Onboarding.sessionStarted,
            parameters: [
                "flow_version": onboardingFlowVersion,
                "entrypoint": entrypoint,
                "restored_state": AnalyticsBool.string(restoredState)
            ]
        )
    }

    static func onboardingStepViewed(step: String, stepIndex: Int, stepCount: Int) -> AnalyticsEvent {
        AnalyticsEvent(
            name: AnalyticsEventName.Onboarding.stepViewed,
            parameters: [
                "flow_version": onboardingFlowVersion,
                "step": step,
                "step_index": String(stepIndex),
                "step_count": String(stepCount)
            ]
        )
    }

    static func onboardingStepCompleted(step: String, stepIndex: Int) -> AnalyticsEvent {
        AnalyticsEvent(
            name: AnalyticsEventName.Onboarding.stepCompleted,
            parameters: [
                "flow_version": onboardingFlowVersion,
                "step": step,
                "step_index": String(stepIndex)
            ]
        )
    }

    static func onboardingStepSkipped(step: String, stepIndex: Int, skipReason: String) -> AnalyticsEvent {
        AnalyticsEvent(
            name: AnalyticsEventName.Onboarding.stepSkipped,
            parameters: [
                "flow_version": onboardingFlowVersion,
                "step": step,
                "step_index": String(stepIndex),
                "skip_reason": skipReason
            ]
        )
    }

    static func onboardingPrioritySelected(priority: String) -> AnalyticsEvent {
        AnalyticsEvent(
            name: AnalyticsEventName.Onboarding.prioritySelected,
            parameters: [
                "flow_version": onboardingFlowVersion,
                "priority": priority
            ]
        )
    }

    static func onboardingMetricPackApplied(priority: String, packID: String, metricsCount: Int, customizedMetricsBefore: Bool) -> AnalyticsEvent {
        AnalyticsEvent(
            name: AnalyticsEventName.Onboarding.metricPackApplied,
            parameters: [
                "flow_version": onboardingFlowVersion,
                "priority": priority,
                "pack_id": packID,
                "metrics_count": String(metricsCount),
                "customized_metrics_before": AnalyticsBool.string(customizedMetricsBefore)
            ]
        )
    }

    static func onboardingHealthPermissionPrompted(source: String) -> AnalyticsEvent {
        AnalyticsEvent(
            name: AnalyticsEventName.Onboarding.healthPermissionPrompted,
            parameters: [
                "flow_version": onboardingFlowVersion,
                "source": source
            ]
        )
    }

    static func onboardingHealthPermissionResolved(source: String, result: String, importedAge: Bool, importedHeight: Bool) -> AnalyticsEvent {
        AnalyticsEvent(
            name: AnalyticsEventName.Onboarding.healthPermissionResolved,
            parameters: [
                "flow_version": onboardingFlowVersion,
                "source": source,
                "result": result,
                "imported_age": AnalyticsBool.string(importedAge),
                "imported_height": AnalyticsBool.string(importedHeight)
            ]
        )
    }

    static func onboardingCompleted(priority: String, healthConnected: Bool, completedAllSteps: Bool) -> AnalyticsEvent {
        AnalyticsEvent(
            name: AnalyticsEventName.Onboarding.completed,
            parameters: [
                "flow_version": onboardingFlowVersion,
                "priority": priority,
                "health_connected": AnalyticsBool.string(healthConnected),
                "completed_all_steps": AnalyticsBool.string(completedAllSteps)
            ]
        )
    }

    static func activationTaskViewed(task: String, position: Int, source: String) -> AnalyticsEvent {
        AnalyticsEvent(
            name: AnalyticsEventName.Activation.taskViewed,
            parameters: [
                "task": task,
                "position": String(position),
                "source": source
            ]
        )
    }

    static func activationTaskStarted(task: String) -> AnalyticsEvent {
        AnalyticsEvent(
            name: AnalyticsEventName.Activation.taskStarted,
            parameters: ["task": task]
        )
    }

    static func activationTaskCompleted(task: String) -> AnalyticsEvent {
        AnalyticsEvent(
            name: AnalyticsEventName.Activation.taskCompleted,
            parameters: ["task": task]
        )
    }

    static func activationTaskSkipped(task: String, skipReason: String) -> AnalyticsEvent {
        AnalyticsEvent(
            name: AnalyticsEventName.Activation.taskSkipped,
            parameters: [
                "task": task,
                "skip_reason": skipReason
            ]
        )
    }

    static func activationCompleted(completedTasksCount: Int, skippedTasksCount: Int) -> AnalyticsEvent {
        AnalyticsEvent(
            name: AnalyticsEventName.Activation.completed,
            parameters: [
                "completed_tasks_count": String(completedTasksCount),
                "skipped_tasks_count": String(skippedTasksCount)
            ]
        )
    }

    static func checklistItemViewed(item: String, source: String, task: String? = nil) -> AnalyticsEvent {
        checklistEvent(name: AnalyticsEventName.Checklist.itemViewed, item: item, source: source, task: task)
    }

    static func checklistItemStarted(item: String, source: String, task: String? = nil) -> AnalyticsEvent {
        checklistEvent(name: AnalyticsEventName.Checklist.itemStarted, item: item, source: source, task: task)
    }

    static func checklistItemCompleted(item: String, source: String, task: String? = nil) -> AnalyticsEvent {
        checklistEvent(name: AnalyticsEventName.Checklist.itemCompleted, item: item, source: source, task: task)
    }

    static func measurementSaved(source: MeasurementTelemetrySource, metricsCount: Int, isFirstMeasurement: Bool) -> AnalyticsEvent {
        AnalyticsEvent(
            name: AnalyticsEventName.Measurement.saved,
            parameters: [
                "source": source.rawValue,
                "metrics_count": String(metricsCount),
                "is_first_measurement": AnalyticsBool.string(isFirstMeasurement)
            ]
        )
    }

    static func photoAddStarted(source: PhotoTelemetrySource) -> AnalyticsEvent {
        AnalyticsEvent(
            name: AnalyticsEventName.Photo.addStarted,
            parameters: ["source": source.rawValue]
        )
    }

    static func photoAddCompleted(source: PhotoTelemetrySource, isFirstPhoto: Bool) -> AnalyticsEvent {
        AnalyticsEvent(
            name: AnalyticsEventName.Photo.addCompleted,
            parameters: [
                "source": source.rawValue,
                "is_first_photo": AnalyticsBool.string(isFirstPhoto)
            ]
        )
    }

    static func paywallPresented(source: PaywallTelemetrySource, reason: String) -> AnalyticsEvent {
        AnalyticsEvent(
            name: AnalyticsEventName.Paywall.presented,
            parameters: [
                "source": source.rawValue,
                "reason": reason
            ]
        )
    }

    static func paywallSlideSeen(slideID: String, context: String) -> AnalyticsEvent {
        AnalyticsEvent(
            name: AnalyticsEventName.Paywall.slideSeen,
            parameters: ["slide_id": slideID, "context": context]
        )
    }

    static func paywallPlanSelected(planID: String, context: String) -> AnalyticsEvent {
        AnalyticsEvent(
            name: AnalyticsEventName.Paywall.planSelected,
            parameters: ["plan_id": planID, "context": context]
        )
    }

    static func paywallCTATapped(planID: String, context: String) -> AnalyticsEvent {
        AnalyticsEvent(
            name: AnalyticsEventName.Paywall.ctaTapped,
            parameters: ["plan_id": planID, "context": context]
        )
    }

    static func paywallClosed(context: String) -> AnalyticsEvent {
        AnalyticsEvent(
            name: AnalyticsEventName.Paywall.closed,
            parameters: ["context": context]
        )
    }

    static func paywallRestoreTapped(context: String) -> AnalyticsEvent {
        AnalyticsEvent(
            name: AnalyticsEventName.Paywall.restoreTapped,
            parameters: ["context": context]
        )
    }

    static func paywallPurchaseStarted(planID: String, context: String) -> AnalyticsEvent {
        AnalyticsEvent(
            name: AnalyticsEventName.Paywall.purchaseStarted,
            parameters: ["plan_id": planID, "context": context]
        )
    }

    static func paywallPurchaseCancelled(planID: String, context: String) -> AnalyticsEvent {
        AnalyticsEvent(
            name: AnalyticsEventName.Paywall.purchaseCancelled,
            parameters: ["plan_id": planID, "context": context]
        )
    }

    static func premiumSoftPromptSeen(promptType: String) -> AnalyticsEvent {
        AnalyticsEvent(
            name: AnalyticsEventName.PremiumPrompt.softPromptSeen,
            parameters: ["prompt_type": promptType]
        )
    }

    static func premiumSoftPromptDismissed(promptType: String) -> AnalyticsEvent {
        AnalyticsEvent(
            name: AnalyticsEventName.PremiumPrompt.softPromptDismissed,
            parameters: ["prompt_type": promptType]
        )
    }

    static func notificationsPermissionPrompted(source: NotificationTelemetrySource) -> AnalyticsEvent {
        AnalyticsEvent(
            name: AnalyticsEventName.Notifications.permissionPrompted,
            parameters: ["source": source.rawValue]
        )
    }

    static func notificationsPermissionResolved(source: NotificationTelemetrySource, result: String) -> AnalyticsEvent {
        AnalyticsEvent(
            name: AnalyticsEventName.Notifications.permissionResolved,
            parameters: [
                "source": source.rawValue,
                "result": result
            ]
        )
    }

    static func remindersSeeded(source: ReminderTelemetrySource, repeatRule: ReminderRepeat) -> AnalyticsEvent {
        AnalyticsEvent(
            name: AnalyticsEventName.Reminders.seeded,
            parameters: [
                "source": source.rawValue,
                "repeat_rule": repeatRule.rawValue
            ]
        )
    }

    static func aiInsightGenerated(
        kind: AIInsightKind,
        metric: String,
        promptVersion: String,
        shortLength: Int,
        detailedLength: Int,
        validated: Bool
    ) -> AnalyticsEvent {
        AnalyticsEvent(
            name: AnalyticsEventName.AIInsight.generated,
            parameters: [
                "kind": kind.rawValue,
                "metric": metric,
                "prompt_version": promptVersion,
                "length_short": String(shortLength),
                "length_detailed": String(detailedLength),
                "validated": AnalyticsBool.string(validated)
            ]
        )
    }

    static func aiInsightFallback(
        kind: AIInsightKind,
        metric: String,
        reason: AIInsightFallbackReason
    ) -> AnalyticsEvent {
        AnalyticsEvent(
            name: AnalyticsEventName.AIInsight.fallback,
            parameters: [
                "kind": kind.rawValue,
                "metric": metric,
                "reason": reason.rawValue
            ]
        )
    }

    static func aiInsightRefreshed(kind: AIInsightKind, sectionID: String) -> AnalyticsEvent {
        AnalyticsEvent(
            name: AnalyticsEventName.AIInsight.refreshed,
            parameters: [
                "kind": kind.rawValue,
                "section_id": sectionID
            ]
        )
    }

    static func aiInsightExpanded(kind: AIInsightKind, metric: String, expanded: Bool) -> AnalyticsEvent {
        AnalyticsEvent(
            name: AnalyticsEventName.AIInsight.expanded,
            parameters: [
                "kind": kind.rawValue,
                "metric": metric,
                "expanded": AnalyticsBool.string(expanded)
            ]
        )
    }

    private static func checklistEvent(name: String, item: String, source: String, task: String?) -> AnalyticsEvent {
        var parameters: [String: String] = [
            "item": item,
            "source": source
        ]
        if let task {
            parameters["task"] = task
        }
        return AnalyticsEvent(name: name, parameters: parameters)
    }
}

extension AnalyticsClient {
    func track(_ event: AnalyticsEvent) {
        track(signalName: event.name, parameters: event.parameters)
    }
}
