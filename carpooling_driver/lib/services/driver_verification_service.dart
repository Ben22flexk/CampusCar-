import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:developer' as developer;
import 'dart:io';

/// Service for driver verification and validation
class DriverVerificationService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Get current user's verification status
  Future<DriverVerificationStatus?> getVerificationStatus() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return null;

      final response = await _supabase
          .from('driver_verifications')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (response == null) return null;

      return DriverVerificationStatus.fromJson(response);
    } catch (e) {
      developer.log('Error getting verification status: $e', name: 'DriverVerification');
      rethrow;
    }
  }

  /// Submit driver verification
  Future<VerificationResult> submitVerification({
    required String licenseNumber,
    required String licensePlate,
    required String vehicleManufacturer,
    required String vehicleModel,
    required String vehicleColor,
    required int vehicleSeats,
    required String licenseImageUrl,
    String? licenseState,
    DateTime? licenseExpiryDate,
    int? vehicleYear,
    required bool termsAccepted,
    String? ipAddress,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      developer.log('Submitting driver verification for user: $userId', name: 'DriverVerification');

      // Prepare data
      final data = {
        'user_id': userId,
        'license_number': licenseNumber.trim().toUpperCase(),
        'license_state': licenseState,
        'license_image_url': licenseImageUrl,
        'vehicle_plate_number': licensePlate.trim().toUpperCase(),
        'vehicle_manufacturer': vehicleManufacturer.trim(),
        'vehicle_model': vehicleModel.trim(),
        'vehicle_color': vehicleColor.trim(),
        'vehicle_year': vehicleYear,
        'vehicle_seats': vehicleSeats,
        'terms_accepted': termsAccepted,
        'terms_accepted_at': DateTime.now().toIso8601String(),
      };

      // Upsert (insert or update) - conflict on user_id
      await _supabase
          .from('driver_verifications')
          .upsert(data, onConflict: 'user_id');

      // Run auto-verification
      final result = await _autoVerify(userId);

      developer.log('Verification result: ${result.status}', name: 'DriverVerification');

      return result;
    } catch (e) {
      developer.log('Error submitting verification: $e', name: 'DriverVerification');
      
      // Handle duplicate license/plate errors
      final errorMessage = e.toString().toLowerCase();
      
      if (errorMessage.contains('license_number') && errorMessage.contains('unique')) {
        throw Exception('This license number is already registered by another driver');
      }
      
      if (errorMessage.contains('vehicle_plate') && errorMessage.contains('unique')) {
        throw Exception('This vehicle plate is already registered by another driver');
      }
      
      rethrow;
    }
  }

  /// Upload license image (just uploads to storage, doesn't update DB)
  Future<String> uploadLicenseImage(File imageFile) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      final fileExt = imageFile.path.split('.').last;
      final fileName = '$userId/license_${DateTime.now().millisecondsSinceEpoch}.$fileExt';

      developer.log('Uploading license image: $fileName', name: 'DriverVerification');

      // Upload to Supabase Storage
      await _supabase.storage
          .from('driver_documents')
          .upload(fileName, imageFile);

      // Get public URL
      final publicUrl = _supabase.storage
          .from('driver_documents')
          .getPublicUrl(fileName);

      developer.log('License image uploaded successfully: $publicUrl', name: 'DriverVerification');

      return publicUrl;
    } catch (e) {
      developer.log('Error uploading license image: $e', name: 'DriverVerification');
      rethrow;
    }
  }

  /// Run auto-verification
  Future<VerificationResult> _autoVerify(String userId) async {
    try {
      final response = await _supabase.rpc(
        'auto_verify_driver',
        params: {'p_user_id': userId},
      );

      developer.log('Auto-verify response: $response', name: 'DriverVerification');

      if (response == null) {
        throw Exception('No verification result returned');
      }

      // The function returns JSON directly (not a list)
      final data = response as Map<String, dynamic>;

      return VerificationResult(
        isApproved: data['is_approved'] as bool,
        status: data['status'] as String,
        errors: (data['errors'] as List?)?.cast<String>() ?? [],
      );
    } catch (e) {
      developer.log('Error running auto-verification: $e', name: 'DriverVerification');
      rethrow;
    }
  }

  /// Check current verification status
  Future<DriverVerificationResult> checkVerificationStatus() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        return DriverVerificationResult(
          isApproved: false,
          status: 'not_started',
          errors: ['User not authenticated'],
        );
      }

      final response = await _supabase
          .from('driver_verifications')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (response == null) {
        return DriverVerificationResult(
          isApproved: false,
          status: 'not_started',
          errors: [],
        );
      }

      final verificationStatus = response['verification_status'] as String? ?? 'pending';
      final isApproved = verificationStatus == 'verified';
      
      return DriverVerificationResult(
        isApproved: isApproved,
        status: verificationStatus,
        errors: (response['rejection_reasons'] as List<dynamic>?)
                ?.cast<String>() ?? [],
      );
    } catch (e) {
      developer.log('Error checking verification status: $e', name: 'DriverVerification');
      return DriverVerificationResult(
        isApproved: false,
        status: 'error',
        errors: ['Failed to check status: $e'],
      );
    }
  }

  /// Validate Malaysian license format (client-side)
  bool validateMalaysianLicense(String licenseNumber) {
    final cleaned = licenseNumber.trim().toUpperCase();
    
    // Format 1: Single letter + 6-7 digits (e.g., A1234567)
    if (RegExp(r'^[A-Z][0-9]{6,7}$').hasMatch(cleaned)) return true;
    
    // Format 2: Two letters + 6-7 digits (e.g., SA1234567)
    if (RegExp(r'^[A-Z]{2}[0-9]{6,7}$').hasMatch(cleaned)) return true;
    
    // Format 3: Letter + dash + digits (e.g., A-123456)
    if (RegExp(r'^[A-Z]-?[0-9]{6,7}$').hasMatch(cleaned)) return true;
    
    return false;
  }

  /// Validate Malaysian vehicle plate format (client-side)
  bool validateMalaysianPlate(String plateNumber) {
    final cleaned = plateNumber.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
    
    // Format 1: 1-3 letters, space, 1-4 digits (e.g., WAB 1234)
    if (RegExp(r'^[A-Z]{1,3}\s[0-9]{1,4}$').hasMatch(cleaned)) return true;
    
    // Format 2: Without space (e.g., WAB1234)
    if (RegExp(r'^[A-Z]{1,3}[0-9]{1,4}$').hasMatch(cleaned)) return true;
    
    // Format 3: Special plates (e.g., P 1, VIP 1)
    if (RegExp(r'^[A-Z]{1,3}\s?[0-9]{1,4}[A-Z]?$').hasMatch(cleaned)) return true;
    
    return false;
  }

  /// Get format examples
  String getLicenseFormatExample() {
    return 'Examples: A1234567, SA1234567, B987654';
  }

  String getPlateFormatExample() {
    return 'Examples: WAB 1234, WUA 9876, ABC 123';
  }
}

