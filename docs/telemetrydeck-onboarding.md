# TelemetryDeck Runbook

## Source of Truth
- Event catalog: `MeasureMe/AnalyticsEvents.swift`
- Legacy direct signals still in active use: `MeasureMe/AnalyticsClient.swift`
- Current onboarding flow version: `4`
- New telemetry should use `Analytics.shared.track(AnalyticsEvent)` unless it is one of the remaining app/tab/first-value direct signals.

## Privacy Rules
- Do not send user name, exact age, height, weight, body-fat, notes, file names, or photo metadata.
- Keep values low-cardinality: sources, results, task IDs, step IDs, booleans, counts, and stable product IDs are allowed.
- Do not send free-form user text.
- Prefer one generic event plus parameters over many per-screen event names.

## Active Event Catalog

### App and Navigation
- `com.jacekzieba.measureme.app.launched`
  - Meaning: app runtime services were configured after launch.
- `com.jacekzieba.measureme.app.first_frame_ready`
  - Meaning: first visible app frame was rendered.
- `com.jacekzieba.measureme.tab.home.selected`
- `com.jacekzieba.measureme.tab.measurements.selected`
- `com.jacekzieba.measureme.tab.photos.selected`
- `com.jacekzieba.measureme.tab.settings.selected`
  - Meaning: user selected the corresponding main tab.

### Onboarding
- `com.jacekzieba.measureme.onboarding.session_started`
  - Parameters: `flow_version`, `entrypoint`, `restored_state`
  - Funnel role: onboarding top-of-funnel.
- `com.jacekzieba.measureme.onboarding.step_viewed`
  - Parameters: `flow_version`, `step`, `step_index`, `step_count`
  - Funnel role: step exposure.
- `com.jacekzieba.measureme.onboarding.step_completed`
  - Parameters: `flow_version`, `step`, `step_index`
  - Funnel role: step conversion.
- `com.jacekzieba.measureme.onboarding.step_skipped`
  - Parameters: `flow_version`, `step`, `step_index`, `skip_reason`
  - Funnel role: explicit skip path.
- `com.jacekzieba.measureme.onboarding.priority_selected`
  - Parameters: `flow_version`, `priority`
  - Funnel role: goal/intent segmentation.
- `com.jacekzieba.measureme.onboarding.metric_pack_applied`
  - Parameters: `flow_version`, `priority`, `pack_id`, `metrics_count`, `customized_metrics_before`
  - Funnel role: recommended metrics adoption.
- `com.jacekzieba.measureme.onboarding.health_permission_prompted`
  - Parameters: `flow_version`, `source`
  - Funnel role: onboarding Health permission prompt exposure.
- `com.jacekzieba.measureme.onboarding.health_permission_resolved`
  - Parameters: `flow_version`, `source`, `result`, `imported_age`, `imported_height`
  - Funnel role: onboarding Health permission result.
- `com.jacekzieba.measureme.onboarding.completed`
  - Parameters: `flow_version`, `priority`, `health_connected`, `completed_all_steps`
  - Funnel role: onboarding conversion.

Allowed values:
- `step`: `welcome|profile|metrics|photos|health`
- `priority`: `loseWeight|buildMuscle|improveHealth`
- `result`: `granted|denied`
- `skip_reason`: `user_skipped`

### Activation
- `com.jacekzieba.measureme.activation.task_viewed`
  - Parameters: `task`, `position`, `source`
  - Funnel role: activation task exposure.
- `com.jacekzieba.measureme.activation.task_started`
  - Parameters: `task`
  - Funnel role: user intent to perform activation task.
- `com.jacekzieba.measureme.activation.task_completed`
  - Parameters: `task`
  - Funnel role: task conversion.
- `com.jacekzieba.measureme.activation.task_skipped`
  - Parameters: `task`, `skip_reason`
  - Funnel role: explicit task skip.
- `com.jacekzieba.measureme.activation.dismissed`
  - Parameters: `current_task`, `completed_tasks_count`, `skipped_tasks_count`
  - Funnel role: activation hub abandoned/dismissed.
- `com.jacekzieba.measureme.activation.completed`
  - Parameters: `completed_tasks_count`, `skipped_tasks_count`
  - Funnel role: activation flow completed or exhausted.

Allowed values:
- `task`: `firstMeasurement|addPhoto|personalizeProfile|connectHealth|chooseMetrics|setReminders|explorePremium`
- `source`: `activation_screen|activation_hub`
- `skip_reason`: `user_skipped`

### Checklist and Health
- `com.jacekzieba.measureme.checklist.item_started`
  - Parameters: `item`, `source`, optional `task`
  - Funnel role: user started a checklist action.
- `com.jacekzieba.measureme.checklist.item_completed`
  - Parameters: `item`, `source`, optional `task`
  - Funnel role: checklist action conversion.
