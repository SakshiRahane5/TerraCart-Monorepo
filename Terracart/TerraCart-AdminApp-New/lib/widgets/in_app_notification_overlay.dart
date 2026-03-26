import 'package:flutter/material.dart';

import '../core/notifications/in_app_notification_models.dart';
import '../services/in_app_notification_service.dart';

class InAppNotificationOverlay extends StatelessWidget {
  const InAppNotificationOverlay({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        ValueListenableBuilder<InAppNotificationItem?>(
          valueListenable: InAppNotificationService.instance.currentNotification,
          builder: (context, notification, _) {
            if (notification == null) {
              return const SizedBox.shrink();
            }

            return Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: SafeArea(
                minimum: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: _NotificationBanner(
                    key: ValueKey<String>(notification.id),
                    notification: notification,
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _NotificationBanner extends StatelessWidget {
  const _NotificationBanner({
    super.key,
    required this.notification,
  });

  final InAppNotificationItem notification;

  @override
  Widget build(BuildContext context) {
    final type = notification.type;
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () =>
            InAppNotificationService.instance.handleNotificationTap(notification),
        child: Ink(
          decoration: BoxDecoration(
            color: type.backgroundColor,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(type.icon, color: Colors.white, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              notification.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.titleSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (notification.mergedCount > 1)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                'x${notification.mergedCount}',
                                style: textTheme.labelSmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        notification.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.96),
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (type.autoDismissDuration == null)
                  IconButton(
                    constraints:
                        const BoxConstraints.tightFor(width: 26, height: 26),
                    visualDensity: const VisualDensity(
                      horizontal: -4,
                      vertical: -4,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: InAppNotificationService.instance.dismissCurrent,
                    icon: const Icon(Icons.close, color: Colors.white, size: 18),
                  )
                else
                  const Icon(Icons.arrow_forward_ios,
                      color: Colors.white70, size: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
