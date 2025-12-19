import 'dart:async';
import 'dart:developer' as developer;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:carpooling_main/features/notifications/data/models/notification_model.dart';
import 'package:carpooling_main/core/utils/timezone_helper.dart';

/// Remote data source for notifications using Supabase
/// Handles real-time subscriptions and CRUD operations
class NotificationRemoteDataSource {
  final SupabaseClient _supabase;
  RealtimeChannel? _notificationChannel;
  StreamController<List<NotificationModel>>? _notificationStreamController;

  NotificationRemoteDataSource({
    SupabaseClient? supabaseClient,
  }) : _supabase = supabaseClient ?? Supabase.instance.client;

  /// Get current user ID
  String? get _currentUserId => _supabase.auth.currentUser?.id;

  /// Subscribe to real-time notifications for current user
  Stream<List<NotificationModel>> subscribeToNotifications() {
    final userId = _currentUserId;
    if (userId == null) {
      developer.log(
        'Cannot subscribe to notifications: User not authenticated',
        name: 'NotificationDataSource',
      );
      return Stream.value([]);
    }

    // Close existing stream if any
    _closeStream();

    // Create new stream controller
    _notificationStreamController = StreamController<List<NotificationModel>>.broadcast();

    developer.log(
      'Subscribing to notifications for user: $userId',
      name: 'NotificationDataSource',
    );

    // Create real-time channel
    _notificationChannel = _supabase
        .channel('notifications_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            developer.log(
              'Real-time notification event: ${payload.eventType}',
              name: 'NotificationDataSource',
            );
            // Fetch all notifications when any change occurs
            _fetchAndEmitNotifications();
          },
        )
        .subscribe();

    // Initial fetch
    _fetchAndEmitNotifications();

    return _notificationStreamController!.stream;
  }

  /// Fetch notifications and emit to stream
  Future<void> _fetchAndEmitNotifications() async {
    try {
      final notifications = await fetchNotifications();
      if (!_notificationStreamController!.isClosed) {
        _notificationStreamController!.add(notifications);
      }
    } catch (e) {
      developer.log(
        'Error fetching notifications: $e',
        name: 'NotificationDataSource',
        error: e,
      );
      if (!_notificationStreamController!.isClosed) {
        _notificationStreamController!.addError(e);
      }
    }
  }

  /// Fetch all notifications for current user
  Future<List<NotificationModel>> fetchNotifications({
    int limit = 50,
    bool unreadOnly = false,
  }) async {
    final userId = _currentUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    try {
      final List<dynamic> response;
      
      if (unreadOnly) {
        response = await _supabase
            .from('notifications')
            .select()
            .eq('user_id', userId)
            .eq('is_read', false)
            .order('created_at', ascending: false)
            .limit(limit);
      } else {
        response = await _supabase
            .from('notifications')
            .select()
            .eq('user_id', userId)
            .order('created_at', ascending: false)
            .limit(limit);
      }

      developer.log(
        'Fetched ${response.length} notifications',
        name: 'NotificationDataSource',
      );

      return response
          .map((json) => NotificationModel.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      developer.log(
        'Error fetching notifications: $e',
        name: 'NotificationDataSource',
        error: e,
      );
      rethrow;
    }
  }

  /// Mark notification as read
  Future<void> markAsRead(String notificationId) async {
    try {
      final nowMalaysia = TimezoneHelper.nowInMalaysia();
      final nowUtc = TimezoneHelper.malaysiaToUtc(nowMalaysia);
      
      await _supabase.from('notifications').update({
        'is_read': true,
        'read_at': nowUtc.toIso8601String(),
      }).eq('id', notificationId);

      developer.log(
        'Marked notification as read: $notificationId',
        name: 'NotificationDataSource',
      );
    } catch (e) {
      developer.log(
        'Error marking notification as read: $e',
        name: 'NotificationDataSource',
        error: e,
      );
      rethrow;
    }
  }

  /// Mark all notifications as read
  Future<void> markAllAsRead() async {
    final userId = _currentUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    try {
      final nowMalaysia = TimezoneHelper.nowInMalaysia();
      final nowUtc = TimezoneHelper.malaysiaToUtc(nowMalaysia);
      
      await _supabase.from('notifications').update({
        'is_read': true,
        'read_at': nowUtc.toIso8601String(),
      }).eq('user_id', userId).eq('is_read', false);

      developer.log(
        'Marked all notifications as read',
        name: 'NotificationDataSource',
      );
    } catch (e) {
      developer.log(
        'Error marking all notifications as read: $e',
        name: 'NotificationDataSource',
        error: e,
      );
      rethrow;
    }
  }

  /// Delete notification
  Future<void> deleteNotification(String notificationId) async {
    try {
      await _supabase
          .from('notifications')
          .delete()
          .eq('id', notificationId);

      developer.log(
        'Deleted notification: $notificationId',
        name: 'NotificationDataSource',
      );
    } catch (e) {
      developer.log(
        'Error deleting notification: $e',
        name: 'NotificationDataSource',
        error: e,
      );
      rethrow;
    }
  }

  /// Delete all read notifications
  Future<void> clearReadNotifications() async {
    final userId = _currentUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    try {
      await _supabase
          .from('notifications')
          .delete()
          .eq('user_id', userId)
          .eq('is_read', true);

      developer.log(
        'Cleared all read notifications',
        name: 'NotificationDataSource',
      );
    } catch (e) {
      developer.log(
        'Error clearing read notifications: $e',
        name: 'NotificationDataSource',
        error: e,
      );
      rethrow;
    }
  }

  /// Get unread notification count
  Future<int> getUnreadCount() async {
    final userId = _currentUserId;
    if (userId == null) {
      return 0;
    }

    try {
      final List<dynamic> response = await _supabase
          .from('notifications')
          .select()
          .eq('user_id', userId)
          .eq('is_read', false);

      final count = response.length;
      developer.log(
        'Unread notification count: $count',
        name: 'NotificationDataSource',
      );
      return count;
    } catch (e) {
      developer.log(
        'Error getting unread count: $e',
        name: 'NotificationDataSource',
        error: e,
      );
      return 0;
    }
  }

  /// Close real-time subscription and stream
  void _closeStream() {
    _notificationChannel?.unsubscribe();
    _notificationChannel = null;
    _notificationStreamController?.close();
    _notificationStreamController = null;
  }

  /// Dispose resources
  void dispose() {
    developer.log(
      'Disposing notification data source',
      name: 'NotificationDataSource',
    );
    _closeStream();
  }
}

