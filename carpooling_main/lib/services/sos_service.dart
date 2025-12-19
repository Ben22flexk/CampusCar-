import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:developer' as developer;

class SosSmsDraft {
  final List<String> recipients;
  final String body;

  const SosSmsDraft({
    required this.recipients,
    required this.body,
  });
}

class SosTriggerResult {
  final String sosId;
  final SosSmsDraft? smsDraft;

  const SosTriggerResult({
    required this.sosId,
    required this.smsDraft,
  });
}

/// Service to handle SOS/emergency events
class SosService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Trigger an SOS event with current location and ride details
  Future<SosTriggerResult> triggerSos({
    String? rideId,
    String? bookingId,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      // Get current location
      Position? position;
      String? locationAddress;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );

        // Reverse geocode to get address
        try {
          final placemarks = await placemarkFromCoordinates(
            position.latitude,
            position.longitude,
          );
          if (placemarks.isNotEmpty) {
            final place = placemarks.first;
            locationAddress = _formatAddress(place);
          }
        } catch (e) {
          developer.log('Error reverse geocoding: $e', name: 'SosService');
          locationAddress = '${position.latitude}, ${position.longitude}';
        }
      } catch (e) {
        developer.log('Error getting location: $e', name: 'SosService');
        // Continue without location if GPS fails
      }

      // Call database function to create SOS event
      final result = await _supabase.rpc(
        'trigger_sos_event',
        params: {
          'p_ride_id': rideId,
          'p_booking_id': bookingId,
          'p_location_lat': position?.latitude,
          'p_location_lng': position?.longitude,
          'p_location_address': locationAddress,
        },
      );

      final sosId = result as String;
      developer.log('✅ SOS event triggered: $sosId', name: 'SosService');

      // Send notifications to emergency contacts
      final smsDraft = await _notifyEmergencyContacts(
        userId,
        sosId,
        rideId: rideId,
        bookingId: bookingId,
        position: position,
        locationAddress: locationAddress,
      );

      return SosTriggerResult(sosId: sosId, smsDraft: smsDraft);
    } catch (e) {
      developer.log('❌ Error triggering SOS: $e', name: 'SosService');
      rethrow;
    }
  }

  /// Notify emergency contacts about SOS event
  Future<SosSmsDraft?> _notifyEmergencyContacts(
    String userId,
    String sosId,
    {
    required String? rideId,
    required String? bookingId,
    required Position? position,
    required String? locationAddress,
  }
  ) async {
    try {
      // Get user's emergency contact info
      final profile = await _supabase
          .from('profiles')
          .select(
            'emergency_contact_name, '
            'emergency_contact_phone, '
            'campus_security_phone, '
            'full_name',
          )
          .eq('id', userId)
          .single();

      final emergencyName = profile['emergency_contact_name'] as String?;
      final emergencyPhone = profile['emergency_contact_phone'] as String?;
      final campusSecurityPhone = profile['campus_security_phone'] as String?;
      final userName = profile['full_name'] as String? ?? 'User';

      // Create notification records (these can trigger SMS/email via webhooks)
      final notifications = <Map<String, dynamic>>[];

      if (emergencyName != null && emergencyPhone != null) {
        notifications.add({
          'user_id': userId,
          'title': '🚨 SOS Alert',
          'message':
              '$userName has triggered an SOS. Location: ${locationAddress ?? "Unknown"}. '
              'Please check on them immediately.',
          'type': 'sos_alert',
          'related_id': sosId,
          'is_read': false,
        });
      }

      if (campusSecurityPhone != null) {
        notifications.add({
          'user_id': userId,
          'title': '🚨 Campus Security Alert',
          'message':
              'SOS triggered by $userName. Location: ${locationAddress ?? "Unknown"}. '
              'SOS ID: $sosId',
          'type': 'sos_security',
          'related_id': sosId,
          'is_read': false,
        });
      }

      if (notifications.isNotEmpty) {
        await _supabase.from('notifications').insert(notifications);
        developer.log(
          '✅ Emergency notifications created',
          name: 'SosService',
        );
      }

      final smsDraft = _buildSmsDraft(
        userName: userName,
        emergencyPhone: emergencyPhone,
        campusSecurityPhone: campusSecurityPhone,
        sosId: sosId,
        rideId: rideId,
        bookingId: bookingId,
        position: position,
        locationAddress: locationAddress,
      );

      return smsDraft;
    } catch (e) {
      developer.log(
        '⚠️ Error notifying emergency contacts: $e',
        name: 'SosService',
      );
      // Don't throw - SOS should still be recorded even if notifications fail
      return null;
    }
  }

  SosSmsDraft? _buildSmsDraft({
    required String userName,
    required String? emergencyPhone,
    required String? campusSecurityPhone,
    required String sosId,
    required String? rideId,
    required String? bookingId,
    required Position? position,
    required String? locationAddress,
  }) {
    final recipients = <String?>[
      emergencyPhone,
      campusSecurityPhone,
    ]
        .whereType<String>()
        .map(_normalizePhone)
        .where((e) => e.isNotEmpty)
        .toList();

    if (recipients.isEmpty) {
      return null;
    }

    final lat = position?.latitude;
    final lng = position?.longitude;
    final mapsLink = (lat != null && lng != null)
        ? 'https://www.google.com/maps?q=$lat,$lng'
        : null;

    final body = StringBuffer()
      ..writeln('🚨 SOS ALERT')
      ..writeln('$userName triggered an SOS.')
      ..writeln('')
      ..writeln('Location: ${locationAddress ?? "Unknown"}')
      ..writeln(mapsLink != null ? 'Map: $mapsLink' : '')
      ..writeln('SOS ID: $sosId')
      ..writeln(rideId != null ? 'Ride ID: $rideId' : '')
      ..writeln(bookingId != null ? 'Booking ID: $bookingId' : '');

    return SosSmsDraft(
      recipients: recipients,
      body: body.toString().trim(),
    );
  }

  String _normalizePhone(String input) {
    var formatted = input.replaceAll(RegExp(r'[^\d+]'), '');
    if (formatted.isEmpty) return '';

    if (!formatted.startsWith('+')) {
      if (formatted.startsWith('60')) {
        formatted = '+$formatted';
      } else if (formatted.startsWith('0')) {
        formatted = '+60${formatted.substring(1)}';
      } else {
        formatted = '+60$formatted';
      }
    }

    return formatted;
  }

  /// Opens the device SMS app with prefilled recipients + message.
  /// Returns true if an SMS app could be launched.
  Future<bool> launchSmsComposer(SosSmsDraft draft) async {
    if (draft.recipients.isEmpty) return false;

    final recipients = draft.recipients.join(',');
    final encodedBody = Uri.encodeComponent(draft.body);

    // Android typically supports `?body=...`, while some iOS builds prefer `&body=...`.
    final uriQuestion = Uri.parse('sms:$recipients?body=$encodedBody');
    if (await canLaunchUrl(uriQuestion)) {
      return launchUrl(uriQuestion, mode: LaunchMode.externalApplication);
    }

    final uriAmp = Uri.parse('sms:$recipients&body=$encodedBody');
    if (await canLaunchUrl(uriAmp)) {
      return launchUrl(uriAmp, mode: LaunchMode.externalApplication);
    }

    developer.log('⚠️ Unable to launch SMS app', name: 'SosService');
    return false;
  }

  /// Resolve an SOS event
  Future<void> resolveSos(String sosId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      await _supabase
          .from('sos_events')
          .update({
            'status': 'resolved',
            'resolved_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', sosId)
          .eq('user_id', userId);

      developer.log('✅ SOS event resolved: $sosId', name: 'SosService');
    } catch (e) {
      developer.log('❌ Error resolving SOS: $e', name: 'SosService');
      rethrow;
    }
  }

  /// Get active SOS events for current user
  Future<List<Map<String, dynamic>>> getActiveSosEvents() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        return [];
      }

      final response = await _supabase
          .from('sos_events')
          .select()
          .eq('user_id', userId)
          .eq('status', 'active')
          .order('triggered_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      developer.log('Error getting SOS events: $e', name: 'SosService');
      return [];
    }
  }

  String _formatAddress(Placemark place) {
    final parts = <String>[];
    if (place.street != null) parts.add(place.street!);
    if (place.subLocality != null) parts.add(place.subLocality!);
    if (place.locality != null) parts.add(place.locality!);
    if (place.administrativeArea != null) {
      parts.add(place.administrativeArea!);
    }
    if (place.postalCode != null) parts.add(place.postalCode!);
    return parts.join(', ');
  }
}
