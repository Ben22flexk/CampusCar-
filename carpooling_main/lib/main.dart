import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'dashboard.dart';
import 'auth/login_page.dart';
import 'pages/ride_summary_payment_page.dart';
import 'services/auth_service.dart';
import 'services/deep_link_service.dart';
import 'services/push_notification_service.dart';
import 'services/push_notification_listener_service.dart';
import 'services/app_lifecycle_service.dart';
import 'features/notifications/presentation/widgets/notification_listener.dart';

// Background message handler - must be top-level function
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Initialize Firebase if not already initialized
  await Firebase.initializeApp();
  
  print('📨 Background message received');
  print('   Title: ${message.notification?.title}');
  print('   Body: ${message.notification?.body}');
  print('   Data: ${message.data}');
  
  // Background notifications are automatically shown by Android/iOS
  // Additional processing can be done here if needed
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  print('🚀 Initializing CampusCar Passenger App');
  
  // Initialize Supabase
  // ⚠️ IMPORTANT: Replace with your actual anon key from Supabase Dashboard
  // The key should start with "eyJ..." (it's a JWT token)
  // Current key format is invalid - get the correct one from:
  // https://app.supabase.com/project/nldxaxthaqefugkokwhh/settings/api
  try {
    await Supabase.initialize(
      url: 'https://nldxaxthaqefugkokwhh.supabase.co',
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5sZHhheHRoYXFlZnVna29rd2hoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjM2NDQ0NjUsImV4cCI6MjA3OTIyMDQ2NX0.7LsKZjxUwmcZCmKg9UJUXJ5Zsz8disVB1Hx7hQ_Liyo', // ⚠️ REPLACE THIS!
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
      realtimeClientOptions: const RealtimeClientOptions(
        logLevel: RealtimeLogLevel.info,
        eventsPerSecond: 2, // Reduce load
      ),
    );
    print('✅ Supabase initialized');
  } catch (e) {
    print('❌ Supabase initialization failed: $e');
    print('⚠️ Check your API key in Supabase Dashboard!');
  }

  // Initialize Firebase (only on supported platforms)
  print('📱 Platform check: isWeb=$kIsWeb, isAndroid=${!kIsWeb && Platform.isAndroid}, isIOS=${!kIsWeb && Platform.isIOS}');
  
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    try {
      print('🔥 Initializing Firebase...');
      await Firebase.initializeApp();
      print('✅ Firebase initialized successfully');

      // Set up background message handler
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
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

  // Initialize app lifecycle service
  AppLifecycleService().initialize();
  print('✅ App lifecycle service initialized');

  // Set up goodbye notification on app pause
  AppLifecycleService().onAppPaused = () {
    print('👋 App paused - showing goodbye notification');
    PushNotificationService.instance.showGoodbyeNotification();
  };
  
  runApp(
    const ProviderScope(
      child: CarpoolingApp(),
    ),
  );
}

// Global navigator key for navigation from anywhere
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class CarpoolingApp extends StatelessWidget {
  const CarpoolingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return RealtimeNotificationListener(
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'CampusCar',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
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
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  bool _notificationsInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeDeepLinking();
    // Don't initialize notifications here - wait for user to be authenticated
  }

  Future<void> _initializeDeepLinking() async {
    await _deepLinkService.initialize(
      onEmailConfirmed: (message) {
        // Show success message
        _scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      },
      onError: (error) {
        // Show error message
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

  Future<void> _initializePushNotifications() async {
    print('🔄 _initializePushNotifications CALLED');
    try {
      print('⏳ Waiting 2 seconds...');
      await Future.delayed(const Duration(seconds: 2));
      
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        print('⚠️ No user logged in, skipping push notification listener');
        return;
      }
      
      print('👤 User ID: ${user.id}');
      
      // Set up notification callback for navigation
      PushNotificationService.instance.onNotificationReceived = (type, relatedId) {
        print('📱 Notification received callback: type=$type, relatedId=$relatedId');
        
        if (type == 'destination_arrived' && relatedId != null) {
          print('🎯 Navigating to payment page for booking: $relatedId');
          // Navigate to payment page
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => RideSummaryPaymentPage(
                bookingId: relatedId,
              ),
            ),
          );
        }
      };
      print('✅ Notification callback set up');
      
      // Set up Realtime listener for booking status changes
      print('📡 Setting up booking status listener...');
      _setupBookingStatusListener(context);
      
      // Start listener for real-time notifications
      // (PushNotificationService already initialized in main())
      print('📡 Starting push notification listener...');
      await PushNotificationListenerService.instance.startListening();
      print('✅ Push notification listener started successfully!');
    } catch (e, stackTrace) {
      print('❌ Push notification listener error: $e');
      print('Stack trace: $stackTrace');
    }
  }

  void _setupBookingStatusListener(BuildContext context) {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    
    print('📡 Subscribing to booking status changes for user: $userId');
    
    // Listen for booking status changes
    Supabase.instance.client
        .channel('booking_status_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'bookings',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'passenger_id',
            value: userId,
          ),
          callback: (payload) {
            print('🔔 Booking update detected: ${payload.newRecord}');
            
            final newStatus = payload.newRecord['request_status'];
            final bookingId = payload.newRecord['id'];
            
            if (newStatus == 'completed' && bookingId != null) {
              print('✅ Booking completed - redirecting to payment page');
              print('   Booking ID: $bookingId');
              
              // Navigate to payment page
              WidgetsBinding.instance.addPostFrameCallback((_) {
                final navigator = navigatorKey.currentState;
                if (navigator != null) {
                  print('   🚀 Executing navigation...');
                  navigator.push(
                    MaterialPageRoute(
                      builder: (context) => RideSummaryPaymentPage(
                        bookingId: bookingId,
                      ),
                    ),
                  );
                }
              });
            }
          },
        )
        .subscribe();
    
    print('✅ Booking status listener active');
  }

  @override
  void dispose() {
    _deepLinkService.dispose();
    PushNotificationListenerService.instance.stopListening();
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

          // Check if user is logged in
          final session = snapshot.hasData ? snapshot.data!.session : null;
          
          // Initialize notifications when user logs in
          if (session != null && !_notificationsInitialized) {
            _notificationsInitialized = true;
            // Use post-frame callback to ensure it runs after build completes
            WidgetsBinding.instance.addPostFrameCallback((_) {
              print('🔄 Post-frame callback triggered for push notifications');
              _initializePushNotifications();
            });
          }
          
          if (session != null) {
            // User is logged in - show dashboard
            return const MainDashboardPage();
          } else {
            // User is not logged in - show login page
            return const LoginPage();
          }
        },
      ),
    );
  }
}
