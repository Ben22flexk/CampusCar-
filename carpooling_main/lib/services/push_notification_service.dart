import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Background message handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  developer.log(
    '📱 Background notification received: ${message.notification?.title}',
    name: 'PushNotificationService',
  );
  // Handle background notification
  await PushNotificationService.instance.handleBackgroundMessage(message);
}

/// Service for handling push notifications with Firebase Cloud Messaging
class PushNotificationService {
  static final PushNotificationService _instance = PushNotificationService._internal();
  static PushNotificationService get instance => _instance;

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  
  bool _initialized = false;
  String? _fcmToken;

  PushNotificationService._internal();

  /// Initialize push notifications
  Future<void> initialize() async {
    if (_initialized) {
      print('⚠️ Push notifications already initialized');
      return;
    }

    // Only initialize on mobile platforms
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      print('⚠️ Push notifications only available on Android/iOS');
      return;
    }

    try {
      print('🚀 Initializing push notifications...');
      
      // Check if Firebase is initialized and available
      try {
        await _firebaseMessaging.getToken();
      } catch (e) {
        print('⚠️ Firebase not available on this platform - push notifications disabled');
        print('Error: $e');
        return;
      }

      // Request notification permissions
      print('📱 Requesting notification permissions...');
      final settings = await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      print('📱 Permission status: ${settings.authorizationStatus}');
      
      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        print('✅ Notification permission granted');
      } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
        print('⚠️ Notification permission provisional');
      } else {
        print('❌ Notification permission denied: ${settings.authorizationStatus}');
        return;
      }

      // Initialize local notifications for foreground display
      print('🔔 Initializing local notifications...');
      await _initializeLocalNotifications();
      print('✅ Local notifications initialized');

      // Get FCM token
      print('📱 Requesting FCM token...');
      _fcmToken = await _firebaseMessaging.getToken();
      print('📱 FCM Token received: $_fcmToken');
      
      if (_fcmToken == null) {
        print('❌ FCM token is null!');
      } else {
        print('✅ FCM token is valid (length: ${_fcmToken!.length})');
      }

      // Save token to Supabase user metadata
      if (_fcmToken != null) {
        print('💾 Saving FCM token to Supabase...');
        await _saveFCMTokenToSupabase(_fcmToken!);
      } else {
        print('⚠️ Skipping token save - token is null');
      }

      // Listen to token refresh
      _firebaseMessaging.onTokenRefresh.listen((newToken) {
        print('🔄 FCM Token refreshed: $newToken');
        _fcmToken = newToken;
        _saveFCMTokenToSupabase(newToken);
      });

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Handle notification taps when app is in background/terminated
      FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

      // Check if app was opened from a notification
      final initialMessage = await _firebaseMessaging.getInitialMessage();
      if (initialMessage != null) {
        print('📱 App opened from notification');
        _handleNotificationTap(initialMessage);
      }

      _initialized = true;
      print('✅ Push notifications initialized successfully');
    } catch (e, stackTrace) {
      print('❌ Error initializing push notifications: $e');
      print('Stack trace: $stackTrace');
    }
  }

  /// Initialize local notifications for foreground display
  Future<void> _initializeLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        developer.log('🔔 Local notification tapped: ${details.payload}', name: 'PushNotificationService');
        // Handle notification tap
      },
    );

    // Create notification channel for Android
    const androidChannel = AndroidNotificationChannel(
      'high_importance_channel',
      'High Importance Notifications',
      description: 'This channel is used for important notifications.',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
  }

  /// Handle foreground messages (show as local notification)
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    developer.log(
      '📱 Foreground notification: ${message.notification?.title}',
      name: 'PushNotificationService',
    );

    final notification = message.notification;
    final type = message.data['type'] as String?;
    final relatedId = message.data['related_id'] as String?;

    if (notification != null) {
      await _showLocalNotification(
        title: notification.title ?? 'New Notification',
        body: notification.body ?? '',
        payload: message.data.toString(),
      );
    }
    
    // Auto-navigate for destination_arrived
    if (type == 'destination_arrived' && relatedId != null && onNotificationReceived != null) {
      developer.log('🎯 Destination arrived in foreground - triggering navigation', name: 'PushNotificationService');
      onNotificationReceived!(type, relatedId);
    }
  }

  /// Show local notification
  Future<void> _showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'high_importance_channel',
      'High Importance Notifications',
      channelDescription: 'This channel is used for important notifications.',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      notificationDetails,
      payload: payload,
    );
  }

  /// Show goodbye notification when app is closed
  Future<void> showGoodbyeNotification() async {
    await _showLocalNotification(
      title: '👋 Goodbye!',
      body: 'Thanks for using CampusCar. Have a great day!',
    );
  }

  // Callback for handling notification navigation
  Function(String? type, String? relatedId)? onNotificationReceived;
  
  /// Handle notification tap
  void _handleNotificationTap(RemoteMessage message) {
    developer.log(
      '🔔 Notification tapped: ${message.data}',
      name: 'PushNotificationService',
    );
    
    final type = message.data['type'] as String?;
    final relatedId = message.data['related_id'] as String?;

    if (type != null && onNotificationReceived != null) {
      developer.log('📱 Calling notification callback: type=$type, relatedId=$relatedId', name: 'PushNotificationService');
      onNotificationReceived!(type, relatedId);
    }
  }

  /// Handle background message
  Future<void> handleBackgroundMessage(RemoteMessage message) async {
    developer.log(
      '📱 Processing background notification: ${message.notification?.title}',
      name: 'PushNotificationService',
    );
    // Background notifications are automatically shown by the system
    // This is just for logging or additional processing
  }

  /// Save FCM token to Supabase
  Future<void> _saveFCMTokenToSupabase(String token) async {
    try {
      print('💾 _saveFCMTokenToSupabase called with token: ${token.substring(0, 20)}...');
      
      final userId = Supabase.instance.client.auth.currentUser?.id;
      print('👤 Current user ID: $userId');
      
      if (userId == null) {
        print('❌ User not authenticated, cannot save FCM token');
        return;
      }

      print('💾 Attempting to update FCM token in profiles...');
      final response = await Supabase.instance.client
          .from('profiles')
          .update({
            'fcm_token': token,
            'fcm_token_updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', userId)
          .select();

      print('✅ FCM token saved to Supabase successfully!');
      print('Response: $response');
    } catch (e, stackTrace) {
      print('❌ Error saving FCM token: $e');
      print('Stack trace: $stackTrace');
    }
  }

  /// Get FCM token
  String? get fcmToken => _fcmToken;

  /// Subscribe to topic
  Future<void> subscribeToTopic(String topic) async {
    try {
      await _firebaseMessaging.subscribeToTopic(topic);
      developer.log('✅ Subscribed to topic: $topic', name: 'PushNotificationService');
    } catch (e) {
      developer.log('❌ Error subscribing to topic: $e', name: 'PushNotificationService', error: e);
    }
  }

  /// Unsubscribe from topic
  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _firebaseMessaging.unsubscribeFromTopic(topic);
      developer.log('✅ Unsubscribed from topic: $topic', name: 'PushNotificationService');
    } catch (e) {
      developer.log('❌ Error unsubscribing from topic: $e', name: 'PushNotificationService', error: e);
    }
  }
}

