import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:developer' as developer;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:carpooling_driver/services/driver_verification_service.dart';
import 'package:carpooling_driver/features/ride_management/create_ride_page_v2.dart';
import 'package:carpooling_driver/features/notifications/data/datasources/notification_service.dart';

/// Driver verification page with automated validation
class DriverVerificationPage extends HookConsumerWidget {
  const DriverVerificationPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final verificationService = useMemoized(() => DriverVerificationService());
    
    // Form controllers
    final licenseController = useTextEditingController();
    final licenseStateController = useTextEditingController();
    final plateController = useTextEditingController();
    final manufacturerController = useTextEditingController();
    final modelController = useTextEditingController();
    final colorController = useTextEditingController();
    final yearController = useTextEditingController();
    final seatsController = useTextEditingController(text: '4');
    
    // State
    final licenseImage = useState<File?>(null);
    final licenseImageUrl = useState<String?>(null);
    final termsAccepted = useState(false);
    final isSubmitting = useState(false);
    final validationErrors = useState<List<String>>([]);
    final currentStep = useState(0);
    
    // Validation states
    final licenseValid = useState(false);
    final plateValid = useState(false);

    Future<void> pickLicenseImage() async {
      final picker = ImagePicker();
      final result = await showDialog<ImageSource>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Select Image Source'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Camera'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Gallery'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      );

      if (result != null) {
        final pickedFile = await picker.pickImage(source: result);
        if (pickedFile != null) {
          licenseImage.value = File(pickedFile.path);
          
          // Upload immediately
          try {
            final url = await verificationService.uploadLicenseImage(File(pickedFile.path));
            licenseImageUrl.value = url;
            
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('License image uploaded successfully!')),
              );
            }
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Upload failed: $e')),
              );
            }
          }
        }
      }
    }

    Future<void> submitVerification() async {
      validationErrors.value = [];
      
      // Client-side validation
      final errors = <String>[];
      
      if (!licenseValid.value) {
        errors.add('Invalid Malaysian license format');
      }
      if (!plateValid.value) {
        errors.add('Invalid Malaysian vehicle plate format');
      }
      if (manufacturerController.text.trim().length < 2) {
        errors.add('Vehicle manufacturer is required');
      }
      if (modelController.text.trim().length < 2) {
        errors.add('Vehicle model is required');
      }
      if (colorController.text.trim().length < 2) {
        errors.add('Vehicle color is required');
      }
      if (licenseImageUrl.value == null) {
        errors.add('License image is required');
      }
      if (!termsAccepted.value) {
        errors.add('You must accept the terms and declaration');
      }

      if (errors.isNotEmpty) {
        validationErrors.value = errors;
        return;
      }

      isSubmitting.value = true;

      try {
        final result = await verificationService.submitVerification(
          licenseNumber: licenseController.text,
          licensePlate: plateController.text,
          vehicleManufacturer: manufacturerController.text,
          vehicleModel: modelController.text,
          vehicleColor: colorController.text,
          vehicleSeats: int.tryParse(seatsController.text) ?? 4,
          licenseImageUrl: licenseImageUrl.value!, // Pass the uploaded image URL
          licenseState: licenseStateController.text.isEmpty ? null : licenseStateController.text,
          vehicleYear: yearController.text.isEmpty ? null : int.tryParse(yearController.text),
          termsAccepted: termsAccepted.value,
        );

        if (result.isApproved) {
          // Send verification success notification
          try {
            final supabase = Supabase.instance.client;
            final userId = supabase.auth.currentUser?.id;
            if (userId != null) {
              final notificationService = NotificationService();
              await notificationService.createNotification(
                userId: userId,
                title: 'Driver Verification Approved! 🎉',
                message: 'Congratulations! Your driver account has been verified. You can now create rides and start driving.',
                type: 'verification_approved',
              );
            }
          } catch (e) {
            // Notification failed, but don't block the flow
            developer.log('Failed to send notification: $e', name: 'DriverVerification', error: e);
          }

          if (context.mounted) {
            await showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) => AlertDialog(
                title: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green.shade600),
                    const SizedBox(width: 12),
                    const Text('Verified!'),
                  ],
                ),
                content: const Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('🎉 Congratulations!'),
                    SizedBox(height: 8),
                    Text('Your driver account has been automatically verified.'),
                    SizedBox(height: 8),
                    Text('You can now create rides and start driving!'),
                  ],
                ),
                actions: [
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(context); // Close dialog
                      Navigator.pop(context); // Exit verification page
                      // Navigate to create ride page
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => CreateRidePageV2(),
                        ),
                      );
                    },
                    child: const Text('Create Your First Ride'),
                  ),
                ],
              ),
            );
          }
        } else {
          validationErrors.value = result.errors;
        }
      } catch (e) {
        // Extract clean error message
        final errorMessage = e.toString().replaceFirst('Exception: ', '');
        validationErrors.value = [errorMessage];
      } finally {
        isSubmitting.value = false;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Driver Verification'),
            Text(
              'Automated approval',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      body: Stepper(
        currentStep: currentStep.value,
        onStepContinue: () {
          if (currentStep.value < 2) {
            currentStep.value++;
          } else {
            submitVerification();
          }
        },
        onStepCancel: () {
          if (currentStep.value > 0) {
            currentStep.value--;
          }
        },
        steps: [
          // Step 1: License Information
          Step(
            title: const Text('License Information'),
            content: Column(
              children: [
                TextField(
                  controller: licenseController,
                  decoration: InputDecoration(
                    labelText: 'Malaysian License Number *',
                    hintText: 'e.g., A1234567',
                    helperText: verificationService.getLicenseFormatExample(),
                    prefixIcon: const Icon(Icons.credit_card),
                    border: const OutlineInputBorder(),
                    suffixIcon: licenseValid.value
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : null,
                  ),
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (value) {
                    licenseValid.value = verificationService.validateMalaysianLicense(value);
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: licenseStateController,
                  decoration: const InputDecoration(
                    labelText: 'State (Optional)',
                    hintText: 'e.g., Selangor, KL',
                    prefixIcon: Icon(Icons.location_city),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                
                // License Image Upload
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        if (licenseImage.value != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              licenseImage.value!,
                              height: 200,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          )
                        else
                          Container(
                            height: 200,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.camera_alt,
                                  size: 48,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Upload License Photo',
                                  style: theme.textTheme.titleMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Required for verification',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: pickLicenseImage,
                          icon: const Icon(Icons.add_a_photo),
                          label: Text(licenseImage.value == null ? 'Upload License' : 'Change Photo'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            isActive: currentStep.value >= 0,
            state: currentStep.value > 0 ? StepState.complete : StepState.indexed,
          ),

          // Step 2: Vehicle Information
          Step(
            title: const Text('Vehicle Information'),
            content: Column(
              children: [
                TextField(
                  controller: plateController,
                  decoration: InputDecoration(
                    labelText: 'Vehicle Plate Number *',
                    hintText: 'e.g., WAB 1234',
                    helperText: verificationService.getPlateFormatExample(),
                    prefixIcon: const Icon(Icons.pin),
                    border: const OutlineInputBorder(),
                    suffixIcon: plateValid.value
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : null,
                  ),
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (value) {
                    plateValid.value = verificationService.validateMalaysianPlate(value);
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: manufacturerController,
                  decoration: const InputDecoration(
                    labelText: 'Manufacturer *',
                    hintText: 'e.g., Perodua, Proton, Honda',
                    prefixIcon: Icon(Icons.business),
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: modelController,
                  decoration: const InputDecoration(
                    labelText: 'Model *',
                    hintText: 'e.g., Myvi, Axia, City',
                    prefixIcon: Icon(Icons.directions_car),
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: colorController,
                        decoration: const InputDecoration(
                          labelText: 'Color *',
                          hintText: 'e.g., White',
                          prefixIcon: Icon(Icons.palette),
                          border: OutlineInputBorder(),
                        ),
                        textCapitalization: TextCapitalization.words,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: yearController,
                        decoration: const InputDecoration(
                          labelText: 'Year (Optional)',
                          hintText: 'e.g., 2020',
                          prefixIcon: Icon(Icons.calendar_today),
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: seatsController,
                  decoration: const InputDecoration(
                    labelText: 'Passenger Seats *',
                    hintText: '1-4 seats',
                    helperText: 'Available seats for passengers (excluding driver)',
                    prefixIcon: Icon(Icons.airline_seat_recline_normal),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
            isActive: currentStep.value >= 1,
            state: currentStep.value > 1 ? StepState.complete : StepState.indexed,
          ),

          // Step 3: Terms & Submit
          Step(
            title: const Text('Terms & Declaration'),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  color: theme.colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Malaysian Transport Law Declaration',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text('I declare that:'),
                        const SizedBox(height: 8),
                        const Text('• All information provided is accurate and valid'),
                        const Text('• My license is valid under Malaysian law'),
                        const Text('• My vehicle is roadworthy and insured'),
                        const Text('• I understand false entries may result in account suspension'),
                        const Text('• I comply with all road safety regulations'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  title: const Text('I accept the terms and declaration'),
                  subtitle: const Text('Required for verification'),
                  value: termsAccepted.value,
                  onChanged: (value) => termsAccepted.value = value ?? false,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                
                // Validation Errors
                if (validationErrors.value.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Card(
                    color: Colors.red.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.error, color: Colors.red.shade700),
                              const SizedBox(width: 8),
                              Text(
                                'Validation Errors',
                                style: TextStyle(
                                  color: Colors.red.shade700,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ...validationErrors.value.map((error) => Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '• $error',
                              style: TextStyle(color: Colors.red.shade700),
                            ),
                          )),
                        ],
                      ),
                    ),
                  ),
                ],
                
                const SizedBox(height: 24),
                if (isSubmitting.value)
                  const Center(child: CircularProgressIndicator())
                else
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: submitVerification,
                      icon: const Icon(Icons.verified_user),
                      label: const Text('Submit for Auto-Verification'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                      ),
                    ),
                  ),
              ],
            ),
            isActive: currentStep.value >= 2,
          ),
        ],
      ),
    );
  }
}

