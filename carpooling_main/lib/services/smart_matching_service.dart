import 'dart:math';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:carpooling_main/core/utils/timezone_helper.dart';
import 'package:carpooling_main/services/fare_calculation_service.dart';
import 'package:carpooling_main/services/gender_matching_service.dart';

/// Smart Matching Hybrid AI for Driver/Passenger Pairing
/// Implements weighted scoring based on:
/// - Route similarity (pickup/drop proximity and destination similarity)
/// - Price (lowest fare for passenger)
/// - Reputation (highest driver ratings)
/// - Gender preferences (safer matching)
class SmartMatchingService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final GenderMatchingService _genderMatchingService = GenderMatchingService();

  // Adjustable weights for hybrid scoring (w1, w2, w3)
  // These can be tuned based on user preferences or A/B testing
  double weightRoute = 0.4; // w1 - Route similarity (40%)
  double weightPrice = 0.3; // w2 - Price score (30%)
  double weightReputation = 0.3; // w3 - Reputation score (30%)

  /// Main Smart Matching Function
  /// Returns top-N driver rides ranked by hybrid score
  Future<List<SmartMatch>> findBestMatches({
    required LatLng passengerPickup,
    required LatLng passengerDestination,
    required int seatsRequired,
    required double maxWillingnessToPay,
    double minRatingThreshold = 0.0,
    int topN = 5,
    double maxDistanceKm = 20.0, // Increased from 15km to 20km for carpooling
  }) async {
    try {
      print('🔍 Smart Matching - Starting search...');
      print('   Passenger pickup: ${passengerPickup.latitude}, ${passengerPickup.longitude}');
      print('   Passenger destination: ${passengerDestination.latitude}, ${passengerDestination.longitude}');
      print('   Seats required: $seatsRequired');
      print('   Max price: RM$maxWillingnessToPay');
      print('   Max distance: ${maxDistanceKm}km');
      
      // DEBUG: Check what DateTime we're sending
      final now = TimezoneHelper.nowInMalaysia();
      final nowUtc = TimezoneHelper.malaysiaToUtc(now);
      print('⏰ Malaysia time: ${now.toIso8601String()}');
      print('⏰ UTC time: ${nowUtc.toIso8601String()}');
      
      // 1. Fetch all available rides (active, in_progress, and scheduled rides)
      // Use UTC time for database comparison
      // We'll filter scheduled rides in code based on activation status
      final response = await _supabase
          .from('rides')
          .select('''
            id,
            driver_id,
            from_location,
            to_location,
            from_lat,
            from_lng,
            to_lat,
            to_lng,
            scheduled_time,
            available_seats,
            price_per_seat,
            ride_status,
            ride_type,
            is_activated,
            created_at
          ''')
          .or('ride_status.eq.active,ride_status.eq.in_progress,ride_status.eq.scheduled') // All available ride types
          .gte('available_seats', seatsRequired)
          .order('created_at', ascending: false);

      print('📊 Query response type: ${response.runtimeType}');
      print('📊 Total rides fetched: ${response.length}');
      
      final rides = response as List;
      
      print('✅ Rides fetched: ${rides.length}');
      
      if (rides.isEmpty) {
        print('❌ No rides found matching initial criteria');
        print('   - Check if there are any active rides in the database');
        print('   - Verify rides have scheduled_time >= now');
        print('   - Verify rides have available_seats >= $seatsRequired');
        return [];
      }

      // Log first ride for debugging
      if (rides.isNotEmpty) {
        print('📋 First ride data: ${rides[0]}');
      }

      // 2. Filter and score rides
      final List<Map<String, dynamic>> scoredRides = [];
      
      for (int i = 0; i < rides.length; i++) {
        final ride = rides[i];
        print('\n🚗 Processing ride ${i + 1}/${rides.length}: ${ride['id']}');
        print('   Status: ${ride['ride_status']}');
        print('   Type: ${ride['ride_type']}');
        print('   Scheduled: ${ride['scheduled_time']}');
        print('   From: ${ride['from_location']} (${ride['from_lat']}, ${ride['from_lng']})');
        print('   To: ${ride['to_location']} (${ride['to_lat']}, ${ride['to_lng']})');
        
        // Check ride availability based on status and type
        final rideStatus = ride['ride_status'] as String?;
        final isActivated = ride['is_activated'] as bool? ?? false;
        final scheduledTime = ride['scheduled_time'] != null 
            ? TimezoneHelper.utcToMalaysia(DateTime.parse(ride['scheduled_time'] as String).toUtc())
            : null;
        
        // Filter logic for different ride types:
        // 1. Active rides (immediate) - always show
        // 2. In-progress rides - always show
        // 3. Scheduled rides - always show if they have a future scheduled time
        if (rideStatus == 'scheduled') {
          if (scheduledTime == null) {
            print('   ⚠️ Skipped - Missing scheduled time');
            continue;
          }

          if (scheduledTime.isBefore(nowUtc)) {
            print('   ⚠️ Skipped - Scheduled time already passed');
            continue;
          }

          print('   ✅ Scheduled ride is available to passengers (pre-booking enabled)');
          print('      Is activated: $isActivated');
          print('      Scheduled time: ${scheduledTime.toLocal()}');
        }
        
        // Skip if coordinates missing
        if (ride['from_lat'] == null || ride['from_lng'] == null ||
            ride['to_lat'] == null || ride['to_lng'] == null) {
          print('   ⚠️ Skipped - Missing coordinates');
          continue;
        }

        final driverPickup = LatLng(
          ride['from_lat'] as double,
          ride['from_lng'] as double,
        );
        final driverDestination = LatLng(
          ride['to_lat'] as double,
          ride['to_lng'] as double,
        );

        // Check if within acceptable distance range (pre-filter)
        final pickupDistance = _calculateDistance(passengerPickup, driverPickup);
        final destDistance = _calculateDistance(passengerDestination, driverDestination);
        
        print('   📏 Pickup distance: ${pickupDistance.toStringAsFixed(2)}km');
        print('   📏 Destination distance: ${destDistance.toStringAsFixed(2)}km');
        
        // CONSTRAINT: Pickup must be within 3km of driver's route start
        if (pickupDistance > 3.0) {
          print('   ❌ Skipped - Pickup too far (max 3km from route)');
          continue;
        }
        
        // CONSTRAINT: Destination must be on route or very close (max 500m)
        if (destDistance > 0.5) {
          print('   ❌ Skipped - Destination not on route (max 0.5km from driver destination)');
          continue;
        }
        
        if (pickupDistance > maxDistanceKm || destDistance > maxDistanceKm) {
          print('   ❌ Skipped - Too far (max ${maxDistanceKm}km)');
          continue; // Skip rides too far away
        }

        // Calculate fare dynamically based on passenger's actual travel distance
        final fareService = FareCalculationService();
        final passengerTravelDistance = _calculateDistance(passengerPickup, passengerDestination);
        final calculatedFare = fareService.calculateStudentFare(
          distanceInKm: passengerTravelDistance,
          tripDateTime: DateTime.parse(ride['scheduled_time'] as String),
        );
        final fare = calculatedFare;
        
        print('   💰 Fare (calculated): RM${fare.toStringAsFixed(2)} for ${passengerTravelDistance.toStringAsFixed(2)}km');
        
        // Skip if price exceeds willingness to pay
        if (fare > maxWillingnessToPay) {
          print('   ❌ Skipped - Too expensive (max RM$maxWillingnessToPay)');
          continue;
        }

        // Get driver info (name and rating)
        final driverId = ride['driver_id'] as String;
        final driverInfo = await _getDriverInfo(driverId);
        final driverRating = driverInfo['rating'] as double;
        final driverName = driverInfo['name'] as String;
        
        // Fetch vehicle info separately
        String? vehicleModel;
        String? vehicleColor;
        String? vehiclePlateNumber;
        
        try {
          final vehicleResponse = await _supabase
              .from('driver_verifications')
              .select('vehicle_model, vehicle_color, vehicle_plate_number, vehicle_year, vehicle_seats')
              .eq('user_id', driverId)
              .eq('verification_status', 'verified')
              .maybeSingle();
          
          print('   🔍 Vehicle query response: $vehicleResponse');
          
          if (vehicleResponse != null) {
            vehicleModel = vehicleResponse['vehicle_model'] as String?;
            vehicleColor = vehicleResponse['vehicle_color'] as String?;
            vehiclePlateNumber = vehicleResponse['vehicle_plate_number'] as String?;
            print('   ✅ Vehicle found: $vehicleModel ($vehicleColor) - $vehiclePlateNumber');
          } else {
            print('   ⚠️ No verified vehicle found for driver $driverId');
            // Try without verification status filter
            final anyVehicle = await _supabase
                .from('driver_verifications')
                .select('vehicle_model, vehicle_color, vehicle_plate_number')
                .eq('user_id', driverId)
                .maybeSingle();
            
            if (anyVehicle != null) {
              vehicleModel = anyVehicle['vehicle_model'] as String?;
              vehicleColor = anyVehicle['vehicle_color'] as String?;
              vehiclePlateNumber = anyVehicle['vehicle_plate_number'] as String?;
              print('   ✅ Unverified vehicle found: $vehicleModel ($vehicleColor) - $vehiclePlateNumber');
            }
          }
        } catch (e) {
          print('   ❌ Error fetching vehicle info: $e');
        }
        
        print('   👤 Driver: $driverName');
        print('   ⭐ Driver rating: $driverRating');
        print('   🚗 Vehicle: ${vehicleModel ?? 'N/A'} (${vehicleColor ?? 'N/A'}) - ${vehiclePlateNumber ?? 'N/A'}');
        
        // Skip if rating below threshold
        if (driverRating < minRatingThreshold) {
          print('   ❌ Skipped - Rating too low (min $minRatingThreshold)');
          continue;
        }

        // Check gender preferences (safer matching)
        final passengerId = _supabase.auth.currentUser?.id;
        if (passengerId != null) {
          final canMatch = await _genderMatchingService.canMatch(
            passengerId: passengerId,
            driverId: driverId,
          );
          if (!canMatch) {
            print('   ❌ Skipped - Gender preference mismatch');
            continue;
          }
        }

        // Calculate individual scores
        final routeScore = _computeRouteScore(
          passengerPickup: passengerPickup,
          passengerDestination: passengerDestination,
          driverPickup: driverPickup,
          driverDestination: driverDestination,
        );

        // CRITICAL: Skip rides with 0 route score (destinations don't match)
        if (routeScore == 0.0) {
          print('   ❌ Skipped - Destinations not compatible for carpooling');
          continue;
        }

        final priceScore = _computePriceScore(fare);
        final reputationScore = _computeReputationScore(driverRating);

        scoredRides.add({
          'ride': ride,
          'driver_name': driverName,
          'driver_photo_url': driverInfo['photo_url'],
          'driver_total_ratings': driverInfo['total_ratings'],
          'driver_gender': driverInfo['gender'],
          'driver_is_verified': driverInfo['is_verified'] ?? false,
          'vehicle_model': vehicleModel,
          'vehicle_color': vehicleColor,
          'vehicle_plate_number': vehiclePlateNumber,
          'route_score': routeScore,
          'price_score': priceScore,
          'reputation_score': reputationScore,
          'pickup_distance_km': pickupDistance,
          'dest_distance_km': destDistance,
          'fare': fare,
          'driver_rating': driverRating,
        });
      }

      if (scoredRides.isEmpty) {
        print('\n❌ No rides passed the filtering criteria');
        print('   Possible reasons:');
        print('   - All rides missing coordinates (from_lat, from_lng, to_lat, to_lng)');
        print('   - All rides too far away (> ${maxDistanceKm}km)');
        print('   - All rides too expensive (> RM$maxWillingnessToPay)');
        print('   - All rides have ratings below threshold ($minRatingThreshold)');
        print('   - All rides have DIFFERENT destinations (> 2km away)');
        print('   ℹ️  Carpooling requires rides going to the SAME destination!');
        return [];
      }

      print('\n✅ ${scoredRides.length} rides passed initial filtering');

      // 3. SKIP normalization if only 1 ride (to preserve absolute scores)
      // Normalize scores using Min-Max scaling ONLY if multiple rides
      if (scoredRides.length > 1) {
        _normalizeScores(scoredRides, 'route_score');
        _normalizeScores(scoredRides, 'price_score');
        _normalizeScores(scoredRides, 'reputation_score');
        print('   ℹ️  Normalized scores across ${scoredRides.length} rides');
      } else {
        print('   ℹ️  Skipped normalization (only 1 ride available)');
      }

      // 4. Calculate hybrid score
      for (final scored in scoredRides) {
        final hybridScore = 
            (weightRoute * scored['route_score']) +
            (weightPrice * scored['price_score']) +
            (weightReputation * scored['reputation_score']);
        
        scored['hybrid_score'] = hybridScore;
        print('   Ride ${scored['ride']['id']}: Score = ${(hybridScore * 100).toStringAsFixed(0)}%');
      }

      // 5. Sort by hybrid score (descending) and return top-N
      scoredRides.sort((a, b) => 
        (b['hybrid_score'] as double).compareTo(a['hybrid_score'] as double)
      );

      final topMatches = scoredRides.take(topN).toList();

      print('\n🎯 Returning top ${topMatches.length} matches');

      // 6. Convert to SmartMatch objects
      return topMatches.map((scored) {
        return SmartMatch.fromScoredData(scored);
      }).toList();

    } catch (e, stackTrace) {
      print('❌ Error in smart matching: $e');
      print('Stack trace: $stackTrace');
      return [];
    }
  }

  /// Compute Route Score
  /// CRITICAL: Destination MUST be close (< 2km), pickup can vary
  /// This matches carpooling logic: same destination, different pickups
  double _computeRouteScore({
    required LatLng passengerPickup,
    required LatLng passengerDestination,
    required LatLng driverPickup,
    required LatLng driverDestination,
  }) {
    // Calculate distances using Haversine formula
    final pickupDistance = _calculateDistance(passengerPickup, driverPickup);
    final destDistance = _calculateDistance(passengerDestination, driverDestination);

    print('   📍 Pickup distance: ${pickupDistance.toStringAsFixed(2)}km');
    print('   🎯 Destination distance: ${destDistance.toStringAsFixed(2)}km');

    // CRITICAL: If destinations are too far apart, this is NOT a match!
    // For carpooling to work, passengers must be going to the SAME destination
    if (destDistance > 2.0) {
      print('   ❌ REJECTED: Destinations too far apart (${destDistance.toStringAsFixed(2)}km > 2.0km)');
      print('   ℹ️  Carpooling requires SAME destination!');
      return 0.0; // Return 0 score - this ride doesn't match
    }

    // Destination is MORE important than pickup (70% vs 30%)
    // Because carpooling = same destination, different pickups
    final destScore = exp(-destDistance / 1.0); // Very strict: < 1km is excellent
    
    // Improved pickup scoring with better range handling
    // Use a more lenient decay factor for longer pickup distances
    // - 0-5km: Excellent (80-100%)
    // - 5-10km: Good (50-80%)
    // - 10-15km: Acceptable (30-50%)
    // - 15-20km: Poor (< 30%)
    final pickupScore = exp(-pickupDistance / 10.0); // More lenient: < 10km is good
    
    // Weighted combination: 70% destination, 30% pickup
    // Increased pickup weight from 20% to 30% for better balance
    final combinedScore = (destScore * 0.7) + (pickupScore * 0.3);
    
    print('   📊 Destination score: ${(destScore * 100).toStringAsFixed(0)}%');
    print('   📊 Pickup score: ${(pickupScore * 100).toStringAsFixed(0)}%');
    print('   📊 Combined route score: ${(combinedScore * 100).toStringAsFixed(0)}%');
    
    return combinedScore;
  }

  /// Compute Price Score
  /// Lower fare = higher score
  double _computePriceScore(double fare) {
    // Inverse relationship: lower price is better
    // Normalize to a reasonable range (e.g., RM 6 to RM 80 for student fares)
    const minFare = 6.0; // Updated minimum fare
    const maxFare = 80.0; // Updated for longer distance student fares
    
    if (fare <= minFare) return 1.0;
    if (fare >= maxFare) return 0.0;
    
    // Linear inverse scaling
    final score = 1.0 - ((fare - minFare) / (maxFare - minFare));
    
    return score.clamp(0.0, 1.0);
  }

  /// Compute Reputation Score
  /// Higher rating = higher score
  double _computeReputationScore(double driverRating) {
    // Normalize rating (assuming 0-5 scale)
    const minRating = 0.0;
    const maxRating = 5.0;
    
    if (driverRating <= minRating) return 0.0;
    if (driverRating >= maxRating) return 1.0;
    
    // Linear scaling
    final score = (driverRating - minRating) / (maxRating - minRating);
    
    return score.clamp(0.0, 1.0);
  }

  /// Normalize scores using Min-Max scaling
  /// Scales all values to [0, 1] range
  void _normalizeScores(List<Map<String, dynamic>> scoredRides, String scoreKey) {
    if (scoredRides.isEmpty) return;

    final scores = scoredRides.map((r) => r[scoreKey] as double).toList();
    final minScore = scores.reduce(min);
    final maxScore = scores.reduce(max);

    // Avoid division by zero
    if (maxScore == minScore) {
      for (final ride in scoredRides) {
        ride[scoreKey] = 1.0;
      }
      return;
    }

    // Min-Max normalization
    for (final ride in scoredRides) {
      final oldScore = ride[scoreKey] as double;
      final normalizedScore = (oldScore - minScore) / (maxScore - minScore);
      ride[scoreKey] = normalizedScore;
    }
  }

  /// Calculate distance between two points using Haversine formula
  double _calculateDistance(LatLng point1, LatLng point2) {
    const Distance distance = Distance();
    final distanceMeters = distance.as(
      LengthUnit.Meter,
      point1,
      point2,
    );
    return distanceMeters / 1000.0; // Convert to km
  }

  /// Get driver info (name, rating, photo, gender, verification)
  Future<Map<String, dynamic>> _getDriverInfo(String driverId) async {
    try {
      // Fetch driver profile from profiles table
      final response = await _supabase
          .from('profiles')
          .select('full_name, avatar_url, gender')
          .eq('id', driverId)
          .maybeSingle();
      
      // Calculate average rating from driver_ratings table
      final ratingsResponse = await _supabase
          .from('driver_ratings')
          .select('rating')
          .eq('driver_id', driverId);
      
      double averageRating = 4.5; // Default rating
      int totalRatings = 0;
      
      if (ratingsResponse.isNotEmpty) {
        final ratings = ratingsResponse.map((r) => (r['rating'] as num).toDouble()).toList();
        averageRating = ratings.reduce((a, b) => a + b) / ratings.length;
        totalRatings = ratings.length;
      }

      // Check driver verification status
      final verificationResponse = await _supabase
          .from('driver_verifications')
          .select('verification_status')
          .eq('user_id', driverId)
          .maybeSingle();
      
      final isVerified = verificationResponse?['verification_status'] == 'verified';
      
      if (response != null) {
        return {
          'name': response['full_name'] ?? 'Driver',
          'photo_url': response['avatar_url'],
          'rating': averageRating,
          'total_ratings': totalRatings,
          'gender': response['gender'],
          'is_verified': isVerified,
        };
      }
      
      return {
        'name': 'Driver',
        'photo_url': null,
        'rating': averageRating,
        'total_ratings': totalRatings,
        'gender': null,
        'is_verified': false,
      };
    } catch (e) {
      print('Error fetching driver info: $e');
      return {
        'name': 'Driver',
        'photo_url': null,
        'rating': 4.5,
      };
    }
  }

  /// Update weights for hybrid scoring
  /// Allows dynamic adjustment based on user preferences
  void updateWeights({
    double? route,
    double? price,
    double? reputation,
  }) {
    if (route != null) weightRoute = route;
    if (price != null) weightPrice = price;
    if (reputation != null) weightReputation = reputation;

    // Normalize weights to sum to 1.0
    final total = weightRoute + weightPrice + weightReputation;
    weightRoute /= total;
    weightPrice /= total;
    weightReputation /= total;
  }
}

