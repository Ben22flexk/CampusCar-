import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Enhanced push notification listener with beautiful styling
class PushNotificationListenerSimple {
  static final PushNotificationListenerSimple instance = PushNotificationListenerSimple._internal();
  
  final SupabaseClient _supabase = Supabase.instance.client;
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  
  RealtimeChannel? _channel;
  bool _isListening = false;

  PushNotificationListenerSimple._internal();

  /// Start listening for push notifications
  Future<void> startListening() async {
    if (_isListening) {
      print('⚠️ Already listening');
      return;
    }

    try {
      print('📡 Starting push notification listener...');
      
      // Initialize notifications
      await _initializeNotifications();
      
      // Subscribe to realtime
      _channel = _supabase
          .channel('push_notifications')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'pending_push_notifications',
            callback: (payload) async {
              print('');
              print('🔔🔔🔔 NOTIFICATION RECEIVED! 🔔🔔🔔');
              print('Payload: ${payload.newRecord}');
              await _handleNotification(payload.newRecord);
            },
          )
          .subscribe((status, [error]) {
            print('Status: $status');
            if (error != null) print('Error: $error');
          });

      _isListening = true;
      print('✅ Listener started!');
    } catch (e) {
      print('❌ Error: $e');
    }
  }

  /// Initialize local notifications
  Future<void> _initializeNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _notifications.initialize(initSettings);
  }

  /// Handle incoming notification
  Future<void> _handleNotification(Map<String, dynamic> record) async {
    try {
      final targetUserIds = List<String>.from(record['target_user_ids'] ?? []);
      final title = record['title'] as String;
      final body = record['body'] as String;
      final notificationType = record['notification_type'] as String? ?? 'general';
      
      final currentUserId = _supabase.auth.currentUser?.id;
      print('Current user: $currentUserId');
      print('Targets: $targetUserIds');
      
      if (currentUserId != null && targetUserIds.contains(currentUserId)) {
        print('✅ Showing notification!');
        await _showStyledNotification(
          title: title, 
          body: body,
          type: notificationType,
        );
      } else {
        print('ℹ️ Not for this user');
      }
    } catch (e) {
      print('❌ Error handling notification: $e');
    }
  }

  /// Show beautifully styled notification
  Future<void> _showStyledNotification({
    required String title,
    required String body,
    required String type,
  }) async {
    try {
      // Enhanced Android notification with beautiful styling
      final androidDetails = AndroidNotificationDetails(
        'campuscar_channel', // Channel ID
        'CampusCar Notifications', // Channel name
        channelDescription: 'Stay updated with your rides and bookings',
        importance: Importance.max,
        priority: Priority.max,
        
        // Sound & Vibration
        playSound: true,
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 500, 250, 500]), // Custom vibration
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
          summaryText: 'CampusCar - Your Campus Carpool', // Subtitle text
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
        
        // Grouping
        groupKey: 'campuscar_notifications',
        setAsGroupSummary: false,
        
        // Auto-cancel when tapped
        autoCancel: true,
        
        // Full screen for important notifications (optional)
        fullScreenIntent: false,
        
        // Ongoing for persistent notifications
        ongoing: false,
        
        // Additional styling
        category: AndroidNotificationCategory.message,
        channelShowBadge: true,
        showProgress: false,
      );
      
      // iOS notification details
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        badgeNumber: 1,
        subtitle: 'CampusCar',
        interruptionLevel: InterruptionLevel.timeSensitive,
      );
      
      final notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );
      
      // Generate unique notification ID
      final notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      
      // Show the notification
      await _notifications.show(
        notificationId,
        title,
        body,
        notificationDetails,
        payload: type,
      );
      
      print('✅ Styled notification shown! 🎨');
    } catch (e) {
      print('❌ Error showing styled notification: $e');
    }
  }
  
  /// Get vibrant color based on notification type (like the screenshot)
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
      default:
        return const Color(0xFF1976D2); // Dark Blue (default)
    }
  }

  /// Stop listening
  void stopListening() {
    _channel?.unsubscribe();
    _isListening = false;
  }
}

