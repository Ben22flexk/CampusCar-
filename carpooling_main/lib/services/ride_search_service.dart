import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:latlong2/latlong.dart';
import 'package:carpooling_main/core/utils/timezone_helper.dart';
import 'dart:developer' as developer;

class RideSearchResult {
  final String id;
  final String driverId;
  final String driverName;
  final String? driverPhotoUrl;
  final String pickupLocation;
  final String destination;
  final double pickupLatitude;
  final double pickupLongitude;
  final double destinationLatitude;
  final double destinationLongitude;
  final DateTime scheduledTime;
  final int availableSeats;
  final double farePerSeat;
  final double? calculatedDistanceKm;
  final int? calculatedDurationMinutes;
  final String vehicleModel;
  final String vehicleColor;
  final String vehiclePlateNumber;

  RideSearchResult({
    required this.id,
    required this.driverId,
    required this.driverName,
    this.driverPhotoUrl,
    required this.pickupLocation,
    required this.destination,
    required this.pickupLatitude,
    required this.pickupLongitude,
    required this.destinationLatitude,
    required this.destinationLongitude,
    required this.scheduledTime,
    required this.availableSeats,
    required this.farePerSeat,
    this.calculatedDistanceKm,
    this.calculatedDurationMinutes,
    required this.vehicleModel,
    required this.vehicleColor,
    required this.vehiclePlateNumber,
  });

  factory RideSearchResult.fromJson(Map<String, dynamic> json) {
    final driverProfile = json['driver_profile'] ?? {};
    final driverVerification = json['driver_verification'] ?? {};

    return RideSearchResult(
      id: json['id'] ?? '',
      driverId: json['driver_id'] ?? '',
      driverName: driverProfile['display_name'] ?? 'Unknown Driver',
      driverPhotoUrl: driverProfile['avatar_url'],
      pickupLocation: json['pickup_location'] ?? '',
      destination: json['destination'] ?? '',
      pickupLatitude: (json['pickup_latitude'] as num?)?.toDouble() ?? 0.0,
      pickupLongitude: (json['pickup_longitude'] as num?)?.toDouble() ?? 0.0,
      destinationLatitude: (json['destination_latitude'] as num?)?.toDouble() ?? 0.0,
      destinationLongitude: (json['destination_longitude'] as num?)?.toDouble() ?? 0.0,
      scheduledTime: TimezoneHelper.utcToMalaysia(DateTime.parse(json['scheduled_time']).toUtc()),
      availableSeats: json['available_seats'] ?? 0,
      farePerSeat: (json['final_fare_per_seat'] as num?)?.toDouble() ?? 0.0,
      calculatedDistanceKm: (json['calculated_distance_km'] as num?)?.toDouble(),
      calculatedDurationMinutes: json['calculated_duration_minutes'] as int?,
      vehicleModel: driverVerification['vehicle_model'] ?? 'Unknown',
      vehicleColor: driverVerification['vehicle_color'] ?? 'Unknown',
      vehiclePlateNumber: driverVerification['vehicle_plate_number'] ?? 'N/A',
    );
  }

  // Calculate distance from passenger location to pickup point
  double distanceToPickupKm(double passengerLat, double passengerLng) {
    const distance = Distance();
    return distance.as(
      LengthUnit.Kilometer,
      LatLng(passengerLat, passengerLng),
      LatLng(pickupLatitude, pickupLongitude),
    );
  }

  // Calculate match quality based on proximity
  String getMatchType(double distanceKm) {
    if (distanceKm < 1.0) return 'Best Match';
    if (distanceKm < 3.0) return 'Nearby';
    return 'Further Away';
  }
}

class RideSearchService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Search for available rides based on pickup and destination
  Future<List<RideSearchResult>> searchRides({
    required LatLng pickupLocation,
    required LatLng destinationLocation,
    required int seatsRequired,
    double maxDistanceKm = 10.0, // Maximum distance for matching
  }) async {
    try {
      developer.log('🔍 Searching for rides...', name: 'RideSearchService');
      developer.log('Pickup: (${pickupLocation.latitude}, ${pickupLocation.longitude})', name: 'RideSearchService');
      developer.log('Destination: (${destinationLocation.latitude}, ${destinationLocation.longitude})', name: 'RideSearchService');

      // Query rides with driver profile and vehicle info
      final response = await _supabase
          .from('rides')
          .select('''
            *,
            driver_profile:profiles!rides_driver_id_fkey(
              display_name,
              avatar_url
            ),
            driver_verification:driver_verifications!driver_verifications_user_id_fkey(
              vehicle_model,
              vehicle_color,
              vehicle_plate_number
            )
          ''')
          .eq('ride_status', 'active')
          .gte('available_seats', seatsRequired)
          .gte('scheduled_time', TimezoneHelper.malaysiaToUtc(TimezoneHelper.nowInMalaysia()).toIso8601String())
          .order('scheduled_time', ascending: true);

      developer.log('✅ Found ${response.length} rides', name: 'RideSearchService');

      if (response.isEmpty) {
        return [];
      }

      // Parse and filter rides by distance
      final rides = (response as List)
          .map((json) => RideSearchResult.fromJson(json))
          .where((ride) {
            // Filter by proximity to pickup location
            final pickupDistance = ride.distanceToPickupKm(
              pickupLocation.latitude,
              pickupLocation.longitude,
            );

            // Filter by proximity to destination
            final destDistance = const Distance().as(
              LengthUnit.Kilometer,
              LatLng(destinationLocation.latitude, destinationLocation.longitude),
              LatLng(ride.destinationLatitude, ride.destinationLongitude),
            );

            developer.log(
              'Ride ${ride.id}: Pickup distance = ${pickupDistance.toStringAsFixed(2)} km, Dest distance = ${destDistance.toStringAsFixed(2)} km',
              name: 'RideSearchService',
            );

            // Accept rides within max distance for both pickup and destination
            return pickupDistance <= maxDistanceKm && destDistance <= maxDistanceKm;
          })
          .toList();

      // Sort by pickup distance (closest first)
      rides.sort((a, b) {
        final distA = a.distanceToPickupKm(pickupLocation.latitude, pickupLocation.longitude);
        final distB = b.distanceToPickupKm(pickupLocation.latitude, pickupLocation.longitude);
        return distA.compareTo(distB);
      });

      developer.log('✅ Filtered to ${rides.length} matching rides', name: 'RideSearchService');

      return rides;
    } catch (e, stackTrace) {
      developer.log('❌ Error searching rides: $e', name: 'RideSearchService', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Subscribe to real-time ride updates
  RealtimeChannel subscribeToRideUpdates(Function(List<RideSearchResult>) onRidesUpdated) {
    developer.log('📡 Subscribing to real-time ride updates', name: 'RideSearchService');

    return _supabase
        .channel('rides_channel')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'rides',
          callback: (payload) async {
            developer.log('🔔 Real-time ride update: ${payload.eventType}', name: 'RideSearchService');
            // Re-fetch rides when changes occur
            // Note: You'll need to call searchRides again with the same parameters
            // This is a simplified version - you can enhance it with caching
          },
        )
        .subscribe();
  }
}

