import 'dart:math';
import 'dart:developer' as developer;

/// Fare Calculation Service for Student Carpooling
/// Implements Grab-style pricing with 40% student discount and surge pricing
class FareCalculationService {
  // Base rates (Malaysian Ringgit)
  static const double _minimumFare = 6.00; // Minimum fare (realistic for short trips)
  static const double _studentDiscountRate = 0.60; // 40% off = 60% of price
  
  // Surge multipliers for peak times in Malaysia
  static const double _normalMultiplier = 1.0;
  static const double _moderateSurgeMultiplier = 1.3;
  static const double _highSurgeMultiplier = 1.5;
  static const double _extremeSurgeMultiplier = 2.0;
  
  /// Calculate student fare based on distance
  /// Returns the fare in Malaysian Ringgit (RM)
  double calculateStudentFare({
    required double distanceInKm,
    DateTime? tripDateTime,
  }) {
    // Calculate base Grab-style fare
    double grabFare = _calculateGrabFare(distanceInKm);
    
    // Apply student discount (40% off)
    double studentFare = grabFare * _studentDiscountRate;
    
    // Apply surge pricing if applicable
    double surgeMultiplier = _getSurgeMultiplier(tripDateTime ?? DateTime.now());
    if (surgeMultiplier > 1.0) {
      studentFare *= surgeMultiplier;
      developer.log(
        '📈 Surge pricing applied: ${surgeMultiplier}x',
        name: 'FareCalculation',
      );
    }
    
    // Ensure minimum fare
    studentFare = max(studentFare, _minimumFare);
    
    developer.log(
      '💰 Fare calculated: RM ${studentFare.toStringAsFixed(2)} '
      '(Distance: ${distanceInKm.toStringAsFixed(2)}km, '
      'Surge: ${surgeMultiplier}x)',
      name: 'FareCalculation',
    );
    
    return studentFare;
  }
  
  /// Calculate base Grab-style fare (before student discount)
  /// More realistic pricing based on Malaysian Grab rates
  double _calculateGrabFare(double distanceInKm) {
    // Base fare (covers first 1km)
    double baseFare = 4.00;
    double fare = baseFare;
    
    // Remaining distance after base
    double remainingDistance = max(0, distanceInKm - 1.0);
    
    if (remainingDistance <= 0) {
      // Very short trip (< 1km)
      return baseFare;
    } else if (distanceInKm <= 10.0) {
      // 1-10km: RM 1.80/km (typical city rates)
      fare += remainingDistance * 1.80;
    } else if (distanceInKm <= 20.0) {
      // 10-20km: slightly discounted
      fare += (9.0 * 1.80); // First 9km after base
      fare += ((distanceInKm - 10.0) * 1.50);
    } else if (distanceInKm <= 35.0) {
      // 20-35km: further discount for longer trips
      fare += (9.0 * 1.80); // 1-10km
      fare += (10.0 * 1.50); // 10-20km
      fare += ((distanceInKm - 20.0) * 1.20);
    } else {
      // Over 35km: maximum discount
      fare += (9.0 * 1.80);
      fare += (10.0 * 1.50);
      fare += (15.0 * 1.20);
      fare += ((distanceInKm - 35.0) * 1.00);
    }
    
    return fare;
  }
  
  /// Determine surge multiplier based on Malaysian peak times
  double _getSurgeMultiplier(DateTime dateTime) {
    final hour = dateTime.hour;
    final dayOfWeek = dateTime.weekday;
    final isWeekday = dayOfWeek >= 1 && dayOfWeek <= 5; // Monday to Friday
    
    // Malaysian peak hours
    final isMorningRush = hour >= 7 && hour <= 9; // 7 AM - 9 AM
    final isEveningRush = hour >= 17 && hour <= 19; // 5 PM - 7 PM
    final isLateNight = hour >= 23 || hour <= 2; // 11 PM - 2 AM
    final isLunchTime = hour >= 12 && hour <= 14; // 12 PM - 2 PM
    
    // Extreme surge: Weekday peak hours
    if (isWeekday && (isMorningRush || isEveningRush)) {
      return _extremeSurgeMultiplier;
    }
    
    // High surge: Late night (safety premium)
    if (isLateNight) {
      return _highSurgeMultiplier;
    }
    
    // Moderate surge: Lunch time on weekdays
    if (isWeekday && isLunchTime) {
      return _moderateSurgeMultiplier;
    }
    
    // Weekend evening surge
    if (!isWeekday && isEveningRush) {
      return _moderateSurgeMultiplier;
    }
    
    // Normal pricing
    return _normalMultiplier;
  }
  
  /// Get surge information as human-readable string
  String getSurgeInfo(DateTime dateTime) {
    double multiplier = _getSurgeMultiplier(dateTime);
    
    if (multiplier >= _extremeSurgeMultiplier) {
      return '🔥 High Demand - ${multiplier}x';
    } else if (multiplier >= _highSurgeMultiplier) {
      return '⚡ Increased Demand - ${multiplier}x';
    } else if (multiplier >= _moderateSurgeMultiplier) {
      return '📊 Moderate Demand - ${multiplier}x';
    } else {
      return '✅ Normal Pricing';
    }
  }
  
  /// Check if current time is peak time
  bool isPeakTime(DateTime dateTime) {
    return _getSurgeMultiplier(dateTime) > 1.0;
  }
  
  /// Format fare as Malaysian Ringgit string
  String formatFare(double fare) {
    return 'RM ${fare.toStringAsFixed(2)}';
  }
  
  /// Calculate total fare for multiple seats
  double calculateTotalFare({
    required double farePerSeat,
    required int numberOfSeats,
  }) {
    return farePerSeat * numberOfSeats;
  }
}

