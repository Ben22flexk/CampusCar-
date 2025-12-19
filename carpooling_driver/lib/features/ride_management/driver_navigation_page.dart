import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:carpooling_driver/features/notifications/data/datasources/notification_service.dart';
import 'package:carpooling_driver/services/messaging_service.dart';
import 'package:carpooling_driver/pages/driver_ride_summary_page.dart';
import 'package:carpooling_driver/core/network/mqtt_service.dart';
import 'package:carpooling_driver/core/network/mqtt_config.dart';
import 'package:carpooling_driver/services/driver_location_publisher.dart';
import 'dart:developer' as developer;

/// Driver Navigation Page - Handles turn-by-turn navigation and pickup tracking
class DriverNavigationPage extends StatefulWidget {
  final String rideId;
  final List<Map<String, dynamic>> passengers; // List of passengers with pickup locations

  const DriverNavigationPage({
    super.key,
    required this.rideId,
    required this.passengers,
  });

  @override
  State<DriverNavigationPage> createState() => _DriverNavigationPageState();
}

class _DriverNavigationPageState extends State<DriverNavigationPage> {
  final _supabase = Supabase.instance.client;
  
  int _currentPickupIndex = 0;
  bool _isProcessing = false;
  Map<String, dynamic>? _rideData;
  Position? _currentPosition;
  late final MqttService _mqttService;
  DriverLocationPublisher? _driverLocationPublisher;

  @override
  void initState() {
    super.initState();
    _mqttService = MqttService();
    _loadRideData();
    _getCurrentLocation();
    _loadPickupProgress();
    _startMqttPublishing();
  }

