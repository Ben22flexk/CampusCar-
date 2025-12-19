import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:carpooling_main/services/auth_service.dart';
import 'package:carpooling_main/auth/login_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:carpooling_main/pages/passenger_reports_page.dart';
import 'package:carpooling_main/pages/gender_preferences_page.dart';
import 'package:carpooling_main/pages/emergency_contacts_page.dart';

// User Profile Model
@immutable
class UserProfile {
  final String name;
  final String email;
  final String phone;
  final String? photoUrl;
  final String? photoPath;

  const UserProfile({
    required this.name,
    required this.email,
    required this.phone,
    this.photoUrl,
    this.photoPath,
  });

  UserProfile copyWith({
    String? name,
    String? email,
    String? phone,
    String? photoUrl,
    String? photoPath,
  }) {
    return UserProfile(
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      photoUrl: photoUrl ?? this.photoUrl,
      photoPath: photoPath ?? this.photoPath,
    );
  }
}

// Providers
final userProfileProvider = StateProvider<UserProfile>((ref) {
  // Get user data from Supabase Auth
  final authService = AuthService();
  final user = authService.currentUser;
  
  if (user != null) {
    // We'll load the avatar from Supabase in the ProfilePage
    return UserProfile(
      name: authService.userFullName,
      email: user.email ?? '',
      phone: authService.userContactNumber,
      photoUrl: null, // Will be loaded from Supabase
    );
  }
  
  // Fallback if no user logged in
  return const UserProfile(
    name: 'Guest',
    email: '',
    phone: '',
    photoUrl: null,
  );
});

// Main Profile Page
class ProfilePage extends HookConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userProfileProvider);
    final theme = Theme.of(context);
    
    // Load avatar and phone number from Supabase on mount
    useEffect(() {
      Future.microtask(() async {
        try {
          final supabase = Supabase.instance.client;
          final userId = supabase.auth.currentUser?.id;
          
          if (userId != null) {
            final profile = await supabase
                .from('profiles')
                .select('avatar_url, phone_number')
                .eq('id', userId)
                .maybeSingle();
            
            if (profile != null) {
              final updatedUser = user.copyWith(
                photoUrl: profile['avatar_url'] as String?,
              );
              
              // Load phone_number from profiles table if available
              final phoneFromProfile = profile['phone_number'] as String?;
              if (phoneFromProfile != null && phoneFromProfile.isNotEmpty) {
                ref.read(userProfileProvider.notifier).state = updatedUser.copyWith(
                  phone: phoneFromProfile,
                );
              } else {
                ref.read(userProfileProvider.notifier).state = updatedUser;
              }
            }
          }
        } catch (e) {
          debugPrint('Error loading profile: $e');
        }
      });
      return null;
    }, []);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: <Widget>[
            const SizedBox(height: 24),
            // Profile Image
            GestureDetector(
              onTap: () => _showImagePickerOptions(context, ref),
              child: Stack(
                children: <Widget>[
                  CircleAvatar(
                    radius: 60,
                    backgroundImage: user.photoPath != null
                        ? FileImage(File(user.photoPath!))
                        : (user.photoUrl != null
                            ? NetworkImage(user.photoUrl!) as ImageProvider
                            : null),
                    child: user.photoUrl == null && user.photoPath == null
                        ? const Icon(Icons.person, size: 60)
                        : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: theme.colorScheme.primary,
                      child: const Icon(
                        Icons.camera_alt,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // User Info
            Text(
              user.name,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              user.email,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              user.phone,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 32),
            // Menu Items
            _ProfileMenuItem(
              icon: Icons.edit,
              title: 'Edit Profile',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const EditProfilePage(),
                  ),
                );
              },
            ),
            _ProfileMenuItem(
              icon: Icons.lock,
              title: 'Change Password',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ChangePasswordPage(),
                  ),
                );
              },
            ),
            _ProfileMenuItem(
              icon: Icons.payment,
              title: 'Payment Methods',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PaymentDetailsPage(),
                  ),
                );
              },
            ),
            _ProfileMenuItem(
              icon: Icons.assessment,
              title: 'Summary Reports',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PassengerReportsPage(),
                  ),
                );
              },
            ),
            _ProfileMenuItem(
              icon: Icons.people,
              title: 'Gender & Matching Preferences',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const GenderPreferencesPage(),
                  ),
                );
              },
            ),
            _ProfileMenuItem(
              icon: Icons.emergency,
              title: 'Emergency Contacts',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const EmergencyContactsPage(),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 8),
            _ProfileMenuItem(
              icon: Icons.logout,
              title: 'Logout',
              iconColor: Colors.red,
              titleColor: Colors.red,
              onTap: () {
                _showLogoutDialog(context, ref);
              },
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  void _showLogoutDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              
              try {
                final authService = AuthService();
                await authService.signOut();
                
                if (context.mounted) {
                  // Navigate to login page and clear navigation stack
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const LoginPage(),
                    ),
                    (route) => false,
                  );
                  
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Logged out successfully'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Logout error: ${e.toString()}'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  void _showImagePickerOptions(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text(
                'Update Profile Photo',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Colors.blue),
                title: const Text('Take Photo'),
                onTap: () async {
                  Navigator.pop(context);
                  await _pickImage(ImageSource.camera, ref);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Colors.green),
                title: const Text('Choose from Gallery'),
                onTap: () async {
                  Navigator.pop(context);
                  await _pickImage(ImageSource.gallery, ref);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source, WidgetRef ref) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        // Upload to Supabase Storage
        final supabase = Supabase.instance.client;
        final userId = supabase.auth.currentUser?.id;
        
        if (userId == null) {
          debugPrint('User not logged in');
          return;
        }
        
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
        
        // Update local state
        final user = ref.read(userProfileProvider);
        ref.read(userProfileProvider.notifier).state = user.copyWith(
          photoUrl: publicUrl,
          photoPath: null, // Clear local path
        );
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
    }
  }
}

