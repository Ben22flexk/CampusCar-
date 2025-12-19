import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'dart:developer' as developer;

/// Service for OpenStreetMap location search and geocoding
class LocationService {
  // Nominatim API (OpenStreetMap geocoding service)
  static const String _nominatimBaseUrl = 'https://nominatim.openstreetmap.org';
  
  /// Search for locations using Nominatim
  /// Returns list of search results with coordinates
  Future<List<LocationSearchResult>> searchLocations(String query) async {
    if (query.trim().isEmpty) return [];
    
    try {
      final url = Uri.parse('$_nominatimBaseUrl/search').replace(
        queryParameters: {
          'q': query,
          'format': 'json',
          'addressdetails': '1',
          'limit': '10',
          'countrycodes': 'my', // Malaysia only
        },
      );

      developer.log('Searching locations: $query', name: 'LocationService');

      final response = await http.get(
        url,
        headers: {
          'User-Agent': 'CampusCar/1.0', // Required by Nominatim
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        
        final results = data.map((item) {
          return LocationSearchResult(
            displayName: item['display_name'] as String,
            latitude: double.parse(item['lat'] as String),
            longitude: double.parse(item['lon'] as String),
            address: _parseAddress(item['address']),
            placeType: item['type'] as String?,
          );
        }).toList();

        developer.log('Found ${results.length} results', name: 'LocationService');
        return results;
      } else {
        developer.log(
          'Location search failed: ${response.statusCode}',
          name: 'LocationService',
          error: response.body,
        );
        throw Exception('Failed to search locations: ${response.statusCode}');
      }
    } catch (e) {
      developer.log('Error searching locations: $e', name: 'LocationService', error: e);
      rethrow;
    }
  }

  /// Reverse geocode: Get address from coordinates
  Future<String> getAddressFromCoordinates(double latitude, double longitude) async {
    try {
      final url = Uri.parse('$_nominatimBaseUrl/reverse').replace(
        queryParameters: {
          'lat': latitude.toString(),
          'lon': longitude.toString(),
          'format': 'json',
          'addressdetails': '1',
        },
      );

      developer.log(
        'Reverse geocoding: ($latitude, $longitude)',
        name: 'LocationService',
      );

      final response = await http.get(
        url,
        headers: {
          'User-Agent': 'CampusCar/1.0',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final address = data['display_name'] as String;
        developer.log('Found address: $address', name: 'LocationService');
        return address;
      } else {
        throw Exception('Failed to get address: ${response.statusCode}');
      }
    } catch (e) {
      developer.log('Error reverse geocoding: $e', name: 'LocationService', error: e);
      return 'Unknown location';
    }
  }

  /// Parse address components from Nominatim response
  LocationAddress _parseAddress(Map<String, dynamic>? addressData) {
    if (addressData == null) {
      return const LocationAddress(
        road: null,
        suburb: null,
        city: null,
        state: null,
        postcode: null,
        country: null,
      );
    }

    return LocationAddress(
      road: addressData['road'] as String?,
      suburb: addressData['suburb'] as String?,
      city: addressData['city'] as String? ?? addressData['town'] as String?,
      state: addressData['state'] as String?,
      postcode: addressData['postcode'] as String?,
      country: addressData['country'] as String?,
    );
  }

  /// Get popular/suggested locations for Malaysia
  List<LocationSuggestion> getPopularLocations() {
    return [
      // TARC Campuses
      const LocationSuggestion(
        name: 'TARC KL Main Campus',
        address: 'Jalan Genting Kelang, Setapak, Kuala Lumpur',
        latitude: 3.2175,
        longitude: 101.7258,
        category: 'Campus',
      ),
      const LocationSuggestion(
        name: 'TARC PJ Campus',
        address: 'Jalan PJU 10/1, Damansara Damai, Petaling Jaya',
        latitude: 3.1957,
        longitude: 101.5754,
        category: 'Campus',
      ),
      
      // Shopping Malls
      const LocationSuggestion(
        name: 'KLCC',
        address: 'Kuala Lumpur City Centre',
        latitude: 3.1579,
        longitude: 101.7120,
        category: 'Shopping',
      ),
      const LocationSuggestion(
        name: 'Pavilion KL',
        address: 'Bukit Bintang, Kuala Lumpur',
        latitude: 3.1491,
        longitude: 101.7134,
        category: 'Shopping',
      ),
      const LocationSuggestion(
        name: 'Mid Valley Megamall',
        address: 'Mid Valley City, Kuala Lumpur',
        latitude: 3.1172,
        longitude: 101.6778,
        category: 'Shopping',
      ),
      const LocationSuggestion(
        name: 'Sunway Pyramid',
        address: 'Bandar Sunway, Petaling Jaya',
        latitude: 3.0728,
        longitude: 101.6072,
        category: 'Shopping',
      ),
      
      // Transit Hubs
      const LocationSuggestion(
        name: 'Wangsa Maju LRT Station',
        address: 'Wangsa Maju, Kuala Lumpur',
        latitude: 3.2050,
        longitude: 101.7312,
        category: 'Transit',
      ),
      const LocationSuggestion(
        name: 'KL Sentral',
        address: 'Brickfields, Kuala Lumpur',
        latitude: 3.1345,
        longitude: 101.6867,
        category: 'Transit',
      ),
      
      // Tourist Spots
      const LocationSuggestion(
        name: 'Batu Caves',
        address: 'Gombak, Selangor',
        latitude: 3.2379,
        longitude: 101.6841,
        category: 'Tourist',
      ),
    ];
  }
}

/// Location search result from Nominatim
class LocationSearchResult {
  final String displayName;
  final double latitude;
  final double longitude;
  final LocationAddress address;
  final String? placeType;

  const LocationSearchResult({
    required this.displayName,
    required this.latitude,
    required this.longitude,
    required this.address,
    this.placeType,
  });

  LatLng get latLng => LatLng(latitude, longitude);
  
  String get shortName {
    if (address.road != null) return address.road!;
    if (address.suburb != null) return address.suburb!;
    if (address.city != null) return address.city!;
    return displayName.split(',').first;
  }
}

/// Parsed address components
class LocationAddress {
  final String? road;
  final String? suburb;
  final String? city;
  final String? state;
  final String? postcode;
  final String? country;

  const LocationAddress({
    this.road,
    this.suburb,
    this.city,
    this.state,
    this.postcode,
    this.country,
  });
}

/// Suggested/popular location
class LocationSuggestion {
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final String category;

  const LocationSuggestion({
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.category,
  });

  LatLng get latLng => LatLng(latitude, longitude);
}

