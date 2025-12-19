import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:carpooling_driver/services/driver_profile_service.dart';
import 'package:carpooling_driver/features/driver_verification/driver_verification_page.dart';
import 'package:carpooling_driver/pages/gender_preferences_page.dart';
import 'package:image_picker/image_picker.dart';

/// Driver Profile Page with Vehicle Management
class DriverProfilePage extends HookConsumerWidget {
  const DriverProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final supabase = Supabase.instance.client;
    final profileService = DriverProfileService();
    
    final user = supabase.auth.currentUser;
    final nameController = useTextEditingController(text: user?.userMetadata?['name'] ?? '');
    final emailController = useTextEditingController(text: user?.email ?? '');
    final phoneController = useTextEditingController(text: user?.userMetadata?['phone'] ?? '');
    
    final isEditing = useState(false);
    final isSaving = useState(false);
    final vehicleDetails = useState<VehicleDetails?>(null);
    final isLoadingVehicle = useState(true);
    
    // Payment details
    final tngPhoneController = useTextEditingController();
    final tngQrCodeUrl = useState<String?>(null);
    final isLoadingPayment = useState(true);
    final isUploadingQr = useState(false);
    
    // Profile picture
    final avatarUrl = useState<String?>(null);
    final isUploadingAvatar = useState(false);

    // Load vehicle details and payment info
    useEffect(() {
      () async {
        try {
          final details = await profileService.getVehicleDetails();
          vehicleDetails.value = details;
        } finally {
          isLoadingVehicle.value = false;
        }
        
        // Load payment details, avatar, and phone number
        try {
          final userId = supabase.auth.currentUser?.id;
          if (userId != null) {
            final profile = await supabase
                .from('profiles')
                .select('tng_qr_code, tng_phone_number, avatar_url, phone_number')
                .eq('id', userId)
                .maybeSingle();
            
            if (profile != null) {
              tngQrCodeUrl.value = profile['tng_qr_code'] as String?;
              tngPhoneController.text = (profile['tng_phone_number'] as String?) ?? '';
              avatarUrl.value = profile['avatar_url'] as String?;
              // Load phone_number from profiles table, fallback to auth metadata
              final phoneFromProfile = profile['phone_number'] as String?;
              if (phoneFromProfile != null && phoneFromProfile.isNotEmpty) {
                phoneController.text = phoneFromProfile;
              }
            }
          }
        } finally {
          isLoadingPayment.value = false;
        }
      }();
      return null;
    }, []);

