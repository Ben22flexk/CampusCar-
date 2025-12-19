import 'dart:async';
import 'package:carpooling_main/features/notifications/domain/entities/notification_entity.dart';
import 'package:carpooling_main/features/notifications/data/datasources/notification_remote_datasource.dart';

/// Service layer for notifications
/// Provides a clean API for the presentation layer
class NotificationService {
  final NotificationRemoteDataSource _remoteDataSource;

  NotificationService({
    NotificationRemoteDataSource? remoteDataSource,
  }) : _remoteDataSource = remoteDataSource ?? NotificationRemoteDataSource();

  /// Subscribe to real-time notifications
  /// Returns a stream of notification entities
  Stream<List<NotificationEntity>> subscribeToNotifications() {
    return _remoteDataSource
        .subscribeToNotifications()
        .map((models) => models.map((model) => model.toDomain()).toList());
  }

  /// Fetch all notifications
  Future<List<NotificationEntity>> fetchNotifications({
    int limit = 50,
    bool unreadOnly = false,
  }) async {
    final models = await _remoteDataSource.fetchNotifications(
      limit: limit,
      unreadOnly: unreadOnly,
    );
    return models.map((model) => model.toDomain()).toList();
  }

  /// Mark notification as read
  Future<void> markAsRead(String notificationId) async {
    await _remoteDataSource.markAsRead(notificationId);
  }

  /// Mark all notifications as read
  Future<void> markAllAsRead() async {
    await _remoteDataSource.markAllAsRead();
  }

  /// Delete notification
  Future<void> deleteNotification(String notificationId) async {
    await _remoteDataSource.deleteNotification(notificationId);
  }

  /// Clear all read notifications
  Future<void> clearReadNotifications() async {
    await _remoteDataSource.clearReadNotifications();
  }

  /// Get unread notification count
  Future<int> getUnreadCount() async {
    return await _remoteDataSource.getUnreadCount();
  }

  /// Dispose resources
  void dispose() {
    _remoteDataSource.dispose();
  }
}

