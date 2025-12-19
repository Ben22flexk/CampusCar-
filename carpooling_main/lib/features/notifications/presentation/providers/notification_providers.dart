import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:carpooling_main/features/notifications/domain/entities/notification_entity.dart';
import 'package:carpooling_main/features/notifications/data/datasources/notification_service.dart';

/// Provider for NotificationService instance
final notificationServiceProvider = Provider<NotificationService>((ref) {
  final service = NotificationService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Stream provider for real-time notifications
/// Automatically subscribes to Supabase real-time updates
final notificationsStreamProvider = StreamProvider<List<NotificationEntity>>((ref) {
  final service = ref.watch(notificationServiceProvider);
  return service.subscribeToNotifications();
});

/// Provider for unread notification count
final unreadNotificationCountProvider = StreamProvider<int>((ref) async* {
  final service = ref.watch(notificationServiceProvider);
  
  // Initial count
  yield await service.getUnreadCount();
  
  // Listen to notifications stream and count unread
  await for (final notifications in service.subscribeToNotifications()) {
    final unreadCount = notifications.where((n) => !n.isRead).length;
    yield unreadCount;
  }
});

/// Provider for filtered notifications (unread only)
final unreadNotificationsProvider = Provider<List<NotificationEntity>>((ref) {
  final notificationsAsync = ref.watch(notificationsStreamProvider);
  return notificationsAsync.when(
    data: (notifications) => notifications.where((n) => !n.isRead).toList(),
    loading: () => [],
    error: (_, __) => [],
  );
});

/// Provider for notification actions
final notificationActionsProvider = Provider<NotificationActions>((ref) {
  final service = ref.watch(notificationServiceProvider);
  return NotificationActions(service, ref);
});

/// Class containing notification actions
class NotificationActions {
  final NotificationService _service;
  final Ref _ref;

  NotificationActions(this._service, this._ref);

  /// Mark notification as read
  Future<void> markAsRead(String notificationId) async {
    await _service.markAsRead(notificationId);
    // Refresh notifications
    _ref.invalidate(notificationsStreamProvider);
  }

  /// Mark all notifications as read
  Future<void> markAllAsRead() async {
    await _service.markAllAsRead();
    // Refresh notifications
    _ref.invalidate(notificationsStreamProvider);
  }

  /// Delete notification
  Future<void> deleteNotification(String notificationId) async {
    await _service.deleteNotification(notificationId);
    // Refresh notifications
    _ref.invalidate(notificationsStreamProvider);
  }

  /// Clear all read notifications
  Future<void> clearReadNotifications() async {
    await _service.clearReadNotifications();
    // Refresh notifications
    _ref.invalidate(notificationsStreamProvider);
  }

  /// Refresh notifications manually
  void refresh() {
    _ref.invalidate(notificationsStreamProvider);
  }
}