  Future<void> _startMqttPublishing() async {
    try {
      final driverId = _supabase.auth.currentUser?.id;
      if (driverId == null) {
        developer.log(
          '⚠️ Cannot start MQTT publishing: no driver ID',
          name: 'DriverNavigation',
        );
        return;
      }

      _driverLocationPublisher ??= DriverLocationPublisher(_mqttService);
      await _driverLocationPublisher!.start(
        driverId: driverId,
        mqttUsername: MqttConfig.driverUsername,
        mqttPassword: MqttConfig.driverPassword,
      );

      developer.log(
        '✅ MQTT live location publishing started',
        name: 'DriverNavigation',
      );
    } catch (e, stackTrace) {
      developer.log(
        '❌ Error starting MQTT publishing: $e',
        name: 'DriverNavigation',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _stopMqttPublishing() async {
    try {
      await _driverLocationPublisher?.stop();
      _mqttService.dispose();
      developer.log(
        '🛑 MQTT live location publishing stopped',
        name: 'DriverNavigation',
      );
    } catch (e, stackTrace) {
      developer.log(
        '⚠️ Error stopping MQTT publishing: $e',
        name: 'DriverNavigation',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  void dispose() {
    _stopMqttPublishing();
    super.dispose();
  }
  
  /// Load saved pickup progress from database
  Future<void> _loadPickupProgress() async {
    try {
      // Check which passengers have already been picked up
      int completedPickups = 0;
      for (int i = 0; i < widget.passengers.length; i++) {
        final booking = await _supabase
            .from('bookings')
            .select('pickup_status')
            .eq('id', widget.passengers[i]['booking_id'])
            .maybeSingle();
        
        if (booking != null && booking['pickup_status'] == 'arrived') {
          completedPickups++;
        } else {
          break; // Stop at first non-arrived passenger
        }
      }
      
      if (completedPickups > 0) {
        setState(() {
          _currentPickupIndex = completedPickups;
        });
        developer.log('📍 Restored pickup progress: $completedPickups/${widget.passengers.length} completed', 
                     name: 'DriverNavigation');
      }
    } catch (e) {
      developer.log('Error loading pickup progress: $e', name: 'DriverNavigation');
    }
  }

  Future<void> _loadRideData() async {
    try {
      final response = await _supabase
          .from('rides')
          .select()
          .eq('id', widget.rideId)
          .single();
      
      setState(() {
        _rideData = response;
      });
    } catch (e) {
      developer.log('Error loading ride data: $e', name: 'DriverNavigation');
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition();
      setState(() {
        _currentPosition = position;
      });
    } catch (e) {
      developer.log('Error getting location: $e', name: 'DriverNavigation');
    }
  }

  /// Get current pickup location
  Map<String, dynamic>? get _currentPickup {
    if (_currentPickupIndex < widget.passengers.length) {
      return widget.passengers[_currentPickupIndex];
    }
    return null;
  }

  /// Check if all pickups are completed
  bool get _allPickupsCompleted => _currentPickupIndex >= widget.passengers.length;

  /// Open Waze navigation
  Future<void> _openWaze() async {
    final pickup = _currentPickup;
    if (pickup == null && !_allPickupsCompleted) return;

    try {
      String lat, lng, label;
      
      if (_allPickupsCompleted && _rideData != null) {
        // Navigate to final destination
        lat = _rideData!['to_lat'].toString();
        lng = _rideData!['to_lng'].toString();
        label = _rideData!['to_location'] ?? 'Destination';
      } else if (pickup != null) {
        // Navigate to pickup
        lat = pickup['pickup_lat'].toString();
        lng = pickup['pickup_lng'].toString();
        label = pickup['pickup_location'] ?? 'Pickup';
      } else {
        return;
      }

      final url = Uri.parse('waze://?ll=$lat,$lng&navigate=yes&z=10');
      
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
        developer.log('✅ Opened Waze navigation', name: 'DriverNavigation');
      } else {
        // Fallback to Waze website
        final webUrl = Uri.parse('https://www.waze.com/ul?ll=$lat,$lng&navigate=yes');
        await launchUrl(webUrl, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      developer.log('❌ Error opening Waze: $e', name: 'DriverNavigation');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open Waze: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Open Google Maps navigation
  Future<void> _openGoogleMaps() async {
    final pickup = _currentPickup;
    if (pickup == null && !_allPickupsCompleted) return;

    try {
      String lat, lng, label;
      
      if (_allPickupsCompleted && _rideData != null) {
        // Navigate to final destination
        lat = _rideData!['to_lat'].toString();
        lng = _rideData!['to_lng'].toString();
        label = Uri.encodeComponent(_rideData!['to_location'] ?? 'Destination');
      } else if (pickup != null) {
        // Navigate to pickup
        lat = pickup['pickup_lat'].toString();
        lng = pickup['pickup_lng'].toString();
        label = Uri.encodeComponent(pickup['pickup_location'] ?? 'Pickup');
      } else {
        return;
      }

      // Try Google Maps app first
      final mapsUrl = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
      
      if (await canLaunchUrl(mapsUrl)) {
        await launchUrl(mapsUrl, mode: LaunchMode.externalApplication);
        developer.log('✅ Opened Google Maps app', name: 'DriverNavigation');
      } else {
        // Fallback to web
        final webUrl = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&destination_place_id=$label');
        await launchUrl(webUrl, mode: LaunchMode.externalApplication);
        developer.log('✅ Opened Google Maps web', name: 'DriverNavigation');
      }
    } catch (e) {
      developer.log('❌ Error opening Google Maps: $e', name: 'DriverNavigation');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open Google Maps: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Calculate distance between two GPS coordinates in meters
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
  }

  /// Mark current pickup as arrived and notify passenger
  Future<void> _markArrivedAtPickup() async {
    if (_isProcessing) return;

    final pickup = _currentPickup;
    if (pickup == null) return;

    setState(() => _isProcessing = true);

    try {
      // Get current GPS location
      final currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // Get pickup location coordinates
      final pickupLat = pickup['pickup_lat'] as double;
      final pickupLng = pickup['pickup_lng'] as double;

      // Calculate distance between driver and pickup location
      final distance = _calculateDistance(
        currentPosition.latitude,
        currentPosition.longitude,
        pickupLat,
        pickupLng,
      );

      developer.log(
        '📍 Distance to pickup: ${distance.toStringAsFixed(2)}m',
        name: 'DriverNavigation',
      );

      // Verify driver is within 100 meters of pickup location
      if (distance > 100) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'You haven\'t arrived at the exact pickup location yet.\n'
                'You are ${distance.toStringAsFixed(0)}m away. Please get closer.',
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 4),
            ),
          );
        }
        setState(() => _isProcessing = false);
        return;
      }

      final passengerId = pickup['passenger_id'];
      final passengerName = pickup['passenger_name'] ?? 'Passenger';
      final driverId = _supabase.auth.currentUser?.id;
      
      if (driverId == null) {
        throw Exception('Driver not authenticated');
      }

      developer.log('📍 Driver arrived (verified within 100m) - notifying passenger: $passengerName', name: 'DriverNavigation');
      
      // 1. Send push notification
      final notificationService = NotificationService();
      await notificationService.createNotification(
        userId: passengerId,
        title: '🚗 Driver has arrived!',
        message: 'Your driver has arrived at the pickup location. Please head out!',
        type: 'driver_arrived',
        relatedId: widget.rideId,
      );
      developer.log('✅ Push notification sent', name: 'DriverNavigation');

      // 2. Send in-app message "I have arrived!"
      final messagingService = MessagingService();
      await messagingService.sendMessage(
        rideId: widget.rideId,
        receiverId: passengerId,
        messageText: 'I have arrived! 🚗',
      );
      developer.log('✅ In-app message sent', name: 'DriverNavigation');

      // 3. Update booking status
      await _supabase
          .from('bookings')
          .update({'pickup_status': 'arrived'})
          .eq('id', pickup['booking_id']);
      developer.log('✅ Booking status updated', name: 'DriverNavigation');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ $passengerName notified via notification & message!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }

      // Move to next pickup or destination
      await Future.delayed(const Duration(seconds: 1));
      _proceedToNext();
    } catch (e) {
      developer.log('❌ Error marking arrival: $e', name: 'DriverNavigation');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to notify passenger: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  /// Proceed to next pickup or destination
  void _proceedToNext() {
    if (_currentPickupIndex < widget.passengers.length - 1) {
      // More pickups remaining
      setState(() {
        _currentPickupIndex++;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('📍 Proceeding to next pickup...'),
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      // All pickups done, go to destination
      setState(() {
        _currentPickupIndex = widget.passengers.length;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎯 All passengers picked up! Heading to destination...'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  /// Complete the trip - called when confirming arrival at destination
  Future<void> _completeTripDialog() async {
    if (_isProcessing) return;

    setState(() => _isProcessing = true);

    try {
      // Get current GPS location
      final currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // Get destination coordinates
      if (_rideData == null) {
        throw Exception('Ride data not loaded');
      }

      final destLat = _rideData!['to_lat'] as double;
      final destLng = _rideData!['to_lng'] as double;

      // Calculate distance to destination
      final distance = _calculateDistance(
        currentPosition.latitude,
        currentPosition.longitude,
        destLat,
        destLng,
      );

      developer.log(
        '🎯 Distance to destination: ${distance.toStringAsFixed(2)}m',
        name: 'DriverNavigation',
      );

      // Verify driver is within 100 meters of destination
      if (distance > 100) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'You haven\'t arrived at the exact destination yet.\n'
                'You are ${distance.toStringAsFixed(0)}m away. Please get closer.',
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 4),
            ),
          );
        }
        setState(() => _isProcessing = false);
        return;
      }

      developer.log('🎯 Marking arrival at destination (verified within 100m)', name: 'DriverNavigation');

      // Mark all bookings as completed and notify passengers
      final notificationService = NotificationService();
      final messagingService = MessagingService();
      
      for (final passenger in widget.passengers) {
        final passengerId = passenger['passenger_id'];
        final bookingId = passenger['booking_id'];

        // Mark booking as completed
        await _supabase
            .from('bookings')
            .update({'request_status': 'completed'})
            .eq('id', bookingId);
        
        developer.log('✅ Booking $bookingId marked as completed', name: 'DriverNavigation');

        // Send push notification
        await notificationService.createNotification(
          userId: passengerId,
          title: '🎯 Destination Reached!',
          message: 'You have arrived at your destination. Please proceed to payment.',
          type: 'destination_arrived',
          relatedId: bookingId,
        );

        // Send in-app message
        await messagingService.sendMessage(
          rideId: widget.rideId,
          receiverId: passengerId,
          messageText: 'We have arrived at the destination! 🎯',
        );
      }

      developer.log('✅ All bookings completed and passengers notified', name: 'DriverNavigation');

      // Show confirmation dialog and redirect
      if (mounted) {
  // Show dialog and wait for OK
  final proceed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.check_circle, color: Colors.green, size: 64),
      title: const Text('🎯 Destination Reached!'),
      content: const Text(
        'All passengers have been notified.\n\n'
        'Press OK to complete the ride.',
        textAlign: TextAlign.center,
      ),
      actions: [
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context, true);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            minimumSize: const Size(double.infinity, 50),
          ),
          child: const Text('OK - View Summary'),
        ),
      ],
    ),
  );
  // Only run this after the dialog is dismissed and the context is safe!
  if (proceed == true) {
    await _completeTrip();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => DriverRideSummaryPage(
            rideId: widget.rideId,
          ),
        ),
      );
    }
  }
}

    } catch (e) {
      developer.log('❌ Error at destination arrival: $e', name: 'DriverNavigation');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to notify passengers: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _completeTrip() async {
    try {
      setState(() => _isProcessing = true);

      // Call complete_ride function
      await _supabase.rpc('complete_ride', params: {
        'p_ride_id': widget.rideId,
      });

      developer.log('✅ Trip completed', name: 'DriverNavigation');

      if (mounted) {
        //Navigator.of(context).popUntil((route) => route.isFirst);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 Trip completed! Passengers have been notified.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      developer.log('❌ Error completing trip: $e', name: 'DriverNavigation');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to complete trip: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentPickup = _currentPickup;

    return WillPopScope(
      onWillPop: () async {
        // If at final destination, go back to ride details instead of previous pickup
        if (_allPickupsCompleted) {
          Navigator.of(context).pop();
          return false;
        }
        // Otherwise allow normal back navigation
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Navigation'),
          backgroundColor: Colors.green,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              // If at final destination, go back to ride details
              if (_allPickupsCompleted) {
                Navigator.of(context).pop();
              } else {
                // Otherwise show confirmation dialog
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Cancel Navigation?'),
                    content: const Text('Are you sure you want to go back?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('No'),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.pop(context);
                        },
                        child: const Text('Yes'),
                      ),
                    ],
                  ),
                );
              }
            },
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _getCurrentLocation,
              tooltip: 'Refresh location',
            ),
          ],
        ),
      body: SafeArea(
        child: Column(
          children: [
            // Progress indicator
            _buildProgressBar(),

            // Current destination card
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Status card
                    _buildStatusCard(theme, currentPickup),

                    const SizedBox(height: 24),

                    // Navigation buttons
                    _buildNavigationButtons(theme),

                    const SizedBox(height: 24),

                    // Action button (Arrived / Complete Trip)
                    _buildActionButton(theme, currentPickup),

                    const SizedBox(height: 16),

                    // Passenger list
                    if (!_allPickupsCompleted) _buildPassengerList(theme),
                  ],
                ),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildProgressBar() {
    final totalStops = widget.passengers.length + 1; // pickups + destination
    final progress = (_currentPickupIndex + 1) / totalStops;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.green.shade50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _allPickupsCompleted
                      ? 'Final Destination'
                      : 'Pickup ${_currentPickupIndex + 1} of ${widget.passengers.length}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${(_currentPickupIndex + 1)}/$totalStops stops',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.grey[300],
            color: Colors.green,
            minHeight: 8,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(ThemeData theme, Map<String, dynamic>? currentPickup) {
    String title, subtitle, location;
    IconData icon;
    Color iconColor;

    if (_allPickupsCompleted && _rideData != null) {
      title = 'Final Destination';
      subtitle = 'All passengers picked up';
      location = _rideData!['to_location'] ?? 'Destination';
      icon = Icons.flag;
      iconColor = Colors.green;
    } else if (currentPickup != null) {
      title = 'Pickup Location';
      subtitle = currentPickup['passenger_name'] ?? 'Passenger';
      location = currentPickup['pickup_location'] ?? 'Pickup Point';
      icon = Icons.person_pin_circle;
      iconColor = Colors.blue;
    } else {
      title = 'Loading...';
      subtitle = '';
      location = '';
      icon = Icons.help;
      iconColor = Colors.grey;
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: iconColor, size: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.grey[600],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (location.isNotEmpty) ...[
              const Divider(height: 24),
              Row(
                children: [
                  Icon(Icons.location_on, color: Colors.red, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      location,
                      style: theme.textTheme.bodyLarge,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNavigationButtons(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Choose Navigation App',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _openWaze,
                icon: const Icon(Icons.navigation),
                label: const Text('Waze'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.lightBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _openGoogleMaps,
                icon: const Icon(Icons.map),
                label: const Text('Google Maps'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionButton(ThemeData theme, Map<String, dynamic>? currentPickup) {
    if (_allPickupsCompleted) {
      // Show "We've Arrived at Destination" button
      return ElevatedButton.icon(
        onPressed: _isProcessing ? null : _completeTripDialog,
        icon: _isProcessing
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.location_on),
        label: const Text('We\'ve Arrived at Destination'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    } else {
      // Show "Arrived" and "Next" buttons
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ElevatedButton.icon(
            onPressed: _isProcessing ? null : _markArrivedAtPickup,
            icon: _isProcessing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_circle_outline),
            label: const Text('I\'ve Arrived - Notify Passenger'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      );
    }
  }

  Widget _buildPassengerList(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Passengers (${widget.passengers.length})',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        ...List.generate(widget.passengers.length, (index) {
          final passenger = widget.passengers[index];
          final isCompleted = index < _currentPickupIndex;
          final isCurrent = index == _currentPickupIndex;

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            color: isCurrent
                ? Colors.blue.shade50
                : isCompleted
                    ? Colors.green.shade50
                    : null,
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: isCurrent
                    ? Colors.blue
                    : isCompleted
                        ? Colors.green
                        : Colors.grey,
                child: Icon(
                  isCompleted ? Icons.check : Icons.person,
                  color: Colors.white,
                ),
              ),
              title: Text(passenger['passenger_name'] ?? 'Passenger ${index + 1}'),
              subtitle: Text(passenger['pickup_location'] ?? 'Pickup location'),
              trailing: Icon(
                isCurrent
                    ? Icons.navigation
                    : isCompleted
                        ? Icons.check_circle
                        : Icons.circle_outlined,
                color: isCurrent
                    ? Colors.blue
                    : isCompleted
                        ? Colors.green
                        : Colors.grey,
              ),
            ),
          );
        }),
      ],
    );
  }
}