// Profile Menu Item Widget
class _ProfileMenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final Color? iconColor;
  final Color? titleColor;

  const _ProfileMenuItem({
    required this.icon,
    required this.title,
    required this.onTap,
    this.iconColor,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: <Widget>[
            Icon(
              icon,
              color: iconColor ?? Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: titleColor,
                    ),
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }
}

// Edit Profile Page
class EditProfilePage extends HookConsumerWidget {
  const EditProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userProfileProvider);
    final nameController = useTextEditingController(text: user.name);
    final emailController = useTextEditingController(text: user.email);
    final phoneController = useTextEditingController(text: user.phone);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: emailController,
              enabled: false, // Email cannot be edited
              decoration: InputDecoration(
                labelText: 'Email',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.email),
                helperText: 'Email cannot be changed',
                helperStyle: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 12,
                ),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(
                labelText: 'Phone',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  try {
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

                    // Update local state
                    ref.read(userProfileProvider.notifier).state = user.copyWith(
                      name: nameController.text,
                      phone: phoneController.text,
                    );
                    
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Profile updated successfully'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error updating profile: ${e.toString()}'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
                child: const Text('Update Profile'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Change Password Page
class ChangePasswordPage extends HookWidget {
  const ChangePasswordPage({super.key});

  @override
  Widget build(BuildContext context) {
    final oldPasswordController = useTextEditingController();
    final newPasswordController = useTextEditingController();
    final confirmPasswordController = useTextEditingController();
    final showOldPassword = useState<bool>(false);
    final showNewPassword = useState<bool>(false);
    final showConfirmPassword = useState<bool>(false);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Change Password'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            const SizedBox(height: 24),
            // Lock Illustration
            Container(
              height: 150,
              width: 150,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.lock_outline,
                size: 80,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Create a New Password',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your new password must be different from previously used passwords',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            // Old Password
            TextField(
              controller: oldPasswordController,
              obscureText: !showOldPassword.value,
              decoration: InputDecoration(
                labelText: 'Old Password',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.lock),
                suffixIcon: IconButton(
                  icon: Icon(
                    showOldPassword.value
                        ? Icons.visibility
                        : Icons.visibility_off,
                  ),
                  onPressed: () {
                    showOldPassword.value = !showOldPassword.value;
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            // New Password
            TextField(
              controller: newPasswordController,
              obscureText: !showNewPassword.value,
              decoration: InputDecoration(
                labelText: 'New Password',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.lock),
                suffixIcon: IconButton(
                  icon: Icon(
                    showNewPassword.value
                        ? Icons.visibility
                        : Icons.visibility_off,
                  ),
                  onPressed: () {
                    showNewPassword.value = !showNewPassword.value;
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Confirm Password
            TextField(
              controller: confirmPasswordController,
              obscureText: !showConfirmPassword.value,
              decoration: InputDecoration(
                labelText: 'Confirm Password',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.lock),
                suffixIcon: IconButton(
                  icon: Icon(
                    showConfirmPassword.value
                        ? Icons.visibility
                        : Icons.visibility_off,
                  ),
                  onPressed: () {
                    showConfirmPassword.value = !showConfirmPassword.value;
                  },
                ),
              ),
            ),
            const SizedBox(height: 32),
            // Submit Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  // Validation
                  if (oldPasswordController.text.isEmpty ||
                      newPasswordController.text.isEmpty ||
                      confirmPasswordController.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please fill all fields'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }

                  if (newPasswordController.text !=
                      confirmPasswordController.text) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Passwords do not match'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }

                  if (newPasswordController.text.length < 8) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Password must be at least 8 characters'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }

                  // Update password in Supabase
                  try {
                    final authService = AuthService();
                    await authService.updatePassword(
                      newPassword: newPasswordController.text,
                    );
                    
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Password changed successfully!'),
                          backgroundColor: Colors.green,
                        ),
                      );
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
                  }
                },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Submit'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Payment Details Page
class PaymentDetailsPage extends HookWidget {
  const PaymentDetailsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final selectedMethod = useState<String>('bank');
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment Methods'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Select Payment Method',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose how you want to pay for your rides',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 16),
            // Bank Account Option
            Card(
              child: RadioListTile<String>(
                value: 'bank',
                groupValue: selectedMethod.value,
                onChanged: (value) {
                  if (value != null) {
                    selectedMethod.value = value;
                  }
                },
                title: const Text('Bank Account'),
                subtitle: const Text('Add your bank details for payments'),
                secondary: const Icon(Icons.account_balance),
              ),
            ),
            const SizedBox(height: 8),
            // Touch 'n Go Option
            Card(
              child: RadioListTile<String>(
                value: 'tng',
                groupValue: selectedMethod.value,
                onChanged: (value) {
                  if (value != null) {
                    selectedMethod.value = value;
                  }
                },
                title: const Text("Touch 'n Go"),
                subtitle: const Text('Pay using Touch \'n Go eWallet'),
                secondary: const Icon(Icons.phone_android),
              ),
            ),
            const SizedBox(height: 24),
            // Payment Form based on selection
            if (selectedMethod.value == 'bank') ...[
              _BankDetailsForm(),
            ] else ...[
              _TouchNGoForm(),
            ],
          ],
        ),
      ),
    );
  }
}

class _BankDetailsForm extends HookWidget {
  @override
  Widget build(BuildContext context) {
    final bankNameController = useTextEditingController();
    final accountNumberController = useTextEditingController();
    final accountHolderController = useTextEditingController();

    return Column(
      children: <Widget>[
        TextField(
          controller: bankNameController,
          decoration: const InputDecoration(
            labelText: 'Bank Name',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.account_balance),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: accountNumberController,
          decoration: const InputDecoration(
            labelText: 'Account Number',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.numbers),
          ),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: accountHolderController,
          decoration: const InputDecoration(
            labelText: 'Account Holder Name',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.person),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              if (bankNameController.text.isEmpty ||
                  accountNumberController.text.isEmpty ||
                  accountHolderController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please fill all fields'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Bank details saved successfully'),
                ),
              );
            },
            child: const Text('Save Details'),
          ),
        ),
      ],
    );
  }
}

class _TouchNGoForm extends HookWidget {
  @override
  Widget build(BuildContext context) {
    final phoneController = useTextEditingController();

    return Column(
      children: <Widget>[
        TextField(
          controller: phoneController,
          decoration: const InputDecoration(
            labelText: 'Touch \'n Go Phone Number',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.phone),
            prefixText: '+60 ',
          ),
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              if (phoneController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter phone number'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Touch \'n Go linked successfully'),
                ),
              );
            },
            child: const Text('Link Account'),
          ),
        ),
      ],
    );
  }
}