/// Smart Match Result
class SmartMatch {
  final String rideId;
  final String driverId;
  final String driverName;
  final String? driverPhotoUrl;
  final String fromLocation;
  final String toLocation;
  final LatLng driverPickup;
  final LatLng driverDestination;
  final DateTime scheduledTime;
  final int availableSeats;
  final double fare;
  final double driverRating;
  final int driverTotalRatings;
  
  // Vehicle information
  final String? vehicleModel;
  final String? vehicleColor;
  final String? vehiclePlateNumber;
  
  // Safety information
  final String? driverGender;
  final bool isVerified;
  
  // Scoring details
  final double hybridScore;
  final double routeScore;
  final double priceScore;
  final double reputationScore;
  final double pickupDistanceKm;
  final double destDistanceKm;

  const SmartMatch({
    required this.rideId,
    required this.driverId,
    required this.driverName,
    this.driverPhotoUrl,
    required this.fromLocation,
    required this.toLocation,
    required this.driverPickup,
    required this.driverDestination,
    this.vehicleModel,
    this.vehicleColor,
    this.vehiclePlateNumber,
    this.driverGender,
    this.isVerified = false,
    required this.scheduledTime,
    required this.availableSeats,
    required this.fare,
    required this.driverRating,
    required this.driverTotalRatings,
    required this.hybridScore,
    required this.routeScore,
    required this.priceScore,
    required this.reputationScore,
    required this.pickupDistanceKm,
    required this.destDistanceKm,
  });

