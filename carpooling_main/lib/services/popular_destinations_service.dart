import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Popular Destination Model
class PopularDestination {
  final String name;
  final String shortName;
  final String address;
  final LatLng coordinates;
  final int rideCount;
  final String category;
  final String icon;

  const PopularDestination({
    required this.name,
    required this.shortName,
    required this.address,
    required this.coordinates,
    required this.rideCount,
    required this.category,
    required this.icon,
  });
}

/// Service to get popular destinations and route recommendations
class PopularDestinationsService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Get top 10 popular destinations from database (real-time)
  Future<List<PopularDestination>> getTopDestinations({int limit = 10}) async {
    try {
      // Query rides table to find most common destinations
      final response = await _supabase
          .from('rides')
          .select('to_location, to_lat, to_lng')
          .not('to_lat', 'is', null)
          .not('to_lng', 'is', null)
          .order('created_at', ascending: false)
          .limit(100); // Get recent 100 rides

      final rides = response as List;

      // Count occurrences of each destination
      final Map<String, Map<String, dynamic>> destinationCounts = {};

      for (final ride in rides) {
        final location = ride['to_location'] as String;
        final lat = ride['to_lat'] as double;
        final lng = ride['to_lng'] as double;

        final key = '$lat,$lng';
        if (destinationCounts.containsKey(key)) {
          destinationCounts[key]!['count'] = (destinationCounts[key]!['count'] as int) + 1;
        } else {
          destinationCounts[key] = {
            'location': location,
            'lat': lat,
            'lng': lng,
            'count': 1,
          };
        }
      }

      // Sort by count and convert to PopularDestination objects
      final sortedDestinations = destinationCounts.entries.toList()
        ..sort((a, b) => (b.value['count'] as int).compareTo(a.value['count'] as int));

      final popularDestinations = <PopularDestination>[];
      for (var i = 0; i < sortedDestinations.length && i < limit; i++) {
        final entry = sortedDestinations[i].value;
        final location = entry['location'] as String;
        final shortName = _extractShortName(location);
        
        popularDestinations.add(PopularDestination(
          name: location,
          shortName: shortName,
          address: location,
          coordinates: LatLng(entry['lat'] as double, entry['lng'] as double),
          rideCount: entry['count'] as int,
          category: _categorizeDestination(location),
          icon: _getIconForCategory(_categorizeDestination(location)),
        ));
      }

      // If no data from database, return default popular locations
      if (popularDestinations.isEmpty) {
        return _getDefaultPopularLocations();
      }

      return popularDestinations;
    } catch (e) {
      print('Error fetching popular destinations: $e');
      // Return default popular locations on error
      return _getDefaultPopularLocations();
    }
  }

  /// Get default popular TARC and KL locations
  List<PopularDestination> _getDefaultPopularLocations() {
    return [
      PopularDestination(
        name: 'TARC KL Main Campus',
        shortName: 'TARC KL',
        address: 'Jalan Genting Kelang, Setapak, Kuala Lumpur',
        coordinates: LatLng(3.2167, 101.7333),
        rideCount: 0,
        category: 'Campus',
        icon: '🎓',
      ),
      PopularDestination(
        name: 'TARC PJ Campus',
        shortName: 'TARC PJ',
        address: 'Jalan PJU 10/1, Damansara Damai, Petaling Jaya',
        coordinates: LatLng(3.1952, 101.5931),
        rideCount: 0,
        category: 'Campus',
        icon: '🎓',
      ),
      PopularDestination(
        name: 'KLCC',
        shortName: 'KLCC',
        address: 'Kuala Lumpur City Centre, Kuala Lumpur',
        coordinates: LatLng(3.1478, 101.6953),
        rideCount: 0,
        category: 'Shopping',
        icon: '🏢',
      ),
      PopularDestination(
        name: 'Pavilion KL',
        shortName: 'Pavilion',
        address: '168 Jalan Bukit Bintang, Kuala Lumpur',
        coordinates: LatLng(3.1494, 101.7143),
        rideCount: 0,
        category: 'Shopping',
        icon: '🛍️',
      ),
      PopularDestination(
        name: 'Mid Valley Megamall',
        shortName: 'Mid Valley',
        address: 'Mid Valley City, Kuala Lumpur',
        coordinates: LatLng(3.1184, 101.6768),
        rideCount: 0,
        category: 'Shopping',
        icon: '🛍️',
      ),
      PopularDestination(
        name: 'Sunway Pyramid',
        shortName: 'Sunway',
        address: 'Bandar Sunway, Petaling Jaya',
        coordinates: LatLng(3.0734, 101.6075),
        rideCount: 0,
        category: 'Shopping',
        icon: '🎡',
      ),
      PopularDestination(
        name: 'Batu Caves',
        shortName: 'Batu Caves',
        address: 'Gombak, Selangor',
        coordinates: LatLng(3.2372, 101.6840),
        rideCount: 0,
        category: 'Tourist',
        icon: '⛰️',
      ),
      PopularDestination(
        name: 'KL Sentral',
        shortName: 'KL Sentral',
        address: 'KL Sentral Station, Kuala Lumpur',
        coordinates: LatLng(3.1337, 101.6856),
        rideCount: 0,
        category: 'Transport',
        icon: '🚆',
      ),
      PopularDestination(
        name: 'Bukit Jalil',
        shortName: 'Bukit Jalil',
        address: 'Bukit Jalil, Kuala Lumpur',
        coordinates: LatLng(3.0577, 101.6993),
        rideCount: 0,
        category: 'Sport',
        icon: '🏟️',
      ),
      PopularDestination(
        name: 'KLIA',
        shortName: 'Airport',
        address: 'Kuala Lumpur International Airport',
        coordinates: LatLng(2.7456, 101.7072),
        rideCount: 0,
        category: 'Transport',
        icon: '✈️',
      ),
    ];
  }

  /// Extract short name from full address
  String _extractShortName(String fullAddress) {
    // Split by comma and take first part
    final parts = fullAddress.split(',');
    if (parts.isNotEmpty) {
      return parts[0].trim();
    }
    return fullAddress;
  }

  /// Categorize destination based on name/address
  String _categorizeDestination(String location) {
    final lower = location.toLowerCase();
    
    if (lower.contains('tarc') || lower.contains('university') || lower.contains('college')) {
      return 'Campus';
    } else if (lower.contains('mall') || lower.contains('shopping') || lower.contains('pavilion')) {
      return 'Shopping';
    } else if (lower.contains('station') || lower.contains('airport') || lower.contains('terminal')) {
      return 'Transport';
    } else if (lower.contains('stadium') || lower.contains('sport')) {
      return 'Sport';
    } else if (lower.contains('cave') || lower.contains('park') || lower.contains('museum')) {
      return 'Tourist';
    } else {
      return 'Popular';
    }
  }

  /// Get icon for category
  String _getIconForCategory(String category) {
    switch (category) {
      case 'Campus':
        return '🎓';
      case 'Shopping':
        return '🛍️';
      case 'Transport':
        return '🚆';
      case 'Sport':
        return '🏟️';
      case 'Tourist':
        return '⛰️';
      default:
        return '📍';
    }
  }
}

