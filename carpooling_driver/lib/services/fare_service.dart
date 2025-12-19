import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:developer' as developer;

/// Service for calculating and managing ride fares
class FareService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Calculate fare using REAL distance from API
  Future<FareCalculation> calculateFareByDistance({
    required String fromLocation,
    required String toLocation,
    required double distanceKm,
    required DateTime scheduledTime,
  }) async {
    try {
      developer.log(
        'Calculating fare: $fromLocation → $toLocation (${distanceKm.toStringAsFixed(1)} km)',
        name: 'FareService',
      );

      final response = await _supabase.rpc(
        'calculate_fare_by_distance',
        params: {
          'p_from_location': fromLocation,
          'p_to_location': toLocation,
          'p_distance_km': distanceKm,
          'p_scheduled_time': scheduledTime.toIso8601String(),
        },
      );

      if (response == null || (response as List).isEmpty) {
        throw Exception('No fare calculation returned');
      }

      final data = (response).first as Map<String, dynamic>;
      
      final result = FareCalculation.fromJson(data);
      
      developer.log(
        'Fare calculated: Base RM${result.baseFare}, Final RM${result.finalFare} (${result.calculationMethod})',
        name: 'FareService',
      );
      
      return result;
    } catch (e) {
      developer.log(
        'Error calculating fare: $e',
        name: 'FareService',
        error: e,
      );
      rethrow;
    }
  }
  
  /// Calculate fare for a route (DEPRECATED - use calculateFareByDistance)
  @Deprecated('Use calculateFareByDistance with real distance from API')
  Future<FareCalculation> calculateFare({
    required String fromLocation,
    required String toLocation,
    required DateTime scheduledTime,
  }) async {
    // For backward compatibility, use default 10km distance
    return calculateFareByDistance(
      fromLocation: fromLocation,
      toLocation: toLocation,
      distanceKm: 10.0,
      scheduledTime: scheduledTime,
    );
  }

  /// Get all available Grab fare references
  Future<List<GrabFareReference>> getGrabFares() async {
    try {
      final response = await _supabase
          .from('grab_fares')
          .select()
          .eq('is_active', true)
          .order('from_location');

      return (response as List)
          .map((data) => GrabFareReference.fromJson(data))
          .toList();
    } catch (e) {
      developer.log(
        'Error fetching grab fares: $e',
        name: 'FareService',
        error: e,
      );
      rethrow;
    }
  }

  /// Get Grab fare for specific route
  Future<double?> getGrabFare(String from, String to) async {
    try {
      final response = await _supabase
          .from('grab_fares')
          .select('grab_fare')
          .eq('from_location', from)
          .eq('to_location', to)
          .eq('is_active', true)
          .maybeSingle();

      if (response == null) return null;
      
      return (response['grab_fare'] as num).toDouble();
    } catch (e) {
      developer.log(
        'Error fetching grab fare: $e',
        name: 'FareService',
        error: e,
      );
      return null;
    }
  }
}

/// Fare calculation result
class FareCalculation {
  final double baseFare;
  final double grabFare;
  final bool highDemand;
  final double surgeMultiplier;
  final double finalFare;
  final double savings;
  final String calculationMethod; // 'grab_reference' or 'distance_based'

  const FareCalculation({
    required this.baseFare,
    required this.grabFare,
    required this.highDemand,
    required this.surgeMultiplier,
    required this.finalFare,
    required this.savings,
    this.calculationMethod = 'unknown',
  });

  factory FareCalculation.fromJson(Map<String, dynamic> json) {
    return FareCalculation(
      baseFare: (json['base_fare'] as num).toDouble(),
      grabFare: (json['grab_fare'] as num).toDouble(),
      highDemand: json['high_demand'] as bool,
      surgeMultiplier: (json['surge_multiplier'] as num).toDouble(),
      finalFare: (json['final_fare'] as num).toDouble(),
      savings: (json['savings'] as num).toDouble(),
      calculationMethod: json['calculation_method'] as String? ?? 'unknown',
    );
  }

  /// Get discount percentage (always 40% or more)
  double get discountPercentage {
    return ((grabFare - finalFare) / grabFare) * 100;
  }

  /// Get surcharge amount (if high demand)
  double get surchargeAmount {
    return highDemand ? (finalFare - baseFare) : 0;
  }

  /// Get formatted display strings
  String get baseFareDisplay => 'RM ${baseFare.toStringAsFixed(2)}';
  String get grabFareDisplay => 'RM ${grabFare.toStringAsFixed(2)}';
  String get finalFareDisplay => 'RM ${finalFare.toStringAsFixed(2)}';
  String get savingsDisplay => 'RM ${savings.toStringAsFixed(2)}';
  String get surchargeDisplay => 'RM ${surchargeAmount.toStringAsFixed(2)}';
  String get discountDisplay => '${discountPercentage.toStringAsFixed(0)}%';
}

/// Grab fare reference model
class GrabFareReference {
  final String id;
  final String fromLocation;
  final String toLocation;
  final double grabFare;
  final double? distanceKm;
  final int? estimatedDurationMinutes;
  final bool isActive;
  final String? notes;

  const GrabFareReference({
    required this.id,
    required this.fromLocation,
    required this.toLocation,
    required this.grabFare,
    this.distanceKm,
    this.estimatedDurationMinutes,
    required this.isActive,
    this.notes,
  });

  factory GrabFareReference.fromJson(Map<String, dynamic> json) {
    return GrabFareReference(
      id: json['id'] as String,
      fromLocation: json['from_location'] as String,
      toLocation: json['to_location'] as String,
      grabFare: (json['grab_fare'] as num).toDouble(),
      distanceKm: json['distance_km'] != null 
          ? (json['distance_km'] as num).toDouble() 
          : null,
      estimatedDurationMinutes: json['estimated_duration_minutes'] as int?,
      isActive: json['is_active'] as bool,
      notes: json['notes'] as String?,
    );
  }

  /// Calculate app base fare (40% lower than Grab)
  double get appBaseFare => grabFare * 0.6;

  /// Calculate high demand fare (+20% surcharge)
  double get highDemandFare => appBaseFare * 1.2;
}

