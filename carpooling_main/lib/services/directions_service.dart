import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:developer' as developer;

/// Service to get real driving routes and ETA from Google Directions API
class DirectionsService {
  // Your Google Maps API key
  static const String _apiKey = 'AIzaSyCq-OE3mBpewP0435n0w5jrnzFXUGF-aYY';
  static const String _baseUrl = 'https://maps.googleapis.com/maps/api/directions/json';

  /// Get real driving route and ETA from origin to destination
  Future<DirectionsResult?> getDirections({
    required LatLng origin,
    required LatLng destination,
  }) async {
    try {
      final url = Uri.parse(_baseUrl).replace(queryParameters: {
        'origin': '${origin.latitude},${origin.longitude}',
        'destination': '${destination.latitude},${destination.longitude}',
        'mode': 'driving',
        'departure_time': 'now', // For real-time traffic
        'key': _apiKey,
      });

      developer.log('🗺️ Fetching route from Google Directions API', name: 'DirectionsService');

      final response = await http.get(url).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Request timeout');
        },
      );

      if (response.statusCode != 200) {
        throw Exception('API returned ${response.statusCode}: ${response.body}');
      }

      final data = json.decode(response.body) as Map<String, dynamic>;

      if (data['status'] != 'OK') {
        final status = data['status'] as String;
        final errorMessage = data['error_message'] as String?;
        throw Exception('Directions API error: $status${errorMessage != null ? " - $errorMessage" : ""}');
      }

      final routes = data['routes'] as List<dynamic>;
      if (routes.isEmpty) {
        throw Exception('No routes found');
      }

      final route = routes.first as Map<String, dynamic>;
      final legs = route['legs'] as List<dynamic>;
      if (legs.isEmpty) {
        throw Exception('No legs found in route');
      }

      final leg = legs.first as Map<String, dynamic>;

      // Extract distance and duration
      final distance = leg['distance'] as Map<String, dynamic>;
      final duration = leg['duration'] as Map<String, dynamic>;
      final durationInTraffic = leg['duration_in_traffic'] as Map<String, dynamic>?;

      // Extract polyline points for route display
      final overviewPolyline = route['overview_polyline'] as Map<String, dynamic>;
      final points = overviewPolyline['points'] as String;

      final result = DirectionsResult(
        distanceMeters: distance['value'] as int,
        distanceText: distance['text'] as String,
        durationSeconds: duration['value'] as int,
        durationText: duration['text'] as String,
        durationInTrafficSeconds: durationInTraffic?['value'] as int?,
        durationInTrafficText: durationInTraffic?['text'] as String?,
        polylinePoints: points,
        startAddress: leg['start_address'] as String,
        endAddress: leg['end_address'] as String,
      );

      developer.log(
        '✅ Route found: ${result.distanceText}, ETA: ${result.durationText}',
        name: 'DirectionsService',
      );

      return result;
    } catch (e, stackTrace) {
      developer.log(
        '❌ Error fetching directions: $e',
        name: 'DirectionsService',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// Decode polyline string to list of LatLng points
  static List<LatLng> decodePolyline(String encoded) {
    List<LatLng> points = [];
    int index = 0;
    int len = encoded.length;
    int lat = 0;
    int lng = 0;

    while (index < len) {
      int b;
      int shift = 0;
      int result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }

    return points;
  }
}

/// Result from Directions API
class DirectionsResult {
  final int distanceMeters;
  final String distanceText;
  final int durationSeconds;
  final String durationText;
  final int? durationInTrafficSeconds;
  final String? durationInTrafficText;
  final String polylinePoints;
  final String startAddress;
  final String endAddress;

  DirectionsResult({
    required this.distanceMeters,
    required this.distanceText,
    required this.durationSeconds,
    required this.durationText,
    this.durationInTrafficSeconds,
    this.durationInTrafficText,
    required this.polylinePoints,
    required this.startAddress,
    required this.endAddress,
  });

  /// Get distance in kilometers
  double get distanceKm => distanceMeters / 1000.0;

  /// Get duration in minutes
  int get durationMinutes => (durationSeconds / 60).round();

  /// Get duration with traffic in minutes (if available)
  int? get durationInTrafficMinutes =>
      durationInTrafficSeconds != null ? (durationInTrafficSeconds! / 60).round() : null;

  /// Get best ETA (with traffic if available, otherwise without)
  int get bestETAMinutes => durationInTrafficMinutes ?? durationMinutes;

  String get bestETAText => durationInTrafficText ?? durationText;
}