/// Driver verification status model
class DriverVerificationStatus {
  final String id;
  final String userId;
  final String licenseNumber;
  final String vehiclePlate;
  final String vehicleManufacturer;
  final String vehicleModel;
  final String vehicleColor;
  final int vehicleSeats;
  final String verificationStatus;
  final bool isVerified;
  final bool termsAccepted;
  final String? licenseImageUrl;
  final bool licenseFormatValid;
  final bool vehiclePlateFormatValid;
  final List<String> validationErrors;
  final DateTime? verifiedAt;

  const DriverVerificationStatus({
    required this.id,
    required this.userId,
    required this.licenseNumber,
    required this.vehiclePlate,
    required this.vehicleManufacturer,
    required this.vehicleModel,
    required this.vehicleColor,
    required this.vehicleSeats,
    required this.verificationStatus,
    required this.isVerified,
    required this.termsAccepted,
    this.licenseImageUrl,
    required this.licenseFormatValid,
    required this.vehiclePlateFormatValid,
    required this.validationErrors,
    this.verifiedAt,
  });

  factory DriverVerificationStatus.fromJson(Map<String, dynamic> json) {
    return DriverVerificationStatus(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      licenseNumber: json['license_number'] as String,
      vehiclePlate: json['vehicle_plate_number'] as String,
      vehicleManufacturer: json['vehicle_manufacturer'] as String,
      vehicleModel: json['vehicle_model'] as String,
      vehicleColor: json['vehicle_color'] as String,
      vehicleSeats: json['vehicle_seats'] as int,
      verificationStatus: json['verification_status'] as String,
      isVerified: json['verification_status'] == 'verified',
      termsAccepted: json['terms_accepted'] as bool,
      licenseImageUrl: json['license_image_url'] as String?,
      licenseFormatValid: true, // Validated by database function
      vehiclePlateFormatValid: true, // Validated by database function
      validationErrors: json['rejection_reasons'] != null
          ? List<String>.from(json['rejection_reasons'])
          : [],
      verifiedAt: json['verified_at'] != null
          ? DateTime.parse(json['verified_at'] as String)
          : null,
    );
  }

  bool get canDrive => isVerified && verificationStatus == 'auto_approved';
}

/// Verification result model
class VerificationResult {
  final bool isApproved;
  final String status;
  final List<String> errors;

  const VerificationResult({
    required this.isApproved,
    required this.status,
    required this.errors,
  });

  bool get hasErrors => errors.isNotEmpty;
}

/// Driver Verification Result (alias for consistency)
typedef DriverVerificationResult = VerificationResult;

