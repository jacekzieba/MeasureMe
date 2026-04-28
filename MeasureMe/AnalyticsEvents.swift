import Foundation

struct AnalyticsEvent: Equatable {
    let name: String
    let parameters: [String: String]
}

enum AnalyticsBool {
    static func string(_ value: Bool) -> String {
        value ? "true" : "false"
    }
}

enum AnalyticsEventName {
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
    }

    enum Notifications {
        static let permissionPrompted = "com.jacekzieba.measureme.notifications.permission_prompted"
        static let permissionResolved = "com.jacekzieba.measureme.notifications.permission_resolved"
    }

    enum Reminders {
        static let seeded = "com.jacekzieba.measureme.reminders.seeded"
    }
}

enum MeasurementTelemetrySource: String {
    case onboarding
    case activation
    case quickAdd = "quick_add"
    case widget
    case watch
    case intent
}

enum PhotoTelemetrySource: String {
    case activation
    case photos
    case multiImport = "multi_import"
}

enum PaywallTelemetrySource: String {
    case onboarding
    case activation
    case checklist
    case settings
    case feature
}

enum NotificationTelemetrySource: String {
    case activation
    case checklist
}

enum ReminderTelemetrySource: String {
    case activation
}

enum AnalyticsEvents {
    static let onboardingFlowVersion = "3"

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
