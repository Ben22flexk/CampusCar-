import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'dart:developer' as developer;

/// Service for calculating real-time distance and duration between locations
/// Supports both Google Distance Matrix API and Mapbox Directions API
class DistanceService {
  // API Configuration
  // IMPORTANT: Make sure this API key has Directions API enabled in Google Cloud Console
  static const String _googleApiKey = 'AIzaSyCq-OE3mBpewP0435n0w5jrnzFXUGF-aYY';
  static const String? _mapboxApiKey = null; // Optional: Mapbox fallback
  
  static const String _googleDirectionsUrl = 'https://maps.googleapis.com/maps/api/directions/json';
  static const String _mapboxBaseUrl = 'https://api.mapbox.com/directions/v5/mapbox/driving';
  
  // For testing purposes
  static bool _loggedApiKeyWarning = false;
  
  /// Calculate distance and duration between two points
  /// Tries Google first, falls back to Mapbox, then Haversine formula
  Future<DistanceCalculationResult> calculateDistance({
    required LatLng origin,
    required LatLng destination,
  }) async {
    try {
      // Try Google Directions API first (more accurate, provides route polyline)
      if (_googleApiKey.isNotEmpty ?? false) {
        developer.log('Trying Google Directions API', name: 'DistanceService');
        final result = await _calculateWithGoogle(origin, destination);
        if (result != null) return result;
      }
      
      // Fall back to Mapbox Directions API
      if (_mapboxApiKey?.isNotEmpty ?? false) {
        developer.log('Trying Mapbox Directions API', name: 'DistanceService');
        final result = await _calculateWithMapbox(origin, destination);
        if (result != null) return result;
      }
      
      // Final fallback: Haversine formula (straight-line distance)
      developer.log('Using Haversine formula (no API key)', name: 'DistanceService');
      return _calculateWithHaversine(origin, destination);
      
    } catch (e) {
      developer.log('Error calculating distance: $e', name: 'DistanceService', error: e);
      // Return Haversine as ultimate fallback
      return _calculateWithHaversine(origin, destination);
    }
  }
  
