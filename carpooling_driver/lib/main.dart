import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'auth/login_page.dart';
import 'features/driver_dashboard/driver_dashboard_page.dart';
import 'services/auth_service.dart';
import 'services/deep_link_service.dart';
import 'services/push_notification_service.dart';
import 'services/push_notification_listener_simple.dart';
import 'features/notifications/presentation/widgets/notification_listener.dart';

// Background message handler must be top-level function
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  await firebaseMessagingBackgroundHandler(message);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  print('🚀 Starting CampusCar Driver App...');
  
  // Initialize Supabase
  // ⚠️ IMPORTANT: Replace with your actual anon key from Supabase Dashboard
  // The key should start with "eyJ..." (it's a JWT token)
  // Get the correct key from: https://app.supabase.com/project/nldxaxthaqefugkokwhh/settings/api
  try {
    await Supabase.initialize(
      url: 'https://nldxaxthaqefugkokwhh.supabase.co',
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5sZHhheHRoYXFlZnVna29rd2hoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjM2NDQ0NjUsImV4cCI6MjA3OTIyMDQ2NX0.7LsKZjxUwmcZCmKg9UJUXJ5Zsz8disVB1Hx7hQ_Liyo', // ⚠️ REPLACE THIS!
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
      realtimeClientOptions: const RealtimeClientOptions(
        logLevel: RealtimeLogLevel.info,
        eventsPerSecond: 2,
      ),
    );
    print('✅ Supabase initialized');
  } catch (e) {
    print('❌ Supabase initialization failed: $e');
    print('⚠️ Check your API key in Supabase Dashboard!');
  }
  
  // Initialize Firebase only on supported platforms (Android/iOS)
  print('📱 Platform check: isWeb=$kIsWeb, isAndroid=${!kIsWeb && Platform.isAndroid}, isIOS=${!kIsWeb && Platform.isIOS}');
  
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    try {
      print('🔥 Initializing Firebase...');
      await Firebase.initializeApp();
      print('✅ Firebase initialized successfully');
      
      // Set up background message handler
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
      print('✅ Background handler set up');
      
      // Initialize Push Notifications
      print('🔔 Initializing Push Notifications...');
      await PushNotificationService.instance.initialize();
      print('✅ Push notifications initialized successfully');
    } catch (e, stackTrace) {
      print('❌ Firebase initialization failed: $e');
      print('Stack trace: $stackTrace');
    }
  } else {
    print('ℹ️ Push notifications not supported on this platform');
  }
  
  runApp(
    const ProviderScope(
      child: DriverApp(),
    ),
  );
}

class DriverApp extends StatelessWidget {
  const DriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return RealtimeNotificationListener(
      child: MaterialApp(
        title: 'CampusCar - Driver',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.orange, // Different color for driver app
          ),
          useMaterial3: true,
        ),
        home: const AuthWrapper(),
      ),
    );
  }
}

// Auth Wrapper to handle authentication state and deep links
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final DeepLinkService _deepLinkService = DeepLinkService();
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey = 
      GlobalKey<ScaffoldMessengerState>();
  bool _listenerStarted = false;

  @override
  void initState() {
    super.initState();
    _initializeDeepLinking();
    // Don't start listener here - wait for user to be authenticated
  }

  Future<void> _initializeDeepLinking() async {
    await _deepLinkService.initialize(
      onEmailConfirmed: (message) {
        _scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      },
      onError: (error) {
        _scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text(error),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      },
    );
  }

  Future<void> _initializePushNotificationListener() async {
    print('🔄 _initializePushNotificationListener CALLED');
    try {
      print('⏳ Waiting for auth to initialize...');
      await Future.delayed(const Duration(seconds: 2));
      
      // Check if user is authenticated
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        print('⚠️ No user logged in, skipping push notification listener');
        return;
      }
      
      print('👤 User ID: ${user.id}');
      print('📡 Starting push notification listener...');
      
      await PushNotificationListenerSimple.instance.startListening();
      
      print('✅ Push notification listener started successfully!');
    } catch (e, stackTrace) {
      print('❌ Error starting push notification listener: $e');
      print('Stack trace: $stackTrace');
    }
  }

  @override
  void dispose() {
    _deepLinkService.dispose();
    PushNotificationListenerSimple.instance.stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();
    
    return ScaffoldMessenger(
      key: _scaffoldMessengerKey,
      child: StreamBuilder<AuthState>(
        stream: authService.authStateChanges,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            );
          }

          final session = snapshot.hasData ? snapshot.data!.session : null;
          
          // Start listener when user logs in
          if (session != null && !_listenerStarted) {
            _listenerStarted = true;
            // Use post-frame callback to ensure it runs after build completes
            WidgetsBinding.instance.addPostFrameCallback((_) {
              print('🔄 Post-frame callback triggered for push notification listener');
              _initializePushNotificationListener();
            });
          }
          
          if (session != null) {
            return const DriverDashboardPage();
          } else {
            return const LoginPage();
          }
        },
      ),
    );
  }
}
