import 'package:flutter/material.dart';
import 'dart:developer' as developer;

class AppLifecycleService with WidgetsBindingObserver {
  static final AppLifecycleService _instance = AppLifecycleService._internal();
  factory AppLifecycleService() => _instance;
  AppLifecycleService._internal();

  // Callbacks
  Function()? onAppPaused;
  Function()? onAppResumed;
  Function()? onAppClosed;

  bool _isInitialized = false;

  /// Initialize the service and register lifecycle observer
  void initialize() {
    if (_isInitialized) return;
    
    WidgetsBinding.instance.addObserver(this);
    _isInitialized = true;
    developer.log('✅ App lifecycle service initialized', name: 'AppLifecycleService');
  }

  /// Clean up when service is no longer needed
  void dispose() {
    if (!_isInitialized) return;
    
    WidgetsBinding.instance.removeObserver(this);
    _isInitialized = false;
    developer.log('🗑️ App lifecycle service disposed', name: 'AppLifecycleService');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    developer.log('🔄 App lifecycle state changed: $state', name: 'AppLifecycleService');

    switch (state) {
      case AppLifecycleState.resumed:
        // App came to foreground
        developer.log('👋 Welcome back!', name: 'AppLifecycleService');
        onAppResumed?.call();
        break;

      case AppLifecycleState.inactive:
        // App is inactive (e.g., receiving a call, in app switcher)
        developer.log('⏸️ App is inactive', name: 'AppLifecycleService');
        break;

      case AppLifecycleState.paused:
        // App is in background
        developer.log('👋 Goodbye! Have a great day!', name: 'AppLifecycleService');
        onAppPaused?.call();
        break;

      case AppLifecycleState.detached:
        // App is detached (about to be destroyed)
        developer.log('🚪 App is closing', name: 'AppLifecycleService');
        onAppClosed?.call();
        break;

      case AppLifecycleState.hidden:
        // App is hidden (on some platforms)
        developer.log('🙈 App is hidden', name: 'AppLifecycleService');
        break;
    }
  }

  /// Show a local notification when app is paused/closed
  Future<void> showGoodbyeNotification() async {
    developer.log('📲 Showing goodbye notification', name: 'AppLifecycleService');
    
    // This will be handled by PushNotificationService
    // We'll trigger it from the app lifecycle
  }
}

