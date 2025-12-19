import 'dart:math';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Distance calculation utilities for smart matching
class DistanceHelper {
  /// Earth's radius in kilometers
  static const double _earthRadiusKm = 6371.0;
  
  /// Calculate distance between two points using Haversine formula
  /// Returns distance in kilometers
  static double calculateDistance({
    required double lat1,
    required double lon1,
    required double lat2,
    required double lon2,
  }) {
    // Convert to radians
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    
    return _earthRadiusKm * c;
  }
  
  /// Calculate distance from LatLng objects
  static double calculateDistanceLatLng({
    required LatLng point1,
    required LatLng point2,
  }) {
    return calculateDistance(
      lat1: point1.latitude,
      lon1: point1.longitude,
      lat2: point2.latitude,
      lon2: point2.longitude,
    );
  }
  
  /// Calculate distance in meters
  static double calculateDistanceInMeters({
    required double lat1,
    required double lon1,
    required double lat2,
    required double lon2,
  }) {
    return calculateDistance(
      lat1: lat1,
      lon1: lon1,
      lat2: lat2,
      lon2: lon2,
    ) * 1000;
  }
  
  /// Check if pickup location is within acceptable radius (5km)
  static bool isWithinPickupRadius({
    required LatLng passengerLocation,
    required LatLng pickupLocation,
  }) {
    const maxPickupRadiusKm = 5.0;
    final distance = calculateDistanceLatLng(
      point1: passengerLocation,
      point2: pickupLocation,
    );
    return distance <= maxPickupRadiusKm;
  }
  
  /// Check if destination is within acceptable radius (500m)
  static bool isWithinDestinationRadius({
    required LatLng driverDestination,
    required LatLng passengerDestination,
  }) {
    const maxDestinationRadiusMeters = 500.0;
    final distanceMeters = calculateDistanceInMeters(
      lat1: driverDestination.latitude,
      lon1: driverDestination.longitude,
      lat2: passengerDestination.latitude,
      lon2: passengerDestination.longitude,
    );
    return distanceMeters <= maxDestinationRadiusMeters;
  }
  
  /// Convert degrees to radians
  static double _toRadians(double degrees) {
    return degrees * pi / 180;
  }
  
  /// Format distance as human-readable string
  static String formatDistance(double distanceKm) {
    if (distanceKm < 1.0) {
      return '${(distanceKm * 1000).toStringAsFixed(0)}m';
    } else {
      return '${distanceKm.toStringAsFixed(1)}km';
    }
  }
}

