import 'dart:async';
import 'dart:developer' as developer;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:carpooling_driver/features/notifications/data/models/notification_model.dart';

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
    
    developer.log('🔍 Fetching notifications...', name: 'NotificationDataSource');
    developer.log('   User ID: $userId', name: 'NotificationDataSource');
    
    if (userId == null) {
      developer.log('❌ User not authenticated!', name: 'NotificationDataSource');
      throw Exception('User not authenticated');
    }

    try {
      final List<dynamic> response;
      
      if (unreadOnly) {
        developer.log('   Fetching unread only...', name: 'NotificationDataSource');
        response = await _supabase
            .from('notifications')
            .select()
            .eq('user_id', userId)
            .eq('is_read', false)
            .order('created_at', ascending: false)
            .limit(limit);
      } else {
        developer.log('   Fetching all notifications...', name: 'NotificationDataSource');
        response = await _supabase
            .from('notifications')
            .select()
            .eq('user_id', userId)
            .order('created_at', ascending: false)
            .limit(limit);
      }

      developer.log(
        '✅ Fetched ${response.length} notifications for user $userId',
        name: 'NotificationDataSource',
      );
      
      if (response.isEmpty) {
        developer.log('⚠️ No notifications found for this user', name: 'NotificationDataSource');
      }

      return response
          .map((json) => NotificationModel.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e, stackTrace) {
      developer.log(
        '❌ Error fetching notifications: $e',
        name: 'NotificationDataSource',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Mark notification as read
  Future<void> markAsRead(String notificationId) async {
    try {
      await _supabase.from('notifications').update({
        'is_read': true,
        'read_at': DateTime.now().toIso8601String(),
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
      await _supabase.from('notifications').update({
        'is_read': true,
        'read_at': DateTime.now().toIso8601String(),
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

  /// Create a new notification using RPC function
  Future<void> createNotification({
    required String userId,
    required String title,
    required String message,
    String? type,
    String? relatedId,
  }) async {
    try {
      developer.log(
        'Creating notification for user $userId: $title',
        name: 'NotificationDataSource',
      );

      await _supabase.rpc('create_notification', params: {
        'p_user_id': userId,
        'p_title': title,
        'p_message': message,
        'p_type': type ?? 'general',
        'p_related_id': relatedId,
      });

      developer.log(
        'Notification created successfully',
        name: 'NotificationDataSource',
      );
    } catch (e) {
      developer.log(
        'Error creating notification: $e',
        name: 'NotificationDataSource',
        error: e,
      );
      rethrow;
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

