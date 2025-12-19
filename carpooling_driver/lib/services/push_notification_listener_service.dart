import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Service that listens to pending_push_notifications table
/// and sends push notifications via Firebase
class PushNotificationListenerService {
  static final PushNotificationListenerService _instance =
      PushNotificationListenerService._internal();
  static PushNotificationListenerService get instance => _instance;

  final SupabaseClient _supabase = Supabase.instance.client;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  RealtimeChannel? _channel;
  bool _isListening = false;

  PushNotificationListenerService._internal();

  /// Start listening for pending push notifications
  Future<void> startListening() async {
    if (_isListening) {
      developer.log('⚠️ Already listening to push notifications',
          name: 'PushNotificationListenerService');
      return;
    }

    try {
      developer.log('📡 Starting to listen for push notifications...',
          name: 'PushNotificationListenerService');

      // Subscribe to pending_push_notifications table
      developer.log('🔌 Creating realtime channel...',
          name: 'PushNotificationListenerService');
      developer.log('⏰ Current time: ${DateTime.now()}',
          name: 'PushNotificationListenerService');

      _channel = _supabase
          .channel('push_notifications_${DateTime.now().millisecondsSinceEpoch}')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'pending_push_notifications',
            callback: (payload) {
              developer.log('🔔🔔🔔 REALTIME EVENT RECEIVED! 🔔🔔🔔',
                  name: 'PushNotificationListenerService');
              developer.log('📦 Event Type: ${payload.eventType}',
                  name: 'PushNotificationListenerService');
              developer.log('📦 Table: ${payload.table}',
                  name: 'PushNotificationListenerService');
              developer.log('📦 Schema: ${payload.schema}',
                  name: 'PushNotificationListenerService');
              developer.log('📦 New Record: ${payload.newRecord}',
                  name: 'PushNotificationListenerService');
              developer.log('📦 Old Record: ${payload.oldRecord}',
                  name: 'PushNotificationListenerService');

              if (payload.eventType == PostgresChangeEvent.insert) {
                developer.log('✅ This is an INSERT event, processing...',
                    name: 'PushNotificationListenerService');
                _handleNewNotification(payload);
              } else {
                developer.log('ℹ️ Event type ${payload.eventType} ignored',
                    name: 'PushNotificationListenerService');
              }
            },
          )
          .subscribe((status, [error]) {
            developer.log('📡 Subscription status changed: $status',
                name: 'PushNotificationListenerService');
            if (error != null) {
              developer.log('❌ Subscription error: $error',
                  name: 'PushNotificationListenerService');
            }
            if (status == RealtimeSubscribeStatus.subscribed) {
              developer.log(
                  '✅✅✅ Successfully subscribed to push notifications! ✅✅✅',
                  name: 'PushNotificationListenerService');
              developer.log('🎯 Listening for new rides...',
                  name: 'PushNotificationListenerService');
            }
            if (status == RealtimeSubscribeStatus.closed) {
              developer.log('❌ Subscription CLOSED!',
                  name: 'PushNotificationListenerService');
            }
            if (status == RealtimeSubscribeStatus.channelError) {
              developer.log('❌ Channel ERROR!',
                  name: 'PushNotificationListenerService');
            }
          });

      _isListening = true;
      developer.log('✅ Listening for push notifications',
          name: 'PushNotificationListenerService');
    } catch (e) {
      developer.log('❌ Error starting push notification listener: $e',
          name: 'PushNotificationListenerService', error: e);
    }
  }

  /// Handle new notification from database
  Future<void> _handleNewNotification(PostgresChangePayload payload) async {
    try {
      developer.log('🔔 New push notification received from database',
          name: 'PushNotificationListenerService');
      developer.log('📦 Payload details: ${payload.newRecord}',
          name: 'PushNotificationListenerService');

      final record = payload.newRecord;
      final notificationId = record['id'] as String;
      final targetUserIds = record['target_user_ids'] as List<dynamic>;
      final title = record['title'] as String;
      final body = record['body'] as String;
      final type = record['notification_type'] as String;

      // Check if current user should receive this notification
      final currentUserId = _supabase.auth.currentUser?.id;
      developer.log('👤 Current user ID: $currentUserId',
          name: 'PushNotificationListenerService');
      developer.log('🎯 Target user IDs: $targetUserIds',
          name: 'PushNotificationListenerService');

      if (currentUserId == null) {
        developer.log('⚠️ No current user, skipping notification',
            name: 'PushNotificationListenerService');
        return;
      }

      if (targetUserIds.contains(currentUserId)) {
        developer.log('✅ Current user IS in target list, showing notification!',
            name: 'PushNotificationListenerService');
        developer.log(
            '📱 Current user is a target, showing notification',
            name: 'PushNotificationListenerService');

        // Show local notification
        await _showStyledNotification(
          title: title,
          body: body,
          type: type,
        );

        // Mark as sent (only for this user)
        await _markAsSent(notificationId);
      } else {
        developer.log('ℹ️ Current user NOT in target list, skipping',
            name: 'PushNotificationListenerService');
      }
    } catch (e) {
      developer.log('❌ Error handling push notification: $e',
          name: 'PushNotificationListenerService', error: e);
    }
  }

  /// Show styled notification with icon and image
  Future<void> _showStyledNotification({
    required String title,
    required String body,
    required String type,
  }) async {
    try {
      final androidDetails = AndroidNotificationDetails(
        'high_importance_channel',
        'High Importance Notifications',
        channelDescription: 'This channel is used for important notifications.',
        importance: Importance.max,
        priority: Priority.max,
        playSound: true,
        enableVibration: true,
        enableLights: true,
        icon: '@mipmap/ic_launcher',
        largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
        styleInformation: BigTextStyleInformation(
          body,
          contentTitle: title,
          summaryText: 'campuscar.tarc.edu.my',
          htmlFormatBigText: true,
          htmlFormatContentTitle: true,
          htmlFormatSummaryText: true,
        ),
        color: _getColorForType(type),
        colorized: true,
        visibility: NotificationVisibility.public,
        fullScreenIntent: false,
        groupKey: 'campuscar_notifications',
        showWhen: true,
        when: DateTime.now().millisecondsSinceEpoch,
        ledColor: _getColorForType(type),
        ledOnMs: 1000,
        ledOffMs: 500,
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        badgeNumber: 1,
        subtitle: 'campuscar.tarc.edu.my',
        interruptionLevel: InterruptionLevel.timeSensitive,
      );

      final notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        notificationDetails,
        payload: type,
      );

      developer.log('✅ Notification shown successfully',
          name: 'PushNotificationListenerService');
    } catch (e) {
      developer.log('❌ Error showing notification: $e',
          name: 'PushNotificationListenerService', error: e);
    }
  }

  /// Get color for notification type - vibrant colors like iOS notifications
  Color _getColorForType(String type) {
    switch (type) {
      case 'ride_available':
      case 'ride_created':
        return const Color(0xFF2196F3); // Vibrant Blue
      case 'booking_confirmed':
        return const Color(0xFF4CAF50); // Vibrant Green (success)
      case 'verification_approved':
        return const Color(0xFF66BB6A); // Light Green (approved)
      case 'ride_cancelled':
        return const Color(0xFFF44336); // Red (cancelled)
      case 'ride_reminder':
        return const Color(0xFFFF9800); // Orange (reminder)
      default:
        return const Color(0xFFFF6F00); // Orange (driver default)
    }
  }

  /// Mark notification as sent
  Future<void> _markAsSent(String notificationId) async {
    try {
      await _supabase.rpc('mark_push_notification_sent', params: {
        'notification_id': notificationId,
      });
      developer.log('✅ Notification marked as sent',
          name: 'PushNotificationListenerService');
    } catch (e) {
      developer.log('⚠️ Error marking notification as sent: $e',
          name: 'PushNotificationListenerService', error: e);
    }
  }

  /// Stop listening
  Future<void> stopListening() async {
    if (_channel != null) {
      await _supabase.removeChannel(_channel!);
      _channel = null;
      _isListening = false;
      developer.log('🛑 Stopped listening for push notifications',
          name: 'PushNotificationListenerService');
    }
  }
}