- `com.jacekzieba.measureme.health.permission_prompted`
  - Parameters: `source`
  - Funnel role: non-onboarding Health permission prompt exposure.
- `com.jacekzieba.measureme.health.permission_resolved`
  - Parameters: `source`, `result`
  - Funnel role: non-onboarding Health permission result.

Allowed values:
- `item`: currently `healthkit`
- `source`: `home_checklist|settings`
- `result`: `granted|denied`

### Measurements
- `com.jacekzieba.measureme.measurement.saved`
  - Parameters: `source`, `metrics_count`, `is_first_measurement`
  - Funnel role: value creation and first measurement conversion.
- `com.jacekzieba.measureme.metric.first_added`
  - Meaning: the user's genuine first metric sample. Since onboarding v5 saves the baseline during onboarding, this fires on that baseline (no longer gated on onboarding completion).
- `com.jacekzieba.measureme.metric.second_added`
  - Meaning: the user's second distinct measurement (the comeback signal); fires after onboarding completion once at least one sample already exists. Use together with `measurement.saved (is_first_measurement=false)` as the retention signal.

Allowed values:
- `source`: `onboarding|activation|quick_add|widget|watch|intent`

### Photos
- `com.jacekzieba.measureme.photo.add_started`
  - Parameters: `source`
  - Funnel role: photo add intent.
- `com.jacekzieba.measureme.photo.add_completed`
  - Parameters: `source`, `is_first_photo`
  - Funnel role: photo add conversion.
- `com.jacekzieba.measureme.photo.first_added`
  - Meaning: first photo after onboarding completion.
- `com.jacekzieba.measureme.photo.second_added`
  - Meaning: second photo after onboarding completion.
- `com.jacekzieba.measureme.photo.compare.first_session`
  - Parameters: `source`
  - Funnel role: first premium photo-compare engagement.

Allowed values:
- `source`: `onboarding|activation|photos|multi_import|home_recent_photos`

### Entry Points, App Intents, and Notifications
- `com.jacekzieba.measureme.quick_action_used`
  - Parameters: `action`
  - Funnel role: iOS Home Screen quick action engagement.
- `com.jacekzieba.measureme.app_intent_executed`
  - Parameters: `action`
  - Funnel role: Shortcuts/App Intents entry.
- `com.jacekzieba.measureme.app_intent_measurement_saved`
  - Parameters: `kind`
  - Funnel role: measurement saved through App Intent.
- `com.jacekzieba.measureme.notification_opened`
  - Parameters: `action`
  - Funnel role: notification re-entry.

Allowed values:
- `action`: `openQuickAdd|openAddPhoto`
- `kind`: metric kind raw value.

### Paywall, Purchase, and Premium
- `com.jacekzieba.measureme.paywall.presented`
  - Parameters: `source`, `reason`
  - Funnel role: monetization entry.
- `com.jacekzieba.measureme.paywall.slide_seen`
  - Parameters: `slide_id`, `context`
  - Funnel role: paywall content exposure.
- `com.jacekzieba.measureme.paywall.plan_selected`
  - Parameters: `plan_id`, `context`
  - Funnel role: plan intent.
- `com.jacekzieba.measureme.paywall.cta_tapped`
  - Parameters: `plan_id`, `context`
  - Funnel role: purchase CTA intent.
- `com.jacekzieba.measureme.paywall.purchase_started`
  - Parameters: `plan_id`, `context`
  - Funnel role: StoreKit/RevenueCat purchase flow started.
- `com.jacekzieba.measureme.purchase.completed`
  - Parameters: `measureme.purchase_source`, `measureme.paywall_reason`, optional feature context.
  - Funnel role: purchase conversion.
- `com.jacekzieba.measureme.purchase.cancelled`
  - Parameters: `measureme.purchase_source`, `measureme.paywall_reason`, optional feature context.
  - Funnel role: purchase cancellation.
- `com.jacekzieba.measureme.purchase.pending`
  - Parameters: `measureme.purchase_source`, `measureme.paywall_reason`, optional feature context.
  - Funnel role: pending purchase outcome.
- `com.jacekzieba.measureme.paywall.restore_tapped`
  - Parameters: `context`
  - Funnel role: restore purchase intent inside monetization surfaces.
- `com.jacekzieba.measureme.purchase.restore_started`
  - Parameters: `source`
  - Funnel role: restore purchase flow started.
- `com.jacekzieba.measureme.purchase.restore_completed`
  - Parameters: `source`, `result`
  - Funnel role: restore purchase outcome.
- `com.jacekzieba.measureme.paywall.closed`
  - Parameters: `context`
  - Funnel role: paywall exit.
- `com.jacekzieba.measureme.premium.soft_prompt_seen`
  - Parameters: `prompt_type`
  - Funnel role: automatic prompt exposure.
