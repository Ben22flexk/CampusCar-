import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:developer' as developer;

/// Service to track and update driver location in real-time
class LocationTrackingService {
  final _supabase = Supabase.instance.client;
  Timer? _locationTimer;
  String? _currentRideId;
  bool _isTracking = false;

  /// Start tracking location for a ride
  Future<void> startTracking(String rideId) async {
    if (_isTracking) {
      developer.log('⚠️  Already tracking', name: 'LocationTracking');
      return;
    }

    _currentRideId = rideId;
    _isTracking = true;

    developer.log('🚗 Starting location tracking for ride: $rideId', name: 'LocationTracking');

    // Check location permissions
    final hasPermission = await _checkLocationPermission();
    if (!hasPermission) {
      throw Exception('Location permission denied');
    }

    // Start periodic location updates (every 10 seconds)
    _locationTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _updateLocation(),
    );

    // Send initial location immediately
    await _updateLocation();
  }

  /// Stop tracking location
  void stopTracking() {
    developer.log('🛑 Stopping location tracking', name: 'LocationTracking');
    _locationTimer?.cancel();
    _locationTimer = null;
    _isTracking = false;
    _currentRideId = null;
  }

  /// Check if currently tracking
  bool get isTracking => _isTracking;

  /// Update location to database
  Future<void> _updateLocation() async {
    if (_currentRideId == null) return;

    try {
      // Get current position
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      developer.log(
        '📍 Location: ${position.latitude}, ${position.longitude}',
        name: 'LocationTracking',
      );

      // Update location in database
      await _supabase.rpc('update_driver_location', params: {
        'p_ride_id': _currentRideId,
        'p_latitude': position.latitude,
        'p_longitude': position.longitude,
        'p_heading': position.heading,
        'p_speed': position.speed * 3.6, // Convert m/s to km/h
        'p_accuracy': position.accuracy,
      });

      developer.log('✅ Location updated successfully', name: 'LocationTracking');
    } catch (e) {
      developer.log('❌ Error updating location: $e', name: 'LocationTracking');
    }
  }

  /// Check and request location permission
  Future<bool> _checkLocationPermission() async {
    // Check if location services are enabled
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      developer.log('❌ Location services are disabled', name: 'LocationTracking');
      return false;
    }

    // Check permission
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        developer.log('❌ Location permission denied', name: 'LocationTracking');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      developer.log('❌ Location permission denied forever', name: 'LocationTracking');
      return false;
    }

    developer.log('✅ Location permission granted', name: 'LocationTracking');
    return true;
  }

  /// Get current location once
  Future<Position> getCurrentLocation() async {
    final hasPermission = await _checkLocationPermission();
    if (!hasPermission) {
      throw Exception('Location permission denied');
    }

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  /// Start ride with initial location
  Future<void> startRide(String rideId) async {
    try {
      // Get current location
      final position = await getCurrentLocation();

      // Call start_ride function
      await _supabase.rpc('start_ride', params: {
        'p_ride_id': rideId,
        'p_initial_latitude': position.latitude,
        'p_initial_longitude': position.longitude,
      });

      developer.log('✅ Ride started successfully', name: 'LocationTracking');

      // Start continuous tracking
      await startTracking(rideId);
    } catch (e) {
      developer.log('❌ Error starting ride: $e', name: 'LocationTracking');
      rethrow;
    }
  }

  /// Dispose resources
  void dispose() {
    stopTracking();
  }
}

