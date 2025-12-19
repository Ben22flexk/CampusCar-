import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:carpooling_driver/features/notifications/presentation/providers/notification_providers.dart';
import 'package:carpooling_driver/features/notifications/presentation/widgets/notification_toast.dart';
import 'package:carpooling_driver/features/notifications/domain/entities/notification_entity.dart';

/// Widget that listens to new notifications and shows in-app toasts
/// Wrap your app with this widget to enable real-time notification alerts
class RealtimeNotificationListener extends ConsumerStatefulWidget {
  final Widget child;

  const RealtimeNotificationListener({
    super.key,
    required this.child,
  });

  @override
  ConsumerState<RealtimeNotificationListener> createState() => _RealtimeNotificationListenerState();
}

class _RealtimeNotificationListenerState extends ConsumerState<RealtimeNotificationListener> {
  List<NotificationEntity> _previousNotifications = [];
  bool _isInitialized = false;

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<List<NotificationEntity>>>(
      notificationsStreamProvider,
      (previous, next) {
        next.whenData((notifications) {
          // Skip initial load
          if (!_isInitialized) {
            _previousNotifications = notifications;
            _isInitialized = true;
            return;
          }

          // Find new notifications
          final newNotifications = notifications.where((notification) {
            return !_previousNotifications.any((prev) => prev.id == notification.id);
          }).toList();

          // Show toast for each new notification
          for (final notification in newNotifications) {
            _showNotificationToast(notification);
          }

          // Update previous notifications
          _previousNotifications = notifications;
        });
      },
    );

    return widget.child;
  }

  void _showNotificationToast(NotificationEntity notification) {
    // Only show toast if context is mounted and user is authenticated
    if (!mounted) return;

    // Show toast after a short delay to ensure context is ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        NotificationToast.show(
          context: context,
          notification: notification,
          onTap: () => _handleNotificationTap(notification),
        );
      }
    });
  }

  void _handleNotificationTap(NotificationEntity notification) {
    // Mark as read when tapped
    final actions = ref.read(notificationActionsProvider);
    if (!notification.isRead) {
      actions.markAsRead(notification.id);
    }

    // Navigate to related screen
    // TODO: Implement navigation based on notification type
    // For now, we'll just let the user tap the notification badge to see all notifications
  }
}

