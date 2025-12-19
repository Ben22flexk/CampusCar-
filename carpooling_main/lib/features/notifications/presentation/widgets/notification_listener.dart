import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:carpooling_main/features/notifications/presentation/providers/notification_providers.dart';
import 'package:carpooling_main/features/notifications/presentation/widgets/notification_toast.dart';
import 'package:carpooling_main/features/notifications/domain/entities/notification_entity.dart';
import 'package:carpooling_main/pages/ride_summary_payment_page.dart';
import 'package:carpooling_main/pages/live_ride_page.dart';
import 'package:carpooling_main/main.dart' as main_app;
import 'dart:developer' as developer;

/// Widget that listens to new notifications and shows in-app toasts
/// Wrap your app with this widget to enable real-time notification alerts
class RealtimeNotificationListener extends ConsumerStatefulWidget {
  final Widget child;

  const RealtimeNotificationListener({
    super.key,
    required this.child,
  });

  @override
  ConsumerState<RealtimeNotificationListener> createState() => _RealtimeNotificationListenerState();
}

class _RealtimeNotificationListenerState extends ConsumerState<RealtimeNotificationListener> {
  List<NotificationEntity> _previousNotifications = [];
  bool _isInitialized = false;

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<List<NotificationEntity>>>(
      notificationsStreamProvider,
      (previous, next) {
        next.whenData((notifications) {
          // Skip initial load
          if (!_isInitialized) {
            _previousNotifications = notifications;
            _isInitialized = true;
            return;
          }

          // Find new notifications
          final newNotifications = notifications.where((notification) {
            return !_previousNotifications.any((prev) => prev.id == notification.id);
          }).toList();

          // Show toast for each new notification
          for (final notification in newNotifications) {
            _showNotificationToast(notification);
            
            // Handle ride_approved notifications
            if (notification.type == 'ride_approved' && notification.relatedId != null) {
              developer.log('✅ Ride approved notification received', name: 'NotificationListener');
              // Toast is already shown by _showNotificationToast
              // No auto-navigation needed, user can view from dashboard
            }
            
            // Auto-navigate for driver_arrived notifications
            if (notification.type == 'driver_arrived' && notification.relatedId != null) {
              developer.log('🚗 Driver arrived - opening live ride page', name: 'NotificationListener');
              
              _openLiveRidePage(notification.relatedId!);
            }
            
            // Auto-navigate for ride_completed notifications
            if (notification.type == 'ride_completed' && notification.relatedId != null) {
              developer.log('🎉 Auto-navigating to payment page for completed ride', name: 'NotificationListener');
              
              // Navigate to payment page after a short delay
              Future.delayed(const Duration(milliseconds: 500), () {
                final navigator = main_app.navigatorKey.currentState;
                if (navigator != null) {
                  navigator.push(
                    MaterialPageRoute(
                      builder: (context) => RideSummaryPaymentPage(
                        bookingId: notification.relatedId!,
                      ),
                    ),
                  );
                }
              });
            }
            
            // Handle destination_arrived notifications - Auto-navigate to payment
            if (notification.type == 'destination_arrived' && notification.relatedId != null) {
              developer.log('🎯 Destination arrived - opening payment page', name: 'NotificationListener');
              developer.log('   Booking ID: ${notification.relatedId}', name: 'NotificationListener');
              
              // Navigate immediately using global navigator
              try {
                final navigator = main_app.navigatorKey.currentState;
                if (navigator != null) {
                  developer.log('   Navigator state found, pushing route...', name: 'NotificationListener');
                  
                  // Schedule navigation for next frame to ensure context is ready
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    developer.log('   ✅ Executing navigation now!', name: 'NotificationListener');
                    navigator.push(
                      MaterialPageRoute(
                        builder: (context) => RideSummaryPaymentPage(
                          bookingId: notification.relatedId!,
                        ),
                      ),
                    ).then((value) {
                      developer.log('   ✅ Navigation completed successfully!', name: 'NotificationListener');
                    }).catchError((error) {
                      developer.log('   ❌ Navigation error: $error', name: 'NotificationListener');
                    });
                  });
                } else {
                  developer.log('   ❌ Navigator key is null - cannot navigate', name: 'NotificationListener');
                }
              } catch (e) {
                developer.log('   ❌ Exception during navigation: $e', name: 'NotificationListener');
              }
            }
          }

          // Update previous notifications
          _previousNotifications = notifications;
        });
      },
    );

    return widget.child;
  }

  void _showNotificationToast(NotificationEntity notification) {
    // Only show toast if context is mounted and user is authenticated
    if (!mounted) return;

    // Show toast after a short delay to ensure context is ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        NotificationToast.show(
          context: context,
          notification: notification,
          onTap: () => _handleNotificationTap(notification),
        );
      }
    });
  }

  void _handleNotificationTap(NotificationEntity notification) {
    // Mark as read when tapped
    final actions = ref.read(notificationActionsProvider);
    if (!notification.isRead) {
      actions.markAsRead(notification.id);
    }

    // Navigate based on notification type
    if (notification.type == 'ride_approved' && notification.relatedId != null) {
      developer.log('✅ Ride approved - showing details', name: 'NotificationListener');
      
      // Show a success dialog or navigate to ride details
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '✅ Your ride request has been approved! Get ready for your trip.',
                  style: TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'View',
            textColor: Colors.white,
            onPressed: () {
              // Navigate to ride details or dashboard
              Navigator.pushNamed(context, '/dashboard');
            },
          ),
        ),
      );
    } else if (notification.type == 'ride_completed' && notification.relatedId != null) {
      developer.log('🎉 Ride completed notification - navigating to payment', name: 'NotificationListener');
      
      final navigator = main_app.navigatorKey.currentState;
      if (navigator != null) {
        navigator.push(
          MaterialPageRoute(
            builder: (context) => RideSummaryPaymentPage(
              bookingId: notification.relatedId!,
            ),
          ),
        );
      }
    } else if (notification.type == 'driver_arrived' && notification.relatedId != null) {
      developer.log('🚗 Driver arrived - opening live ride page', name: 'NotificationListener');
      _openLiveRidePage(notification.relatedId!);
    } else if (notification.type == 'destination_arrived' && notification.relatedId != null) {
      developer.log('🎯 Destination arrived - opening payment page', name: 'NotificationListener');
      
      final navigator = main_app.navigatorKey.currentState;
      if (navigator != null) {
        navigator.push(
          MaterialPageRoute(
            builder: (context) => RideSummaryPaymentPage(
              bookingId: notification.relatedId!,
            ),
          ),
        );
      }
    }
  }

  Future<void> _openLiveRidePage(String rideId) async {
    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;
      
      if (userId == null) return;

      // Get booking and ride details
      final booking = await supabase
          .from('bookings')
          .select('id, ride_id')
          .eq('ride_id', rideId)
          .eq('passenger_id', userId)
          .maybeSingle();

      if (booking == null) return;

      final ride = await supabase
          .from('rides')
          .select('to_lat, to_lng, to_location')
          .eq('id', rideId)
          .maybeSingle();

      if (ride == null) return;

      final navigator = main_app.navigatorKey.currentState;
      if (navigator != null) {
        navigator.push(
          MaterialPageRoute(
            builder: (context) => LiveRidePage(
              rideId: rideId,
              bookingId: booking['id'],
              destinationLat: (ride['to_lat'] as num).toDouble(),
              destinationLng: (ride['to_lng'] as num).toDouble(),
              destinationName: ride['to_location'] ?? 'Destination',
            ),
          ),
        );
      }
    } catch (e) {
      developer.log('❌ Error opening live ride page: $e', name: 'NotificationListener');
    }
  }

}

