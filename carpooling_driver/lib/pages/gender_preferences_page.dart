import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:carpooling_driver/models/gender_preferences.dart';
import 'package:carpooling_driver/services/gender_matching_service.dart';
import 'dart:developer' as developer;

/// Page for setting gender and matching preferences (Driver App)
class DriverGenderPreferencesPage extends HookConsumerWidget {
  const DriverGenderPreferencesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isLoading = useState<bool>(true);
    final isSaving = useState<bool>(false);
    
    final gender = useState<Gender?>(null);
    final driverPreference = useState<DriverGenderPreference>(
      DriverGenderPreference.noPreference,
    );

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
              .select('gender, driver_gender_preference')
              .eq('id', userId)
              .single();

          gender.value = Gender.fromString(profile['gender']);
          driverPreference.value = DriverGenderPreference.fromString(
            profile['driver_gender_preference'],
          )!;

          isLoading.value = false;
        } catch (e) {
          developer.log('Error loading preferences: $e', name: 'DriverGenderPrefs');
          isLoading.value = false;
        }
      });
      return null;
    }, []);

    if (isLoading.value) {
      return Scaffold(
        appBar: AppBar(title: const Text('Gender & Matching Preferences')),
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
                        'Set your gender and preferences for accepting passengers. '
                        'This helps create a safer matching experience.',
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
              'This helps passengers find compatible drivers',
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

            // Driver preferences
            Text(
              'Passenger Acceptance Preferences',
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

                          // Update driver preference
                          await genderService.updateDriverPreference(
                            userId: userId,
                            preference: driverPreference.value,
                          );

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
                              name: 'DriverGenderPrefs');
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

  String _getDriverPreferenceDescription(DriverGenderPreference preference) {
    switch (preference) {
      case DriverGenderPreference.womenNonBinaryOnly:
        return 'Only accept booking requests from women and non-binary passengers';
      case DriverGenderPreference.noPreference:
        return 'Accept booking requests from all passengers';
    }
  }
}
