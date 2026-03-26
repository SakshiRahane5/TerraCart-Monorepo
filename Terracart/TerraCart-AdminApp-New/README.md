# terra_admin_app

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Notification Channel Note

Android notification channels are immutable after they are created on a device.
For the deaf-friendly vibration rollout, the app uses channel id
`orders_high_priority_v2` so updated vibration settings are applied via a new
channel definition instead of trying to mutate an existing one. When vibration
is disabled in Accessibility settings, the app routes alerts to a silent
companion channel because channel vibration flags cannot be changed at runtime.

On iOS, custom vibration patterns are not configurable per-notification from
Flutter local notifications, so background vibration follows normal system/APNs
notification behavior.
