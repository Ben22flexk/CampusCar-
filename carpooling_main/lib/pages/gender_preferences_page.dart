import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:carpooling_main/models/gender_preferences.dart';
import 'package:carpooling_main/services/gender_matching_service.dart';
import 'dart:developer' as developer;

/// Page for setting gender and matching preferences
class GenderPreferencesPage extends HookConsumerWidget {
  const GenderPreferencesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isLoading = useState<bool>(true);
    final isSaving = useState<bool>(false);
    
    final gender = useState<Gender?>(null);
    final passengerPreference = useState<PassengerGenderPreference>(
      PassengerGenderPreference.noPreference,
    );
    final driverPreference = useState<DriverGenderPreference>(
      DriverGenderPreference.noPreference,
    );
    final userRole = useState<String?>(null);

    final genderService = GenderMatchingService();
    final supabase = Supabase.instance.client;

    // Load current preferences
    useEffect(() {
      Future.microtask(() async {
        try {
          final userId = supabase.auth.currentUser?.id;
          if (userId == null) return;

          final profile = await supabase
              .from('profiles')
              .select('gender, passenger_gender_preference, '
                  'driver_gender_preference, role')
              .eq('id', userId)
              .single();

          gender.value = Gender.fromString(profile['gender']);
          passengerPreference.value = PassengerGenderPreference.fromString(
            profile['passenger_gender_preference'],
          )!;
          driverPreference.value = DriverGenderPreference.fromString(
            profile['driver_gender_preference'],
          )!;
          userRole.value = profile['role'] as String?;

          isLoading.value = false;
        } catch (e) {
          developer.log('Error loading preferences: $e', name: 'GenderPrefs');
          isLoading.value = false;
        }
      });
      return null;
    }, []);

    if (isLoading.value) {
      return Scaffold(
        appBar: AppBar(title: const Text('Gender Preferences')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gender & Matching Preferences'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info card
            Card(
              color: theme.colorScheme.primaryContainer.withOpacity(0.3),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Set your preferences for safer matching. '
                        'These help us find rides that match your comfort level.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Gender selection
            Text(
              'Your Gender',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This helps us match you with compatible drivers/passengers',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 12),
            ...Gender.values.map((g) => RadioListTile<Gender>(
                  title: Text(_getGenderLabel(g)),
                  value: g,
                  groupValue: gender.value,
                  onChanged: (value) {
                    if (value != null) gender.value = value;
                  },
                )),
            const SizedBox(height: 24),

            // Passenger preferences (for all users)
            Text(
              'Passenger Preferences',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'When booking rides, I prefer:',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 12),
            ...PassengerGenderPreference.values.map((p) => RadioListTile<
                    PassengerGenderPreference>(
                  title: Text(p.displayName),
                  subtitle: Text(_getPassengerPreferenceDescription(p)),
                  value: p,
                  groupValue: passengerPreference.value,
                  onChanged: (value) {
                    if (value != null) passengerPreference.value = value;
                  },
                )),
            const SizedBox(height: 24),

            // Driver preferences (only for drivers)
            if (userRole.value == 'driver') ...[
              Text(
                'Driver Preferences',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'When accepting passengers, I prefer:',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 12),
              ...DriverGenderPreference.values.map((d) => RadioListTile<
                      DriverGenderPreference>(
                    title: Text(d.displayName),
                    subtitle: Text(_getDriverPreferenceDescription(d)),
                    value: d,
                    groupValue: driverPreference.value,
                    onChanged: (value) {
                      if (value != null) driverPreference.value = value;
                    },
                  )),
              const SizedBox(height: 24),
            ],

            // Save button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isSaving.value
                    ? null
                    : () async {
                        isSaving.value = true;
                        try {
                          final userId = supabase.auth.currentUser?.id;
                          if (userId == null) {
                            throw Exception('User not authenticated');
                          }

                          // Update gender
                          if (gender.value != null) {
                            await genderService.updateUserGender(
                              userId: userId,
                              gender: gender.value!,
                            );
                          }

                          // Update passenger preference
                          await genderService.updatePassengerPreference(
                            userId: userId,
                            preference: passengerPreference.value,
                          );

                          // Update driver preference if user is a driver
                          if (userRole.value == 'driver') {
                            await genderService.updateDriverPreference(
                              userId: userId,
                              preference: driverPreference.value,
                            );
                          }

                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Preferences saved successfully!'),
                                backgroundColor: Colors.green,
                              ),
                            );
                            Navigator.pop(context);
                          }
                        } catch (e) {
                          developer.log('Error saving preferences: $e',
                              name: 'GenderPrefs');
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error: ${e.toString()}'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        } finally {
                          isSaving.value = false;
                        }
                      },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: isSaving.value
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save Preferences'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getGenderLabel(Gender gender) {
    switch (gender) {
      case Gender.male:
        return 'Male';
      case Gender.female:
        return 'Female';
      case Gender.nonBinary:
        return 'Non-Binary';
      case Gender.preferNotToSay:
        return 'Prefer Not to Say';
    }
  }

  String _getPassengerPreferenceDescription(
      PassengerGenderPreference preference) {
    switch (preference) {
      case PassengerGenderPreference.femaleOnly:
        return 'Only show rides with female drivers';
      case PassengerGenderPreference.sameGenderOnly:
        return 'Only show rides with drivers of the same gender';
      case PassengerGenderPreference.noPreference:
        return 'Show all available rides';
    }
  }

  String _getDriverPreferenceDescription(DriverGenderPreference preference) {
    switch (preference) {
      case DriverGenderPreference.womenNonBinaryOnly:
        return 'Only accept booking requests from women and non-binary passengers';
      case DriverGenderPreference.noPreference:
        return 'Accept booking requests from all passengers';
    }
  }
}