- `com.jacekzieba.measureme.premium.soft_prompt_dismissed`
  - Parameters: `prompt_type`
  - Funnel role: automatic prompt rejection/frequency cap.

Allowed values:
- `source`: `onboarding|activation|checklist|settings|feature|paywall`
- `reason` / `context`: `settings|feature_locked|seven_day_prompt|onboarding|activation|checklist|ai_insights|photo_comparison|export|icloud_sync|widgets|premium_metric|post_measurement_prompt|timed_prompt`
- `result`: `restored|already_active|none|failed`
- `prompt_type`: `sevenDay|postMeasurement|homeDiscovery` as defined by `AutomaticPromptKind`

Dedicated TelemetryDeck APIs:
- `TelemetryDeck.paywallShown(...)` is sent together with `paywall.presented`.
- `TelemetryDeck.purchaseCompleted(...)` is still available through `AnalyticsClient`, but current purchase result tracking uses `purchase.completed`.

### Notifications and Reminders
- `com.jacekzieba.measureme.notifications.permission_prompted`
  - Parameters: `source`
  - Funnel role: notification permission prompt exposure.
- `com.jacekzieba.measureme.notifications.permission_resolved`
  - Parameters: `source`, `result`
  - Funnel role: notification permission result or in-app decline.
- `com.jacekzieba.measureme.reminders.seeded`
  - Parameters: `source`, `repeat_rule`
  - Funnel role: reminder scheduled.

Allowed values:
- `source`: `activation|checklist|settings|premium_trial`
- `result`: `granted|denied|dismissed`
- `repeat_rule`: `once|daily|weekly|monthly`

### AI Insights
- `com.jacekzieba.measureme.ai_insight.generated`
  - Parameters: `kind`, `metric`, `prompt_version`, `length_short`, `length_detailed`, `validated`
  - Funnel role: AI insight generation success.
- `com.jacekzieba.measureme.ai_insight.fallback`
  - Parameters: `kind`, `metric`, `reason`
  - Funnel role: generation failure or deterministic fallback.
- `com.jacekzieba.measureme.ai_insight.refreshed`
  - Parameters: `kind`, `section_id`
  - Funnel role: user requested refresh.
- `com.jacekzieba.measureme.ai_insight.expanded`
  - Parameters: `kind`, `metric`, `expanded`
  - Funnel role: insight engagement.

Allowed values:
- `kind`: `metric|health|section`
- `reason`: `insufficient_samples|timeout|generation_error|validation_empty|validation_length|validation_disallowed_language|validation_hallucinated_number|validation_contradiction|validation_no_specifics`

## Recommended Funnels

### Funnel 1: Onboarding Completion
1. `onboarding.session_started`
2. `onboarding.step_viewed` filtered by `step=welcome`
3. `onboarding.step_completed` filtered by `step=welcome`
4. `onboarding.step_completed` filtered by `step=profile`
5. `onboarding.step_completed` filtered by `step=metrics`
6. `onboarding.step_completed` filtered by `step=photos`
7. `onboarding.step_completed` filtered by `step=health`
8. `onboarding.completed`

Use filters:
- Segment by `priority`.
- Compare `step_skipped` by `step`.
- Compare `completed.health_connected=true` vs `false`.

### Funnel 2: Health Permission
Onboarding path:
1. `onboarding.step_viewed` filtered by `step=health`
2. `onboarding.health_permission_prompted`
3. `onboarding.health_permission_resolved` filtered by `result=granted`
4. `onboarding.completed` filtered by `health_connected=true`

Post-onboarding path:
1. `health.permission_prompted` filtered by `source=settings` or `source=checklist`
2. `health.permission_resolved` filtered by `result=granted`
3. `checklist.item_completed` filtered by `item=healthkit`, if source is checklist

### Funnel 3: Activation
1. `onboarding.completed`
2. `activation.task_viewed`
3. `activation.task_started`
4. `activation.task_completed`
5. `activation.completed`

Use filters:
- Group by `task`.
- Treat `activation.task_skipped` and `activation.dismissed` as drop-off reasons.
- Compare `source=activation_screen` for the immediate post-onboarding screen vs `source=activation_hub` on Home.

### Funnel 4: First Value Creation
Measurement path:
1. `onboarding.step_viewed` filtered by `step=metrics`
2. `measurement.saved` filtered by `source=onboarding` and `is_first_measurement=true`
3. `onboarding.completed`
4. `metric.second_added`

Photo path:
1. `onboarding.step_viewed` filtered by `step=photos`
2. `photo.add_started` filtered by `source=onboarding`
3. `photo.add_completed` filtered by `source=onboarding` and `is_first_photo=true`
4. `photo.second_added`

### Funnel 5: Monetization
1. `paywall.presented`
2. `paywall.slide_seen`
3. `paywall.plan_selected`
4. `paywall.cta_tapped`
5. `paywall.purchase_started`
6. `purchase.completed`

