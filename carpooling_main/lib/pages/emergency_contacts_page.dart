import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:developer' as developer;

/// Page for managing emergency contacts
class EmergencyContactsPage extends HookConsumerWidget {
  const EmergencyContactsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isLoading = useState<bool>(true);
    final isSaving = useState<bool>(false);
    
    final emergencyNameController = useTextEditingController();
    final emergencyPhoneController = useTextEditingController();
    final emergencyRelationshipController = useTextEditingController();
    final campusSecurityController = useTextEditingController();

    final supabase = Supabase.instance.client;

    // Load current emergency contacts
    useEffect(() {
      Future.microtask(() async {
        try {
          final userId = supabase.auth.currentUser?.id;
          if (userId == null) return;

          final profile = await supabase
              .from('profiles')
              .select(
                'emergency_contact_name, '
                'emergency_contact_phone, '
                'emergency_contact_relationship, '
                'campus_security_phone',
              )
              .eq('id', userId)
              .single();

          emergencyNameController.text =
              profile['emergency_contact_name'] as String? ?? '';
          emergencyPhoneController.text =
              profile['emergency_contact_phone'] as String? ?? '';
          emergencyRelationshipController.text =
              profile['emergency_contact_relationship'] as String? ?? '';
          campusSecurityController.text =
              profile['campus_security_phone'] as String? ?? '+60123456789';

          isLoading.value = false;
        } catch (e) {
          developer.log('Error loading contacts: $e', name: 'EmergencyContacts');
          isLoading.value = false;
        }
      });
      return null;
    }, []);

    if (isLoading.value) {
      return Scaffold(
        appBar: AppBar(title: const Text('Emergency Contacts')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency Contacts'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info card
            Card(
              color: theme.colorScheme.errorContainer.withOpacity(0.3),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'These contacts will be notified if you trigger an SOS. '
                        'Make sure the information is up to date.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Emergency Contact Section
            Text(
              'Emergency Contact',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'A trusted person who will be notified in case of emergency',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: emergencyNameController,
              decoration: const InputDecoration(
                labelText: 'Contact Name',
                hintText: 'e.g., Parent, Sibling, Friend',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: emergencyPhoneController,
              decoration: const InputDecoration(
                labelText: 'Phone Number',
                hintText: '+60123456789',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone),
                prefixText: '+60 ',
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: emergencyRelationshipController,
              decoration: const InputDecoration(
                labelText: 'Relationship',
                hintText: 'e.g., Parent, Sibling, Friend',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.family_restroom),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 32),

            // Campus Security Section
            Text(
              'Campus Security',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Campus security phone number (default provided)',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: campusSecurityController,
              decoration: const InputDecoration(
                labelText: 'Campus Security Phone',
                hintText: '+60123456789',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.security),
                prefixText: '+60 ',
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 32),

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

                          await supabase
                              .from('profiles')
                              .update({
                                'emergency_contact_name':
                                    emergencyNameController.text.isEmpty
                                        ? null
                                        : emergencyNameController.text,
                                'emergency_contact_phone':
                                    emergencyPhoneController.text.isEmpty
                                        ? null
                                        : emergencyPhoneController.text,
                                'emergency_contact_relationship':
                                    emergencyRelationshipController.text.isEmpty
                                        ? null
                                        : emergencyRelationshipController.text,
                                'campus_security_phone':
                                    campusSecurityController.text.isEmpty
                                        ? '+60123456789'
                                        : campusSecurityController.text,
                              })
                              .eq('id', userId);

                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Emergency contacts saved successfully!',
                                ),
                                backgroundColor: Colors.green,
                              ),
                            );
                            Navigator.pop(context);
                          }
                        } catch (e) {
                          developer.log('Error saving contacts: $e',
                              name: 'EmergencyContacts');
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
                    : const Text('Save Emergency Contacts'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