  /// Calculate using Google Directions API (provides polyline for curved routes)
  Future<DistanceCalculationResult?> _calculateWithGoogle(
    LatLng origin,
    LatLng destination,
  ) async {
    if (_googleApiKey.isEmpty) {
      if (!_loggedApiKeyWarning) {
        developer.log(
          '⚠️ Google API key not configured. Add your key in distance_service.dart',
          name: 'DistanceService',
        );
        _loggedApiKeyWarning = true;
      }
      return null;
    }
    
    try {
      final url = Uri.parse(_googleDirectionsUrl).replace(
        queryParameters: {
          'origin': '${origin.latitude},${origin.longitude}',
          'destination': '${destination.latitude},${destination.longitude}',
          'mode': 'driving',
          'key': _googleApiKey,
        },
      );

      developer.log('🌐 Calling Google Directions API...', name: 'DistanceService');
      final response = await http.get(url).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          developer.log('⏱️ Google API timeout after 10 seconds', name: 'DistanceService');
          throw TimeoutException('Google API request timed out');
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final status = data['status'] as String;
        
        developer.log('📡 Google API Response Status: $status', name: 'DistanceService');
        
        if (status == 'OK' && data['routes'] != null && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final leg = route['legs'][0];
          
          final distanceMeters = leg['distance']['value'] as int;
          final durationSeconds = leg['duration']['value'] as int;
          final polyline = route['overview_polyline']['points'] as String?;
          
          developer.log(
            '✅ Route received: ${distanceMeters / 1000}km, ${(durationSeconds / 60).round()}min, Polyline: ${polyline != null ? "Yes (${polyline.length} chars)" : "No"}',
            name: 'DistanceService'
          );
          
          if (polyline == null) {
            developer.log('⚠️ No polyline in response - API might be misconfigured', name: 'DistanceService');
          }
          
          return DistanceCalculationResult(
            distanceKm: distanceMeters / 1000.0,
            durationMinutes: (durationSeconds / 60.0).round(),
            method: 'google_directions',
            routePolyline: polyline,
          );
        } else {
          // Log detailed error information
          final errorMessage = data['error_message'] as String?;
          developer.log(
            '❌ Google API Error:\n'
            '  Status: $status\n'
            '  Message: ${errorMessage ?? "No error message"}\n'
            '  Full response: ${response.body.substring(0, response.body.length > 300 ? 300 : response.body.length)}',
            name: 'DistanceService',
            error: 'API_ERROR'
          );
          
          // Provide specific guidance based on error type
          switch (status) {
            case 'REQUEST_DENIED':
              developer.log(
                '🔑 ACTION REQUIRED: Enable Directions API in Google Cloud Console\n'
                '   1. Go to https://console.cloud.google.com/apis/library/directions-backend.googleapis.com\n'
                '   2. Click "Enable"\n'
                '   3. Make sure your API key has no restrictions blocking this request',
                name: 'DistanceService'
              );
              break;
            case 'OVER_QUERY_LIMIT':
              developer.log('💰 API quota exceeded. Check your billing in Google Cloud Console', name: 'DistanceService');
              break;
            case 'INVALID_REQUEST':
              developer.log('⚠️ Invalid request parameters. Check lat/lng values', name: 'DistanceService');
              break;
          }
        }
      } else {
        developer.log(
          '❌ HTTP Error ${response.statusCode}: ${response.body}',
          name: 'DistanceService',
          error: 'HTTP_ERROR'
        );
      }
      
      return null;
    } on TimeoutException catch (e) {
      developer.log('⏱️ Timeout: $e', name: 'DistanceService', error: e);
      return null;
    } catch (e) {
      developer.log('❌ Exception: $e', name: 'DistanceService', error: e);
      return null;
    }
  }
  
  /// Calculate using Mapbox Directions API
  Future<DistanceCalculationResult?> _calculateWithMapbox(
    LatLng origin,
    LatLng destination,
  ) async {
    if (_mapboxApiKey == null) return null;
    
    try {
      final coordinates = '${origin.longitude},${origin.latitude};'
                         '${destination.longitude},${destination.latitude}';
      
      final url = Uri.parse('$_mapboxBaseUrl/$coordinates').replace(
        queryParameters: {
          'access_token': _mapboxApiKey,
          'geometries': 'polyline',
          'overview': 'full',
        },
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['code'] == 'Ok' && data['routes'] != null && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final distanceMeters = route['distance'] as num;
          final durationSeconds = route['duration'] as num;
          final polyline = route['geometry'] as String?;
          
          return DistanceCalculationResult(
            distanceKm: distanceMeters / 1000.0,
            durationMinutes: (durationSeconds / 60.0).round(),
            method: 'mapbox_directions',
            routePolyline: polyline,
          );
        }
      }
      
      return null;
    } catch (e) {
      developer.log('Mapbox API error: $e', name: 'DistanceService');
      return null;
    }
  }
  
  /// Calculate using Haversine formula (straight-line distance)
  /// This is a fallback when APIs are unavailable
  DistanceCalculationResult _calculateWithHaversine(
    LatLng origin,
    LatLng destination,
  ) {
    const Distance distance = Distance();
    final distanceMeters = distance.as(
      LengthUnit.Meter,
      origin,
      destination,
    );
    
    final distanceKm = distanceMeters / 1000.0;
    
    // Estimate duration: assume 40 km/h average speed in city
    final durationMinutes = ((distanceKm / 40.0) * 60).round();
    
    // Add 30% to account for roads not being straight lines
    final adjustedDistanceKm = distanceKm * 1.3;
    final adjustedDuration = (durationMinutes * 1.3).round();
    
    developer.log(
      'Haversine: ${adjustedDistanceKm.toStringAsFixed(2)} km, $adjustedDuration min',
      name: 'DistanceService',
    );
    
    return DistanceCalculationResult(
      distanceKm: adjustedDistanceKm,
      durationMinutes: adjustedDuration,
      method: 'haversine_formula',
      routePolyline: null,
    );
  }
}

/// Result of distance calculation
class DistanceCalculationResult {
  final double distanceKm;
  final int durationMinutes;
  final String method; // 'google_distance_matrix', 'mapbox_directions', or 'haversine_formula'
  final String? routePolyline; // Encoded polyline for map display
  
  const DistanceCalculationResult({
    required this.distanceKm,
    required this.durationMinutes,
    required this.method,
    this.routePolyline,
  });
  
  String get distanceDisplay => '${distanceKm.toStringAsFixed(1)} km';
  String get durationDisplay => '$durationMinutes min';
  
  bool get isEstimated => method == 'haversine_formula';
  
  String get methodDisplay {
    switch (method) {
      case 'google_directions':
      case 'google_distance_matrix':
        return 'Google Maps';
      case 'mapbox_directions':
        return 'Mapbox';
      case 'haversine_formula':
        return 'Estimated';
      default:
        return method;
    }
  }
  
  /// Decode polyline to list of LatLng points (Google encoded polyline format)
  List<LatLng>? decodePolyline() {
    if (routePolyline == null || routePolyline!.isEmpty) {
      developer.log('No polyline to decode', name: 'DistanceService');
      return null;
    }
    
    try {
      final points = _decodePolyline(routePolyline!);
      developer.log('Decoded polyline: ${points.length} points', name: 'DistanceService');
      return points;
    } catch (e) {
      developer.log('Error decoding polyline: $e', name: 'DistanceService', error: e);
      return null;
    }
  }
  
  /// Internal polyline decoder for Google's encoded polyline algorithm
  static List<LatLng> _decodePolyline(String encoded) {
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

      points.add(LatLng(lat / 1E5, lng / 1E5));
    }

    return points;
  }
}

