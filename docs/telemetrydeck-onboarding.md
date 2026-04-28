# TelemetryDeck Onboarding Runbook

## Source of truth
- Onboarding flow version: `3`
- Event names live in `MeasureMe/AnalyticsEvents.swift`
- New onboarding, activation, checklist, measurement, photo, paywall, notification, and reminder telemetry should go through `Analytics.shared.track(AnalyticsEvent)`

## Event catalog

### Onboarding
- `com.jacekzieba.measureme.onboarding.session_started`
  - `flow_version`: `3`
  - `entrypoint`: `root`
  - `restored_state`: `true|false`
- `com.jacekzieba.measureme.onboarding.step_viewed`
  - `flow_version`, `step`, `step_index`, `step_count`
- `com.jacekzieba.measureme.onboarding.step_completed`
  - `flow_version`, `step`, `step_index`
- `com.jacekzieba.measureme.onboarding.step_skipped`
  - `flow_version`, `step`, `step_index`, `skip_reason`
- `com.jacekzieba.measureme.onboarding.priority_selected`
  - `flow_version`, `priority`
- `com.jacekzieba.measureme.onboarding.metric_pack_applied`
  - `flow_version`, `priority`, `pack_id`, `metrics_count`, `customized_metrics_before`
- `com.jacekzieba.measureme.onboarding.health_permission_prompted`
  - `flow_version`, `source`
- `com.jacekzieba.measureme.onboarding.health_permission_resolved`
  - `flow_version`, `source`, `result`, `imported_age`, `imported_height`
- `com.jacekzieba.measureme.onboarding.completed`
  - `flow_version`, `priority`, `health_connected`, `completed_all_steps`

Allowed values:
- `step`: `profile|metrics|photos|health`
- `priority`: `loseWeight|buildMuscle|improveHealth`
- `result`: `granted|denied`
- `skip_reason`: currently `user_skipped`

### Activation
- `com.jacekzieba.measureme.activation.task_viewed`
  - `task`, `position`, `source`
- `com.jacekzieba.measureme.activation.task_started`
  - `task`
- `com.jacekzieba.measureme.activation.task_completed`
  - `task`
- `com.jacekzieba.measureme.activation.task_skipped`
  - `task`, `skip_reason`
- `com.jacekzieba.measureme.activation.completed`
  - `completed_tasks_count`, `skipped_tasks_count`

Allowed values:
- `task`: `firstMeasurement|addPhoto|chooseMetrics|setGoal|setReminders|explorePremium`
- `source`: `activation_hub|activation_screen`

### Checklist
- `com.jacekzieba.measureme.checklist.item_viewed`
- `com.jacekzieba.measureme.checklist.item_started`
- `com.jacekzieba.measureme.checklist.item_completed`

Parameters:
- `item`
- `source`
- optional `task`

Current `source`: `home_checklist`

### First-value events
- `com.jacekzieba.measureme.measurement.saved`
  - `source`: `onboarding|activation|quick_add|widget|watch|intent`
  - `metrics_count`
  - `is_first_measurement`
- `com.jacekzieba.measureme.photo.add_started`
  - `source`: `activation|photos|multi_import`
- `com.jacekzieba.measureme.photo.add_completed`
  - `source`
  - `is_first_photo`

### Monetization entry
- `com.jacekzieba.measureme.paywall.presented`
  - `source`: `onboarding|activation|checklist|settings|feature`
  - `reason`

### Notifications and reminders
- `com.jacekzieba.measureme.notifications.permission_prompted`
  - `source`: `activation|checklist`
- `com.jacekzieba.measureme.notifications.permission_resolved`
  - `source`
  - `result`
- `com.jacekzieba.measureme.reminders.seeded`
  - `source`
  - `repeat_rule`

## Privacy rules
- Do not send user name.
- Do not send exact age, height, weight, or body-fat values.
- Do not send free-form text.
- Keep payloads low-cardinality.
- Do not use custom keys under `TelemetryDeck.*`.

## TelemetryDeck setup

### Explore
Use `Explore` first and confirm:
- all new signal types appear
- `step`, `priority`, `result`, `source`, and `task` are present and filterable
- test traffic is visible with the `Test Mode` toggle when validating development builds

### Dashboard groups
Create these groups:
- `Onboarding`
- `Activation`
- `Monetization Entry`

### Recommended funnels
#### Funnel 1: onboarding completion
1. `com.jacekzieba.measureme.onboarding.session_started`
2. `com.jacekzieba.measureme.onboarding.step_completed` filtered by `step=profile`
3. `com.jacekzieba.measureme.onboarding.step_completed` filtered by `step=metrics`
4. `com.jacekzieba.measureme.onboarding.step_completed` filtered by `step=photos`
5. `com.jacekzieba.measureme.onboarding.completed`

#### Funnel 2: post-onboarding activation
1. `com.jacekzieba.measureme.onboarding.completed`
2. `com.jacekzieba.measureme.activation.task_completed` filtered by `task=firstMeasurement`
3. `com.jacekzieba.measureme.photo.add_completed` filtered by `is_first_photo=true`
4. `com.jacekzieba.measureme.paywall.presented` filtered by `source=onboarding`

### Recommended insights
- onboarding starts vs completions
- drop-off by `step`
- Apple Health acceptance rate
- first measurement completion after onboarding
- paywall entries by `source`
- onboarding completion by `priority`

## Validation
1. Run a local debug build and trigger onboarding and activation flows.
2. In TelemetryDeck, enable `Test Mode`.
3. Verify the raw events in `Explore`.
4. Confirm funnel filters work with `step`, `task`, `priority`, `source`, and `result`.
