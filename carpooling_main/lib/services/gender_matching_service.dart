import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:carpooling_main/models/gender_preferences.dart';
import 'dart:developer' as developer;

/// Service to handle gender-based matching logic
class GenderMatchingService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Check if a passenger can match with a driver based on gender preferences
  Future<bool> canMatch({
    required String passengerId,
    required String driverId,
  }) async {
    try {
      // Fetch passenger and driver profiles
      final passengerProfile = await _supabase
          .from('profiles')
          .select('gender, passenger_gender_preference')
          .eq('id', passengerId)
          .single();

      final driverProfile = await _supabase
          .from('profiles')
          .select('gender, driver_gender_preference')
          .eq('id', driverId)
          .single();

      final passengerGender = Gender.fromString(passengerProfile['gender']);
      final driverGender = Gender.fromString(driverProfile['gender']);
      final passengerPreference = PassengerGenderPreference.fromString(
        passengerProfile['passenger_gender_preference'],
      );
      final driverPreference = DriverGenderPreference.fromString(
        driverProfile['driver_gender_preference'],
      );

      // Check passenger preferences
      if (passengerPreference == PassengerGenderPreference.femaleOnly) {
        if (driverGender != Gender.female) {
          developer.log(
            '❌ Match rejected: Passenger requires female driver',
            name: 'GenderMatching',
          );
          return false;
        }
      } else if (passengerPreference == PassengerGenderPreference.sameGenderOnly) {
        if (passengerGender != driverGender) {
          developer.log(
            '❌ Match rejected: Passenger requires same gender',
            name: 'GenderMatching',
          );
          return false;
        }
      }

      // Check driver preferences
      if (driverPreference == DriverGenderPreference.womenNonBinaryOnly) {
        if (passengerGender != Gender.female &&
            passengerGender != Gender.nonBinary) {
          developer.log(
            '❌ Match rejected: Driver accepts only women/non-binary',
            name: 'GenderMatching',
          );
          return false;
        }
      }

      developer.log(
        '✅ Gender match approved',
        name: 'GenderMatching',
      );
      return true;
    } catch (e) {
      developer.log(
        '❌ Error checking gender match: $e',
        name: 'GenderMatching',
      );
      // On error, allow match (fail open for safety)
      return true;
    }
  }

  /// Get user's gender
  Future<Gender?> getUserGender(String userId) async {
    try {
      final profile = await _supabase
          .from('profiles')
          .select('gender')
          .eq('id', userId)
          .single();

      return Gender.fromString(profile['gender']);
    } catch (e) {
      developer.log('Error getting user gender: $e', name: 'GenderMatching');
      return null;
    }
  }

  /// Update user gender
  Future<void> updateUserGender({
    required String userId,
    required Gender gender,
  }) async {
    try {
      await _supabase
          .from('profiles')
          .update({'gender': gender.value})
          .eq('id', userId);

      developer.log(
        '✅ Updated user gender: ${gender.value}',
        name: 'GenderMatching',
      );
    } catch (e) {
      developer.log('Error updating gender: $e', name: 'GenderMatching');
      rethrow;
    }
  }

  /// Update passenger gender preference
  Future<void> updatePassengerPreference({
    required String userId,
    required PassengerGenderPreference preference,
  }) async {
    try {
      await _supabase
          .from('profiles')
          .update({'passenger_gender_preference': preference.value})
          .eq('id', userId);

      developer.log(
        '✅ Updated passenger preference: ${preference.value}',
        name: 'GenderMatching',
      );
    } catch (e) {
      developer.log(
        'Error updating passenger preference: $e',
        name: 'GenderMatching',
      );
      rethrow;
    }
  }

  /// Update driver gender preference
  Future<void> updateDriverPreference({
    required String userId,
    required DriverGenderPreference preference,
  }) async {
    try {
      await _supabase
          .from('profiles')
          .update({'driver_gender_preference': preference.value})
          .eq('id', userId);

      developer.log(
        '✅ Updated driver preference: ${preference.value}',
        name: 'GenderMatching',
      );
    } catch (e) {
      developer.log(
        'Error updating driver preference: $e',
        name: 'GenderMatching',
      );
      rethrow;
    }
  }
}
