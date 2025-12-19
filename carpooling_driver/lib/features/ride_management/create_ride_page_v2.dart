import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'dart:developer' as developer;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:carpooling_driver/services/driver_profile_service.dart';
import 'package:carpooling_driver/services/penalty_service.dart';
import 'package:carpooling_driver/widgets/route_preview_widget.dart';
import 'package:carpooling_driver/features/driver_verification/driver_verification_page.dart';
import 'package:carpooling_driver/features/notifications/data/datasources/notification_service.dart';
import 'package:carpooling_driver/core/utils/timezone_helper.dart';

/// Create Ride Page V2 - with Google Maps-style route preview
class CreateRidePageV2 extends HookConsumerWidget {
  const CreateRidePageV2({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profileService = DriverProfileService();
    final penaltyService = PenaltyService();
    final supabase = Supabase.instance.client;
    
    final seatsController = useTextEditingController(text: '4');
    final notesController = useTextEditingController();
    
    // Ride Type: 'immediate' or 'scheduled'
    final rideType = useState<String>('immediate');
    final selectedDate = useState<DateTime?>(null);
    final selectedTime = useState<TimeOfDay?>(null);
    final routeSelection = useState<RouteSelection?>(null);
    final profileStatus = useState<DriverProfileStatus?>(null);
    final isCheckingProfile = useState(true);
    final penaltyStatus = useState<PenaltyStatus?>(null);
    final hasActiveRide = useState<bool>(false);
    final errorMessage = useState<String?>(null);

    // Check profile, penalty, and active rides on load
    useEffect(() {
      Future.microtask(() async {
        try {
          final userId = supabase.auth.currentUser?.id;
          if (userId == null) return;

          // Check profile
          final status = await profileService.checkProfileCompletion();
          profileStatus.value = status;

          // Check for active penalty
          final penalty = await penaltyService.checkUserPenalty(userId);
          penaltyStatus.value = penalty;

          // Check for active "Start Now" rides (only allow ONE active immediate ride)
          final activeImmediateRides = await supabase
              .from('rides')
              .select('id, ride_type, ride_status')
              .eq('driver_id', userId)
              .eq('ride_type', 'immediate')
              .inFilter('ride_status', ['active', 'in_progress'])
              .eq('ride_completed', false);

          hasActiveRide.value = (activeImmediateRides as List).isNotEmpty;
          
          developer.log('Active immediate rides: ${(activeImmediateRides as List).length}', name: 'CreateRide');

          // Set error messages based on restrictions
          if (hasActiveRide.value) {
            errorMessage.value = '⚠️ You already have an active "Start Now" ride. Complete it before creating a new one.\n\n✅ You can still create scheduled rides!';
          } else if (penalty.hasActivePenalty) {
            errorMessage.value = penaltyService.getPenaltyMessage(penalty);
          }
        } catch (e) {
          developer.log('Error checking ride creation eligibility: $e', name: 'CreateRide');
          profileStatus.value = const DriverProfileStatus(
            isComplete: false,
            hasLicense: false,
            hasVehicle: false,
          );
        } finally {
          isCheckingProfile.value = false;
        }
      });
      return null;
    }, []);

    DateTime? scheduledDateTime() {
      // For immediate rides, use current time
      if (rideType.value == 'immediate') {
        return TimezoneHelper.nowInMalaysia();
      }
      
      // For scheduled rides, validate date/time selection
      if (selectedDate.value == null || selectedTime.value == null) return null;
      
      // Create DateTime in Malaysia timezone (UTC+8)
      final malaysiaDateTime = DateTime(
        selectedDate.value!.year,
        selectedDate.value!.month,
        selectedDate.value!.day,
        selectedTime.value!.hour,
        selectedTime.value!.minute,
      );
      
      // Validation for scheduled rides
      final now = TimezoneHelper.nowInMalaysia();
      final sevenDaysFromNow = now.add(const Duration(days: 7));
      
      if (malaysiaDateTime.isBefore(now)) {
        return null; // Can't schedule in the past
      }
      
      if (malaysiaDateTime.isAfter(sevenDaysFromNow)) {
        return null; // Can't schedule more than 7 days ahead
      }
      
      return malaysiaDateTime;
    }

    final schedTime = scheduledDateTime();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Create New Ride'),
            Text(
              'Google Maps-style preview',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
          ],
        ),
      ),
      body: isCheckingProfile.value
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Ride Type Selector
                Card(
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.directions_car, color: theme.colorScheme.primary),
                            const SizedBox(width: 8),
                            Text(
                              'Ride Type',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                              value: 'immediate',
                              label: Text('Start Now'),
                              icon: Icon(Icons.play_arrow),
                            ),
                            ButtonSegment(
                              value: 'scheduled',
                              label: Text('Schedule'),
                              icon: Icon(Icons.schedule),
                            ),
                          ],
                          selected: {rideType.value},
                          onSelectionChanged: (Set<String> newSelection) {
                            rideType.value = newSelection.first;
                            // Reset date/time when switching modes
                            if (rideType.value == 'immediate') {
                              selectedDate.value = null;
                              selectedTime.value = null;
                            }
                          },
                          style: ButtonStyle(
                            backgroundColor: WidgetStateProperty.resolveWith<Color>(
                              (Set<WidgetState> states) {
                                if (states.contains(WidgetState.selected)) {
                                  return theme.colorScheme.primaryContainer;
                                }
                                return theme.colorScheme.surface;
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          rideType.value == 'immediate'
                              ? '🚀 Start your ride immediately and be visible to nearby passengers'
                              : '📅 Schedule your ride up to 7 days in advance',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Penalty or Active Ride Banner
                // Only show for immediate rides if hasActiveRide, or always for penalty
                if (errorMessage.value != null && 
                    (penaltyStatus.value?.hasActivePenalty == true || 
                     (hasActiveRide.value && rideType.value == 'immediate')))
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.block, color: Colors.red.shade700),
                            const SizedBox(width: 8),
                            Text(
                              penaltyStatus.value?.hasActivePenalty == true
                                  ? 'Account Restricted'
                                  : 'Cannot Create "Start Now" Ride',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.red.shade700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          errorMessage.value!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.red.shade900,
                          ),
                        ),
                      ],
                    ),
                  )
                // Info banner for scheduled rides when hasActiveRide
                else if (hasActiveRide.value && rideType.value == 'scheduled')
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue.shade700),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'You have an active "Start Now" ride, but you can still schedule future rides!',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.blue.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                // Profile Status Banner
                else if (profileStatus.value != null && !profileStatus.value!.canCreateRides)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.orange.shade700,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Complete Your Driver Profile',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          profileService.getStatusMessage(profileStatus.value!),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.orange.shade900,
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const DriverVerificationPage(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.arrow_forward),
                          label: const Text('Complete Verification'),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.orange.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),

                // Info Card
                Card(
                  color: Colors.blue.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue.shade700),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Select locations to see route preview with real-time distance and duration.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.blue.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Date & Time Selection (Only for scheduled rides)
                if (rideType.value == 'scheduled') ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.schedule, color: theme.colorScheme.primary),
                              const SizedBox(width: 8),
                              Text(
                                'Schedule',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        const Divider(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: profileStatus.value?.canCreateRides == true
                                    ? () async {
                                        // Use Malaysia time for date picker
                                        final now = TimezoneHelper.nowInMalaysia();
                                        final date = await showDatePicker(
                                          context: context,
                                          initialDate: now,
                                          firstDate: now,
                                          lastDate: now.add(const Duration(days: 7)), // Max 7 days for scheduled rides
                                        );
                                        if (date != null) {
                                          selectedDate.value = date;
                                        }
                                      }
                                    : null,
                                icon: const Icon(Icons.calendar_today),
                                label: Text(
                                  selectedDate.value == null
                                      ? 'Select Date'
                                      : TimezoneHelper.formatMalaysiaDate(selectedDate.value!),
                                ),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.all(16),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: profileStatus.value?.canCreateRides == true
                                    ? () async {
                                        // Use Malaysia time for time picker
                                        final now = TimezoneHelper.nowInMalaysia();
                                        final initialTime = TimeOfDay(hour: now.hour, minute: now.minute);
                                        
                                        final time = await showTimePicker(
                                          context: context,
                                          initialTime: initialTime,
                                        );
                                        if (time != null && selectedDate.value != null) {
                                          // Create test datetime in Malaysia timezone
                                          final testDateTime = DateTime(
                                            selectedDate.value!.year,
                                            selectedDate.value!.month,
                                            selectedDate.value!.day,
                                            time.hour,
                                            time.minute,
                                          );
                                          
                                          // Validation: Must be in future and within 7 days
                                          final sevenDaysFromNow = now.add(const Duration(days: 7));
                                          if (testDateTime.isBefore(now)) {
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(
                                                  content: Text('⚠️ Please select a time in the future'),
                                                  backgroundColor: Colors.orange,
                                                  duration: Duration(seconds: 2),
                                                ),
                                              );
                                            }
                                            return;
                                          }
                                          if (testDateTime.isAfter(sevenDaysFromNow)) {
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(
                                                  content: Text('⚠️ Scheduled rides can only be created within 7 days'),
                                                  backgroundColor: Colors.orange,
                                                  duration: Duration(seconds: 2),
                                                ),
                                              );
                                            }
                                            return;
                                          }
                                          selectedTime.value = time;
                                        }
                                      }
                                    : null,
                                icon: const Icon(Icons.access_time),
                                label: Text(
                                  selectedTime.value == null
                                      ? 'Select Time'
                                      : selectedTime.value!.format(context),
                                ),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.all(16),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                  const SizedBox(height: 16),
                ],

                // Route Preview Widget (Google Maps Style)
                if (profileStatus.value?.canCreateRides == true &&
                    (rideType.value == 'immediate' || schedTime != null))
                  RoutePreviewWidget(
                    scheduledTime: schedTime ?? TimezoneHelper.nowInMalaysia(),
                    showFareCalculation: false, // DRIVER DOES NOT SEE FARES
                    onRouteSelected: (selection) {
                      routeSelection.value = selection;
                    },
                  )
                else
                  Card(
                    color: Colors.grey.shade100,
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          Icon(
                            Icons.map_outlined,
                            size: 64,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            (rideType.value == 'scheduled' && schedTime == null)
                                ? 'Select date and time first'
                                : 'Complete verification to continue',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: Colors.grey.shade600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),

                if (routeSelection.value != null) ...[
                  const SizedBox(height: 16),

                  // Additional Details
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.info_outline, color: theme.colorScheme.primary),
                              const SizedBox(width: 8),
                              Text(
                                'Ride Details',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 24),
                          
                          // Available Seats
                          TextField(
                            controller: seatsController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Available Seats',
                              hintText: '1-4 seats',
                              helperText: 'Max 4 passenger seats (excluding driver)',
                              prefixIcon: Icon(Icons.event_seat),
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Notes
                          TextField(
                            controller: notesController,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              labelText: 'Notes (Optional)',
                              hintText: 'Any additional information...',
                              prefixIcon: Icon(Icons.notes),
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Create Ride Button
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () async {
                        // Check if trying to create immediate ride when already have one
                        if (hasActiveRide.value && rideType.value == 'immediate') {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('⚠️ You already have an active "Start Now" ride. Complete it first or create a scheduled ride instead.'),
                              backgroundColor: Colors.orange,
                              duration: Duration(seconds: 3),
                            ),
                          );
                          return;
                        }
                        
                        // Check for penalty
                        if (penaltyStatus.value?.hasActivePenalty == true) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(penaltyService.getPenaltyMessage(penaltyStatus.value!)),
                              backgroundColor: Colors.red,
                              duration: const Duration(seconds: 3),
                            ),
                          );
                          return;
                        }
                        
                        // Validate seats
                        final seats = int.tryParse(seatsController.text);
                        if (seats == null || seats < 1 || seats > 4) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Seats must be between 1 and 4'),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }

                        final supabase = Supabase.instance.client;
                        final userId = supabase.auth.currentUser?.id;
                        
                        if (userId == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('User not authenticated'),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }

                        try {
                          // Validate route selection
                          if (routeSelection.value == null) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('⚠️ Please select from and to locations'),
                                  backgroundColor: Colors.orange,
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            }
                            return;
                          }
                          
                          // For scheduled rides, validate time
                          if (rideType.value == 'scheduled') {
                            final now = TimezoneHelper.nowInMalaysia();
                            if (schedTime == null || schedTime.isBefore(now)) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('⚠️ Please select a future date and time'),
                                    backgroundColor: Colors.orange,
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              }
                              return;
                            }

                            // Check minimum 30 minutes, maximum 7 days
                            final earliestAllowed = now.add(const Duration(minutes: 30));
                            final latestAllowed = now.add(const Duration(days: 7));
                            
                            if (schedTime.isBefore(earliestAllowed)) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('⚠️ Scheduled rides must start at least 30 minutes from now'),
                                    backgroundColor: Colors.orange,
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              }
                              return;
                            }

                            if (schedTime.isAfter(latestAllowed)) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('⚠️ Scheduled rides cannot be more than 7 days in advance'),
                                    backgroundColor: Colors.orange,
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              }
                              return;
                            }

                            // Check for active rides - cannot schedule within 2 hours before active ride
                            final activeRides = await supabase
                                .from('rides')
                                .select('scheduled_time, ride_status')
                                .eq('driver_id', userId)
                                .inFilter('ride_status', ['active', 'in_progress'])
                                .eq('ride_completed', false);

                            for (final activeRide in activeRides) {
                              final activeTimeUtc = DateTime.parse(activeRide['scheduled_time'] as String).toUtc();
                              final activeTime = TimezoneHelper.utcToMalaysia(activeTimeUtc);
                              final twoHoursBeforeActive = activeTime.subtract(const Duration(hours: 2));
                              
                              if (schedTime.isAfter(twoHoursBeforeActive) && schedTime.isBefore(activeTime)) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('⚠️ Cannot schedule ride within 2 hours before your active ride (${TimezoneHelper.formatMalaysiaDateTime(activeTime)})'),
                                      backgroundColor: Colors.orange,
                                      duration: const Duration(seconds: 3),
                                    ),
                                  );
                                }
                                return;
                              }
                            }

                            // Check for overlapping scheduled rides - cannot create at same time or around that time
                            final existingScheduledRides = await supabase
                                .from('rides')
                                .select('scheduled_time, id')
                                .eq('driver_id', userId)
                                .eq('ride_status', 'scheduled')
                                .neq('ride_completed', true);

                            // Define time window for overlap check (30 minutes before/after)
                            const overlapWindow = Duration(minutes: 30);
                            
                            for (final existingRide in existingScheduledRides) {
                              final existingTimeUtc = DateTime.parse(existingRide['scheduled_time'] as String).toUtc();
                              final existingTime = TimezoneHelper.utcToMalaysia(existingTimeUtc);
                              
                              // Check if new ride time overlaps with existing ride time
                              final timeDifference = (schedTime.difference(existingTime)).abs();
                              if (timeDifference < overlapWindow) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('⚠️ You already have a scheduled ride at ${TimezoneHelper.formatMalaysiaDateTime(existingTime)}. Please choose a different time (at least 30 minutes apart).'),
                                      backgroundColor: Colors.orange,
                                      duration: const Duration(seconds: 3),
                                    ),
                                  );
                                }
                                return;
                              }
                            }
                          }
                          
                          // Save ride to database
                          // Note: No fare for driver - passengers calculate their own fares
                          
                          // Convert Malaysia time (UTC+8) to UTC for database storage
                          final finalScheduledTime = schedTime ?? TimezoneHelper.nowInMalaysia();
                          final schedTimeUtc = TimezoneHelper.malaysiaToUtc(finalScheduledTime);
                          
                          final rideData = {
                            'driver_id': userId,
                            'from_location': routeSelection.value!.from.displayName,
                            'to_location': routeSelection.value!.to.displayName,
                            'from_lat': routeSelection.value!.from.latitude,
                            'from_lng': routeSelection.value!.from.longitude,
                            'to_lat': routeSelection.value!.to.latitude,
                            'to_lng': routeSelection.value!.to.longitude,
                            'scheduled_time': schedTimeUtc.toIso8601String(), // Store in UTC
                            'price_per_seat': 0.0, // No driver price - passengers calculate their own fares
                            'available_seats': seats,
                            'ride_type': rideType.value, // 'immediate' or 'scheduled'
                            'ride_status': rideType.value == 'immediate' ? 'active' : 'scheduled',
                            'is_activated': rideType.value == 'immediate', // Immediate rides are auto-activated
                            'ride_notes': 'Distance: ${routeSelection.value!.distance.distanceKm.toStringAsFixed(1)}km, Duration: ${routeSelection.value!.distance.durationMinutes}min',
                          };

                          print('🚗 Creating ${rideType.value} ride (Malaysia UTC+8):');
                          print('   📍 Route: ${routeSelection.value!.from.displayName} → ${routeSelection.value!.to.displayName}');
                          print('   ⏰ Malaysia time: ${TimezoneHelper.formatMalaysiaDateTime(finalScheduledTime)}');
                          print('   🌍 UTC time: ${TimezoneHelper.formatMalaysiaDateTime(schedTimeUtc)}');
                          print('   💺 Seats: $seats');
                          print('   🎯 Type: ${rideType.value}');
                          
                          await supabase.from('rides').insert(rideData);

                          // Send notification
                          try {
                            developer.log('Attempting to create notification...', name: 'CreateRide');
                            final notificationService = NotificationService();
                            final notificationMessage = rideType.value == 'immediate'
                                ? 'Your ride from ${routeSelection.value!.from.displayName} to ${routeSelection.value!.to.displayName} is now live! Passengers can join immediately.'
                                : 'Your ride from ${routeSelection.value!.from.displayName} to ${routeSelection.value!.to.displayName} is scheduled for ${TimezoneHelper.formatMalaysiaDateTime(finalScheduledTime)}. Passengers can book in advance.';
                            await notificationService.createNotification(
                              userId: userId,
                              title: rideType.value == 'immediate' ? 'Ride Started! 🚗' : 'Ride Scheduled! 📅',
                              message: notificationMessage,
                              type: 'ride_created',
                            );
                            developer.log('✅ Notification created successfully!', name: 'CreateRide');
                          } catch (e, stackTrace) {
                            // Show visible error to user
                            developer.log('❌ Failed to send notification: $e', name: 'CreateRide', error: e, stackTrace: stackTrace);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('⚠️ Ride created but notification failed: ${e.toString().split('\n').first}'),
                                  backgroundColor: Colors.orange,
                                  duration: const Duration(seconds: 5),
                                  action: SnackBarAction(
                                    label: 'Details',
                                    textColor: Colors.white,
                                    onPressed: () {
                                      developer.log('Notification error details: $e\n$stackTrace', name: 'CreateRide');
                                    },
                                  ),
                                ),
                              );
                            }
                          }

                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      rideType.value == 'immediate' ? '✅ Ride Started!' : '✅ Ride Scheduled!',
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 4),
                                    Text('Route: ${routeSelection.value!.distance.distanceDisplay}'),
                                    Text('Duration: ${routeSelection.value!.distance.durationDisplay}'),
                                    if (rideType.value == 'scheduled')
                                      Text('Scheduled: ${TimezoneHelper.formatMalaysiaDateTime(finalScheduledTime)}'),
                                  ],
                                ),
                                backgroundColor: Colors.green,
                                duration: const Duration(seconds: 4),
                              ),
                            );
                            Navigator.pop(context);
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error creating ride: ${e.toString()}'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                      icon: Icon(rideType.value == 'immediate' ? Icons.play_arrow : Icons.schedule),
                      label: Text(rideType.value == 'immediate' ? 'Start Ride Now' : 'Schedule Ride'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.all(20),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}

