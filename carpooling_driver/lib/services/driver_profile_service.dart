import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:developer' as developer;

/// Service to check driver profile completion
class DriverProfileService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Check if driver has completed their profile
  /// Returns: {isComplete, missingFields, verificationStatus}
  Future<DriverProfileStatus> checkProfileCompletion() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      // Use the database function
      final response = await _supabase.rpc(
        'is_driver_profile_complete',
        params: {'driver_id': userId},
      );

      final isComplete = response as bool;

      developer.log(
        'Driver profile complete: $isComplete',
        name: 'DriverProfileService',
      );

      // Get detailed verification status
      final verification = await _getVerificationDetails(userId);

      return DriverProfileStatus(
        isComplete: isComplete,
        verificationStatus: verification['status'] as String?,
        hasLicense: verification['has_license'] as bool? ?? false,
        hasVehicle: verification['has_vehicle'] as bool? ?? false,
      );
    } catch (e) {
      developer.log(
        'Error checking profile: $e',
        name: 'DriverProfileService',
        error: e,
      );
      rethrow;
    }
  }

  /// Get verification details
  Future<Map<String, dynamic>> _getVerificationDetails(String userId) async {
    try {
      final response = await _supabase
          .from('driver_verifications')
          .select('verification_status, license_number, vehicle_plate_number')
          .eq('user_id', userId)
          .maybeSingle();

      if (response == null) {
        return {
          'status': null,
          'has_license': false,
          'has_vehicle': false,
        };
      }

      return {
        'status': response['verification_status'],
        'has_license': response['license_number'] != null,
        'has_vehicle': response['vehicle_plate_number'] != null,
      };
    } catch (e) {
      developer.log(
        'Error getting verification details: $e',
        name: 'DriverProfileService',
        error: e,
      );
      return {
        'status': null,
        'has_license': false,
        'has_vehicle': false,
      };
    }
  }

  /// Get missing fields for profile completion
  List<String> getMissingFields(DriverProfileStatus status) {
    final missing = <String>[];
    
    if (!status.hasLicense) {
      missing.add('Driver License');
    }
    if (!status.hasVehicle) {
      missing.add('Vehicle Information');
    }
    if (status.verificationStatus == null) {
      missing.add('Complete Verification');
    }
    
    return missing;
  }

  /// Get user-friendly message based on status
  String getStatusMessage(DriverProfileStatus status) {
    if (status.isComplete) {
      switch (status.verificationStatus) {
        case 'verified':
          return 'Your profile is complete and verified! 🎉';
        case 'pending':
          return 'Profile complete. Verification in progress...';
        case 'rejected':
          return 'Profile complete but verification was rejected.';
        default:
          return 'Profile complete!';
      }
    } else {
      final missing = getMissingFields(status);
      return 'Please complete: ${missing.join(", ")}';
    }
  }

  /// Get full vehicle details for profile display
  Future<VehicleDetails?> getVehicleDetails() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return null;

      final response = await _supabase
          .from('driver_verifications')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (response == null) return null;

      return VehicleDetails(
        licensePlate: response['vehicle_plate_number'] as String,
        manufacturer: response['vehicle_manufacturer'] as String,
        model: response['vehicle_model'] as String,
        color: response['vehicle_color'] as String,
        year: response['vehicle_year'] as int?,
        seats: response['vehicle_seats'] as int,
        licenseNumber: response['license_number'] as String,
        verificationStatus: response['verification_status'] as String,
        verifiedAt: response['verified_at'] != null
            ? DateTime.parse(response['verified_at'] as String)
            : null,
      );
    } catch (e) {
      developer.log(
        'Error getting vehicle details: $e',
        name: 'DriverProfileService',
        error: e,
      );
      return null;
    }
  }
}

/// Driver profile completion status
class DriverProfileStatus {
  final bool isComplete;
  final String? verificationStatus;
  final bool hasLicense;
  final bool hasVehicle;

  const DriverProfileStatus({
    required this.isComplete,
    this.verificationStatus,
    required this.hasLicense,
    required this.hasVehicle,
  });

  bool get isVerified => verificationStatus == 'verified';
  bool get isPending => verificationStatus == 'pending';
  bool get isRejected => verificationStatus == 'rejected';
  
  bool get canCreateRides => isComplete && isVerified;
}

/// Vehicle details model
class VehicleDetails {
  final String licensePlate;
  final String manufacturer;
  final String model;
  final String color;
  final int? year;
  final int seats;
  final String licenseNumber;
  final String verificationStatus;
  final DateTime? verifiedAt;

  const VehicleDetails({
    required this.licensePlate,
    required this.manufacturer,
    required this.model,
    required this.color,
    this.year,
    required this.seats,
    required this.licenseNumber,
    required this.verificationStatus,
    this.verifiedAt,
  });

  String get fullVehicleName => year != null
      ? '$year $manufacturer $model'
      : '$manufacturer $model';

  String get statusDisplay {
    switch (verificationStatus) {
      case 'verified':
        return '✅ Verified';
      case 'pending':
        return '⏳ Pending';
      case 'rejected':
        return '❌ Rejected';
      default:
        return '⚠️ Unknown';
    }
  }

  bool get isVerified => verificationStatus == 'verified';
}