    void saveProfile() async {
      isSaving.value = true;
      try {
        final userId = supabase.auth.currentUser?.id;
        if (userId == null) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('User not authenticated'),
                backgroundColor: Colors.red,
              ),
            );
          }
          isSaving.value = false;
          return;
        }

        // Update auth metadata
        await supabase.auth.updateUser(
          UserAttributes(
            data: {
              'name': nameController.text,
              'phone': phoneController.text,
            },
          ),
        );

        // Update phone_number in profiles table
        final phoneNumber = phoneController.text.trim();
        await supabase
            .from('profiles')
            .update({
              'phone_number': phoneNumber.isEmpty ? null : phoneNumber,
            })
            .eq('id', userId);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profile updated successfully'),
              backgroundColor: Colors.green,
            ),
          );
          isEditing.value = false;
        }
      } catch (e) {
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
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Profile'),
        actions: [
          if (!isEditing.value)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => isEditing.value = true,
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => isEditing.value = false,
            ),
            IconButton(
              icon: isSaving.value
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              onPressed: isSaving.value ? null : saveProfile,
            ),
          ],
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Profile Picture
          Center(
            child: Stack(
              children: [
                isUploadingAvatar.value
                    ? Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.grey.shade200,
                        ),
                        child: const Center(
                          child: CircularProgressIndicator(),
                        ),
                      )
                    : CircleAvatar(
                        radius: 60,
                        backgroundColor: Colors.orange.shade100,
                        backgroundImage: avatarUrl.value != null
                            ? NetworkImage(avatarUrl.value!)
                            : null,
                        child: avatarUrl.value == null
                            ? Icon(
                                Icons.person,
                                size: 60,
                                color: Colors.orange.shade700,
                              )
                            : null,
                      ),
                if (isEditing.value && !isUploadingAvatar.value)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: theme.colorScheme.primary,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.camera_alt, size: 18, color: Colors.white),
                        onPressed: () => _uploadProfilePicture(
                          context,
                          supabase,
                          isUploadingAvatar,
                          avatarUrl,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Personal Information Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.person_outline, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Personal Information',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  
                  // Name Field
                  TextField(
                    controller: nameController,
                    enabled: isEditing.value,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      prefixIcon: Icon(Icons.badge),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Email Field (Read-only)
                  TextField(
                    controller: emailController,
                    enabled: false,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      prefixIcon: const Icon(Icons.email),
                      border: const OutlineInputBorder(),
                      helperText: 'Email cannot be changed',
                      helperStyle: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Phone Field
                  TextField(
                    controller: phoneController,
                    enabled: isEditing.value,
                    decoration: const InputDecoration(
                      labelText: 'Phone',
                      prefixIcon: Icon(Icons.phone),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Vehicle Management Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.directions_car, color: theme.colorScheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            'Manage Vehicles',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      if (vehicleDetails.value != null && vehicleDetails.value!.isVerified)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.verified,
                                size: 16,
                                color: Colors.green.shade700,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Verified',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.green.shade700,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const Divider(height: 24),
                  
                  if (isLoadingVehicle.value)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (vehicleDetails.value == null)
                    Column(
                      children: [
                        Icon(
                          Icons.car_rental,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No vehicle registered',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Complete driver verification to add your vehicle',
                          style: theme.textTheme.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const DriverVerificationPage(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('Register Vehicle'),
                        ),
                      ],
                    )
                  else
                    _buildVehicleInfo(context, vehicleDetails.value!),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Payment Details Card
          Card(
            elevation: 3,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.account_balance_wallet,
                          color: Colors.blue.shade700,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Payment Details',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Set up Touch \'n Go for easy payments',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  
                  // Touch 'n Go Section Header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.qr_code_scanner, color: Colors.green.shade700, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Touch \'n Go Details',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  // TNG Phone Number
                  TextField(
                    controller: tngPhoneController,
                    enabled: isEditing.value,
                    decoration: InputDecoration(
                      labelText: 'TNG Phone Number',
                      hintText: '01X-XXXX XXXX',
                      prefixIcon: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                        child: Text(
                          '+60',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      prefixIconConstraints: const BoxConstraints(minWidth: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300, width: 1.5),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
                      ),
                      helperText: 'Malaysian phone number linked to your TNG account',
                      helperMaxLines: 2,
                      filled: true,
                      fillColor: isEditing.value ? Colors.white : Colors.grey.shade50,
                    ),
                    keyboardType: TextInputType.phone,
                    maxLength: 12,
                    onChanged: (value) {
                      // Format phone number as user types
                      String formatted = _formatMalaysianPhone(value);
                      if (formatted != value) {
                        tngPhoneController.value = TextEditingValue(
                          text: formatted,
                          selection: TextSelection.collapsed(offset: formatted.length),
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 24),
                  
                  // TNG QR Code Upload
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.qr_code_2, size: 20, color: theme.colorScheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            'TNG QR Code',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Upload your TNG QR code so passengers can pay you easily',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      if (isLoadingPayment.value)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      else                       if (tngQrCodeUrl.value != null && tngQrCodeUrl.value!.isNotEmpty)
                        Column(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(color: Colors.green.shade300, width: 3),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.green.shade100,
                                    blurRadius: 10,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.check_circle, color: Colors.green.shade700, size: 16),
                                        const SizedBox(width: 6),
                                        Text(
                                          'QR Code Active',
                                          style: TextStyle(
                                            color: Colors.green.shade700,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.network(
                                      tngQrCodeUrl.value!,
                                      width: 220,
                                      height: 220,
                                      fit: BoxFit.contain,
                                      errorBuilder: (context, error, stackTrace) {
                                        return Container(
                                          width: 220,
                                          height: 220,
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade100,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
                                              const SizedBox(height: 8),
                                              Text(
                                                'Failed to load QR code',
                                                style: TextStyle(
                                                  color: Colors.grey.shade600,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                      loadingBuilder: (context, child, loadingProgress) {
                                        if (loadingProgress == null) return child;
                                        return Container(
                                          width: 220,
                                          height: 220,
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade100,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Center(
                                            child: CircularProgressIndicator(
                                              value: loadingProgress.expectedTotalBytes != null
                                                  ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                                  : null,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (isEditing.value)
                              OutlinedButton.icon(
                                onPressed: isUploadingQr.value ? null : () async {
                                  await _uploadTngQrCode(context, supabase, isUploadingQr, tngQrCodeUrl);
                                },
                                icon: isUploadingQr.value
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.photo_camera),
                                label: const Text('Change QR Code'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                  side: BorderSide(color: theme.colorScheme.primary),
                                ),
                              ),
                          ],
                        )
                      else
                        Column(
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(40),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [Colors.blue.shade50, Colors.purple.shade50],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.blue.shade200,
                                  width: 2,
                                  style: BorderStyle.solid,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(20),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.blue.shade100,
                                          blurRadius: 10,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      Icons.qr_code_2,
                                      size: 60,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No QR code uploaded',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Passengers can scan your QR code\nto pay you instantly',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade600,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            if (isEditing.value)
                              ElevatedButton.icon(
                                onPressed: isUploadingQr.value ? null : () async {
                                  await _uploadTngQrCode(context, supabase, isUploadingQr, tngQrCodeUrl);
                                },
                                icon: isUploadingQr.value
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Icon(Icons.add_photo_alternate),
                                label: const Text('Upload QR Code'),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                                  backgroundColor: theme.colorScheme.primary,
                                  foregroundColor: Colors.white,
                                  elevation: 2,
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                  
                  if (isEditing.value) ...[
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: isSaving.value ? null : () async {
                          isSaving.value = true;
                          try {
                            final userId = supabase.auth.currentUser?.id;
                            if (userId != null) {
                              // Remove any formatting characters and validate
                              final phoneNumber = tngPhoneController.text.replaceAll(RegExp(r'[^0-9]'), '');
                              
                              // Validate Malaysian phone number (10-11 digits)
                              if (phoneNumber.isNotEmpty && (phoneNumber.length < 9 || phoneNumber.length > 11)) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('❌ Please enter a valid Malaysian phone number'),
                                      backgroundColor: Colors.orange,
                                    ),
                                  );
                                }
                                isSaving.value = false;
                                return;
                              }
                              
                              await supabase
                                  .from('profiles')
                                  .update({
                                    'tng_phone_number': phoneNumber.isEmpty ? null : phoneNumber,
                                  })
                                  .eq('id', userId);
                              
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Row(
                                      children: [
                                        Icon(Icons.check_circle, color: Colors.white),
                                        SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Payment details updated successfully',
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Row(
                                    children: [
                                      const Icon(Icons.error, color: Colors.white),
                                      const SizedBox(width: 8),
                                      Expanded(child: Text('Error: ${e.toString()}')),
                                    ],
                                  ),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          } finally {
                            isSaving.value = false;
                          }
                        },
                        icon: isSaving.value
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.save),
                        label: const Text('Save Payment Details'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          elevation: 2,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Gender & Matching Preferences Button
          OutlinedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const DriverGenderPreferencesPage(),
                ),
              );
            },
            icon: const Icon(Icons.people),
            label: const Text('Gender & Matching Preferences'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.all(16),
            ),
          ),
          const SizedBox(height: 16),

          // Sign Out Button
          OutlinedButton.icon(
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Sign Out'),
                  content: const Text('Are you sure you want to sign out?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Sign Out'),
                    ),
                  ],
                ),
              );

              if (confirm == true && context.mounted) {
                await supabase.auth.signOut();
              }
            },
            icon: const Icon(Icons.logout),
            label: const Text('Sign Out'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.all(16),
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleInfo(BuildContext context, VehicleDetails vehicle) {
    final theme = Theme.of(context);
    
    return Column(
      children: [
        // Vehicle Plate (READ-ONLY - Cannot be changed)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.black, width: 2),
                ),
                child: Text(
                  vehicle.licensePlate,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Vehicle Plate',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.blue.shade700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.lock,
                          size: 14,
                          color: Colors.blue.shade700,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Cannot be changed',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue.shade700,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        
        // Vehicle Details
        _buildDetailRow(
          icon: Icons.directions_car,
          label: 'Vehicle',
          value: vehicle.fullVehicleName,
        ),
        _buildDetailRow(
          icon: Icons.palette,
          label: 'Color',
          value: vehicle.color,
        ),
        _buildDetailRow(
          icon: Icons.event_seat,
          label: 'Seats',
          value: '${vehicle.seats} passengers',
        ),
        _buildDetailRow(
          icon: Icons.badge,
          label: 'License Number',
          value: vehicle.licenseNumber,
        ),
        _buildDetailRow(
          icon: Icons.verified,
          label: 'Status',
          value: vehicle.statusDisplay,
        ),
        if (vehicle.verifiedAt != null)
          _buildDetailRow(
            icon: Icons.check_circle,
            label: 'Verified On',
            value: '${vehicle.verifiedAt!.day}/${vehicle.verifiedAt!.month}/${vehicle.verifiedAt!.year}',
          ),
      ],
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Helper function to upload profile picture
Future<void> _uploadProfilePicture(
  BuildContext context,
  SupabaseClient supabase,
  ValueNotifier<bool> isUploadingAvatar,
  ValueNotifier<String?> avatarUrl,
) async {
  try {
    isUploadingAvatar.value = true;
    
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    
    if (pickedFile == null) {
      isUploadingAvatar.value = false;
      return;
    }
    
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('User not logged in');
    
    final fileBytes = await pickedFile.readAsBytes();
    final fileExt = pickedFile.path.split('.').last.toLowerCase();
    final filePath = '$userId/avatar.$fileExt';
    
    // Upload to Supabase Storage
    await supabase.storage
        .from('profile-pictures')
        .uploadBinary(
          filePath,
          fileBytes,
          fileOptions: FileOptions(
            upsert: true,
            contentType: 'image/$fileExt',
          ),
        );
    
    // Get public URL
    final publicUrl = supabase.storage
        .from('profile-pictures')
        .getPublicUrl(filePath);
    
    // Update profiles table
    await supabase
        .from('profiles')
        .update({'avatar_url': publicUrl})
        .eq('id', userId);
    
    avatarUrl.value = publicUrl;
    
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Profile picture updated successfully!',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          backgroundColor: Colors.green,
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text('Error uploading: ${e.toString()}')),
            ],
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  } finally {
    isUploadingAvatar.value = false;
  }
}

// Helper function to format Malaysian phone number
String _formatMalaysianPhone(String input) {
  // Remove all non-digit characters
  String digits = input.replaceAll(RegExp(r'[^0-9]'), '');
  
  // Limit to 11 digits (01X-XXXX XXXX)
  if (digits.length > 11) {
    digits = digits.substring(0, 11);
  }
  
  // Format as 01X-XXXX XXXX or 01X-XXX XXXX
  if (digits.length <= 3) {
    return digits;
  } else if (digits.length <= 6) {
    return '${digits.substring(0, 3)}-${digits.substring(3)}';
  } else if (digits.length <= 10) {
    return '${digits.substring(0, 3)}-${digits.substring(3, 6)} ${digits.substring(6)}';
  } else {
    return '${digits.substring(0, 3)}-${digits.substring(3, 7)} ${digits.substring(7)}';
  }
}

// Helper function to upload TNG QR code
Future<void> _uploadTngQrCode(
  BuildContext context,
  SupabaseClient supabase,
  ValueNotifier<bool> isUploadingQr,
  ValueNotifier<String?> tngQrCodeUrl,
) async {
  try {
    // Pick image
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );

    if (image == null) return;

    isUploadingQr.value = true;

    // Get user ID
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    // Upload to Supabase Storage
    final bytes = await image.readAsBytes();
    final fileExt = image.path.split('.').last;
    final fileName = 'tng_qr_${userId}_${DateTime.now().millisecondsSinceEpoch}.$fileExt';
    final filePath = 'tng_qr_codes/$fileName';

    await supabase.storage
        .from('driver-documents')
        .uploadBinary(
          filePath,
          bytes,
          fileOptions: const FileOptions(
            cacheControl: '3600',
            upsert: false,
          ),
        );

    // Get public URL
    final publicUrl = supabase.storage
        .from('driver-documents')
        .getPublicUrl(filePath);

    // Update profile with new QR code URL
    await supabase
        .from('profiles')
        .update({
          'tng_qr_code': publicUrl,
        })
        .eq('id', userId);

    // Update local state
    tngQrCodeUrl.value = publicUrl;

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ TNG QR code uploaded successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error uploading QR code: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  } finally {
    isUploadingQr.value = false;
  }
}