Use filters:
- Segment by `source` and `reason`.
- Treat `purchase.cancelled`, `purchase.pending`, and `paywall.closed` as outcome branches.
- For feature paywalls, use optional `measureme.feature_name`.

### Funnel 6: Restore Purchases
1. `paywall.restore_tapped`, if source is a paywall-like surface
2. `purchase.restore_started`
3. `purchase.restore_completed`

Use filters:
- Segment by `source=onboarding|paywall|settings`.
- Split `result=restored|already_active|none|failed`.

### Funnel 7: Notifications and Reminders
Activation reminder path:
1. `notifications.permission_prompted` filtered by `source=activation`
2. `notifications.permission_resolved`
3. `reminders.seeded` filtered by `source=activation`

Settings reminder path:
1. `notifications.permission_prompted` filtered by `source=settings`
2. `notifications.permission_resolved`
3. `reminders.seeded` filtered by `source=settings`

Premium trial reminder path:
1. `purchase.completed`
2. `notifications.permission_prompted` filtered by `source=premium_trial`
3. `notifications.permission_resolved`
4. `reminders.seeded` filtered by `source=premium_trial`

### Funnel 8: AI Insight Engagement
1. `ai_insight.generated`
2. `ai_insight.expanded` filtered by `expanded=true`
3. `ai_insight.refreshed`

Use filters:
- Segment by `kind`.
- Track fallback rate with `ai_insight.fallback` grouped by `reason`.

## Removed Legacy Signals
These names existed in code but did not have active production call sites and were removed from `AnalyticsSignal`:
- `com.jacekzieba.measureme.onboarding.started`
- `com.jacekzieba.measureme.onboarding.step.welcome.viewed`
- `com.jacekzieba.measureme.onboarding.step.profile.viewed`
- `com.jacekzieba.measureme.onboarding.step.boosters.viewed`
- `com.jacekzieba.measureme.onboarding.step.premium.viewed`
- `com.jacekzieba.measureme.onboarding.step.healthkit.viewed`
- `com.jacekzieba.measureme.onboarding.skipped`
- `com.jacekzieba.measureme.onboarding.goal.lose_weight`
- `com.jacekzieba.measureme.onboarding.goal.build_muscle`
- `com.jacekzieba.measureme.onboarding.goal.track_health`
- `com.jacekzieba.measureme.onboarding.health_sync.prompt.shown`
- `com.jacekzieba.measureme.onboarding.health_sync.accepted`
- `com.jacekzieba.measureme.onboarding.health_sync.declined`
- `com.jacekzieba.measureme.onboarding.step.first_measurement.viewed`
- `com.jacekzieba.measureme.onboarding.first_measurement.saved`
- `com.jacekzieba.measureme.onboarding.step.value_preview.viewed`
- `com.jacekzieba.measureme.onboarding.first_measurement.health_prompt.viewed`
- `com.jacekzieba.measureme.activation.primary_task.shown`
- `com.jacekzieba.measureme.activation.primary_task.completed`
- `com.jacekzieba.measureme.activation.first_measurement.started`
- `com.jacekzieba.measureme.activation.first_measurement.saved`
- `com.jacekzieba.measureme.activation.first_measurement.success.viewed`
- `com.jacekzieba.measureme.activation.recommended_metrics.accepted`
- `com.jacekzieba.measureme.checklist.task.shown`
- `com.jacekzieba.measureme.checklist.task.completed`
- `com.jacekzieba.measureme.notifications.prompt.shown`
- `com.jacekzieba.measureme.notifications.accepted`
- `com.jacekzieba.measureme.reminders.setup.started`
- `com.jacekzieba.measureme.reminders.setup.completed`
- `com.jacekzieba.measureme.photo.first_add.started`
- `com.jacekzieba.measureme.chart.first_viewed`
- `com.jacekzieba.measureme.streak.extended`
- `com.jacekzieba.measureme.streak.broken`

Also removed from the active catalog:
- `com.jacekzieba.measureme.checklist.item_viewed`, because there was no stable production call site.
- `com.jacekzieba.measureme.paywall.purchase_cancelled`, because purchase outcomes now use `purchase.cancelled`.

## Validation Checklist
1. Trigger onboarding and confirm `session_started`, `step_viewed`, `step_completed`, `priority_selected`, Health prompt/result, and `completed`.
2. Complete, skip, and dismiss activation tasks and confirm task-level events.
3. Save first and second measurements; add first and second photos; run first compare session.
4. Open paywall from onboarding, Settings, and a locked feature; verify `source` and `reason`.
5. Start, cancel, complete, and restore purchase flows in sandbox or test mode.
6. Enable notifications from activation, Settings, and premium trial reminder surfaces.
7. Generate, expand, refresh, and fallback AI insights.