  factory SmartMatch.fromScoredData(Map<String, dynamic> scoredData) {
    final ride = scoredData['ride'] as Map<String, dynamic>;

    return SmartMatch(
      rideId: ride['id'] as String,
      driverId: ride['driver_id'] as String,
      driverName: scoredData['driver_name'] as String? ?? 'Driver',
      driverPhotoUrl: scoredData['driver_photo_url'] as String?,
      vehicleModel: scoredData['vehicle_model'] as String?,
      vehicleColor: scoredData['vehicle_color'] as String?,
      vehiclePlateNumber: scoredData['vehicle_plate_number'] as String?,
      driverGender: scoredData['driver_gender'] as String?,
      isVerified: scoredData['driver_is_verified'] as bool? ?? false,
      fromLocation: ride['from_location'] as String,
      toLocation: ride['to_location'] as String,
      driverPickup: LatLng(
        (ride['from_lat'] as num).toDouble(),
        (ride['from_lng'] as num).toDouble(),
      ),
      driverDestination: LatLng(
        (ride['to_lat'] as num).toDouble(),
        (ride['to_lng'] as num).toDouble(),
      ),
      scheduledTime: TimezoneHelper.utcToMalaysia(DateTime.parse(ride['scheduled_time'] as String).toUtc()),
      availableSeats: ride['available_seats'] as int,
      fare: scoredData['fare'] as double,
      driverRating: scoredData['driver_rating'] as double,
      driverTotalRatings: scoredData['driver_total_ratings'] as int? ?? 0,
      hybridScore: scoredData['hybrid_score'] as double,
      routeScore: scoredData['route_score'] as double,
      priceScore: scoredData['price_score'] as double,
      reputationScore: scoredData['reputation_score'] as double,
      pickupDistanceKm: scoredData['pickup_distance_km'] as double,
      destDistanceKm: scoredData['dest_distance_km'] as double,
    );
  }

  /// Get match quality label
  String get matchQuality {
    if (hybridScore >= 0.8) return 'Best Match';
    if (hybridScore >= 0.6) return 'Great Match';
    if (hybridScore >= 0.4) return 'Good Match';
    return 'Fair Match';
  }

  /// Get match quality color
  String get matchQualityBadge {
    if (hybridScore >= 0.8) return '🟢 Best Match';
    if (hybridScore >= 0.6) return '🟦 Great Match';
    if (hybridScore >= 0.4) return '🟡 Good Match';
    return '🟠 Fair Match';
  }

  /// Get score as percentage
  String get scorePercentage => '${(hybridScore * 100).toStringAsFixed(0)}%';
}

