import 'dart:async';
import 'dart:developer' as developer;
import 'dart:typed_data';
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
      print('🔌 Creating realtime channel...');
      print('⏰ Current time: ${DateTime.now()}');
      
      _channel = _supabase
          .channel('push_notifications_${DateTime.now().millisecondsSinceEpoch}') // Unique channel name
          .onPostgresChanges(
            event: PostgresChangeEvent.all, // Listen to ALL events (insert, update, delete)
            schema: 'public',
            table: 'pending_push_notifications',
            callback: (payload) {
              print('');
              print('🔔🔔🔔 REALTIME EVENT RECEIVED! 🔔🔔🔔');
              print('📦 Event Type: ${payload.eventType}');
              print('📦 Table: ${payload.table}');
              print('📦 Schema: ${payload.schema}');
              print('📦 New Record: ${payload.newRecord}');
              print('📦 Old Record: ${payload.oldRecord}');
              print('');
              
              if (payload.eventType == PostgresChangeEvent.insert) {
                print('✅ This is an INSERT event, processing...');
                _handleNewNotification(payload);
              } else {
                print('ℹ️ Event type ${payload.eventType} ignored');
              }
            },
          )
          .subscribe((status, [error]) {
            print('');
            print('📡 Subscription status changed: $status');
            if (error != null) {
              print('❌ Subscription error: $error');
            }
            if (status == RealtimeSubscribeStatus.subscribed) {
              print('✅✅✅ Successfully subscribed to push notifications! ✅✅✅');
              print('🎯 Listening for new rides...');
              print('');
            }
            if (status == RealtimeSubscribeStatus.closed) {
              print('❌ Subscription CLOSED!');
            }
            if (status == RealtimeSubscribeStatus.channelError) {
              print('❌ Channel ERROR!');
            }
          });

      _isListening = true;
      print('✅ Listening for push notifications');
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
      print('🔔 New push notification received from database');
      print('📦 Payload details: ${payload.newRecord}');
      developer.log('🔔 New push notification received from database', 
          name: 'PushNotificationListenerService');
      developer.log('Payload: ${payload.newRecord}', 
          name: 'PushNotificationListenerService');

      final record = payload.newRecord;
      final notificationId = record['id'] as String;
      final targetUserIds = record['target_user_ids'] as List<dynamic>;
      final title = record['title'] as String;
      final body = record['body'] as String;
      final type = record['notification_type'] as String;

      // Check if current user should receive this notification
      final currentUserId = _supabase.auth.currentUser?.id;
      print('👤 Current user ID: $currentUserId');
      print('🎯 Target user IDs: $targetUserIds');
      
      if (currentUserId == null) {
        print('⚠️ No current user, skipping notification');
        developer.log('⚠️ No current user, skipping notification', 
            name: 'PushNotificationListenerService');
        return;
      }

      if (targetUserIds.contains(currentUserId)) {
        print('✅ Current user IS in target list, showing notification!');
        developer.log('📱 Current user is a target, showing notification', 
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
        print('ℹ️ Current user NOT in target list, skipping');
        developer.log('ℹ️ Current user not in target list', 
            name: 'PushNotificationListenerService');
      }
    } catch (e) {
      developer.log('❌ Error handling push notification: $e', 
          name: 'PushNotificationListenerService', error: e);
    }
  }

  /// Show beautifully styled notification (Enhanced version)
  Future<void> _showStyledNotification({
    required String title,
    required String body,
    required String type,
  }) async {
    try {
      print('🎨 Showing enhanced styled notification!');
      
      // Enhanced Android notification with beautiful styling
      final androidDetails = AndroidNotificationDetails(
        'campuscar_channel', // Channel ID
        'CampusCar Notifications', // Channel name
        channelDescription: 'Stay updated with your rides and bookings',
        importance: Importance.max,
        priority: Priority.max,
        
        // Sound & Vibration - Enhanced
        playSound: true,
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 500, 250, 500]), // Custom vibration pattern
        enableLights: true,
        ledColor: _getColorForType(type),
        ledOnMs: 1000,
        ledOffMs: 500,
        
        // App Icon - Shows on the left (circular badge like screenshot)
        icon: '@mipmap/ic_launcher',
        largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
        
        // Enhanced text styling with subtitle (like "campuscar" in screenshot)
        styleInformation: BigTextStyleInformation(
          body,
          contentTitle: title,
          summaryText: 'CampusCar - Your Campus Carpool', // Subtitle text like screenshot
          htmlFormatBigText: true,
          htmlFormatContentTitle: true,
          htmlFormatSummaryText: true,
        ),
        
        // Color theming (Blue/Green/Orange like screenshot)
        color: _getColorForType(type),
        colorized: true, // Makes notification more vibrant
        
        // Visibility & Display
        visibility: NotificationVisibility.public, // Shows on lock screen
        showWhen: true, // Shows timestamp ("now" like screenshot)
        when: DateTime.now().millisecondsSinceEpoch,
        usesChronometer: false,
        
        // Grouping for organized notifications
        groupKey: 'campuscar_notifications',
        setAsGroupSummary: false,
        
        // Auto-cancel when tapped
        autoCancel: true,
        
        // Full screen for important notifications (optional)
        fullScreenIntent: false,
        
        // Not ongoing (user can swipe away)
        ongoing: false,
        
        // Additional styling
        category: AndroidNotificationCategory.message,
        channelShowBadge: true,
        showProgress: false,
      );

      // Enhanced iOS notification details
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        badgeNumber: 1,
        subtitle: 'CampusCar', // Subtitle for iOS
        interruptionLevel: InterruptionLevel.timeSensitive,
      );

      final notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      // Generate unique notification ID
      final notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      await _localNotifications.show(
        notificationId,
        title,
        body,
        notificationDetails,
        payload: type,
      );

      print('✅ Enhanced notification shown successfully! 🎨');
      developer.log('✅ Enhanced notification shown successfully', 
          name: 'PushNotificationListenerService');
    } catch (e) {
      print('❌ Error showing notification: $e');
      developer.log('❌ Error showing notification: $e', 
          name: 'PushNotificationListenerService', error: e);
    }
  }

  /// Get vibrant color based on notification type (Enhanced like screenshot)
  Color _getColorForType(String type) {
    switch (type) {
      case 'ride_created':
        return const Color(0xFF4CAF50); // Green (success/created)
      case 'ride_available':
        return const Color(0xFF2196F3); // Blue (info/available)
      case 'booking_accepted':
        return const Color(0xFF00BCD4); // Cyan (accepted)
      case 'booking_confirmed':
        return const Color(0xFF4CAF50); // Green (confirmed)
      case 'ride_cancelled':
      case 'booking_rejected':
        return const Color(0xFFF44336); // Red (cancelled/rejected)
      case 'ride_reminder':
        return const Color(0xFFFF9800); // Orange (reminder)
      case 'verification_approved':
        return const Color(0xFF66BB6A); // Light Green (approved)
      case 'new_booking_request':
        return const Color(0xFF2196F3); // Blue (new request)
      default:
        return const Color(0xFF1976D2); // Dark Blue (default)
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

