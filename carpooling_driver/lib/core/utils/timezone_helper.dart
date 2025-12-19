import 'package:intl/intl.dart';

/// Malaysia Timezone Helper (UTC+8)
class TimezoneHelper {
  static const int malaysiaOffsetHours = 8;
  
  /// Get current Malaysia time (UTC+8)
  static DateTime nowInMalaysia() {
    final utcNow = DateTime.now().toUtc();
    return utcNow.add(const Duration(hours: malaysiaOffsetHours));
  }
  
  /// Convert UTC to Malaysia time
  static DateTime utcToMalaysia(DateTime utcTime) {
    return utcTime.add(const Duration(hours: malaysiaOffsetHours));
  }
  
  /// Convert Malaysia time to UTC for database storage
  static DateTime malaysiaToUtc(DateTime malaysiaTime) {
    return malaysiaTime.subtract(const Duration(hours: malaysiaOffsetHours));
  }
  
  /// Format Malaysia time for display (12-hour format with AM/PM)
  static String formatMalaysiaTime(DateTime malaysiaTime) {
    return DateFormat('hh:mm a').format(malaysiaTime);
  }
  
  /// Format Malaysia date and time
  static String formatMalaysiaDateTime(DateTime malaysiaTime) {
    return DateFormat('dd/MM/yyyy hh:mm a').format(malaysiaTime);
  }
  
  /// Format Malaysia date only
  static String formatMalaysiaDate(DateTime malaysiaTime) {
    return DateFormat('dd/MM/yyyy').format(malaysiaTime);
  }
  
  /// Check if a time is within allowed advance booking window (30 min - 2 hours)
  static bool isValidAdvanceBooking(DateTime scheduledTime) {
    final now = nowInMalaysia();
    final difference = scheduledTime.difference(now);
    
    // Must be between 30 minutes and 2 hours in the future
    return difference.inMinutes >= 30 && difference.inMinutes <= 120;
  }
  
  /// Get minimum allowed booking time (30 minutes from now)
  static DateTime getMinimumBookingTime() {
    return nowInMalaysia().add(const Duration(minutes: 30));
  }
  
  /// Get maximum allowed booking time (2 hours from now)
  static DateTime getMaximumBookingTime() {
    return nowInMalaysia().add(const Duration(hours: 2));
  }
  
  /// Get human-readable advance booking validation message
  static String getAdvanceBookingMessage(DateTime scheduledTime) {
    final now = nowInMalaysia();
    final difference = scheduledTime.difference(now);
    
    if (difference.inMinutes < 30) {
      final minutesNeeded = 30 - difference.inMinutes;
      return 'Ride must be scheduled at least 30 minutes in advance. Add $minutesNeeded more minutes.';
    } else if (difference.inMinutes > 120) {
      final minutesOver = difference.inMinutes - 120;
      return 'Ride cannot be scheduled more than 2 hours in advance. Reduce by $minutesOver minutes.';
    }
    
    return 'Valid booking time';
  }
}

