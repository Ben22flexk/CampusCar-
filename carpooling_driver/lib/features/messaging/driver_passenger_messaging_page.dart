import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:carpooling_driver/services/messaging_service.dart'; // Adjust path if needed
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:carpooling_driver/core/utils/timezone_helper.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:developer' as developer;
import 'dart:io';

class DriverPassengerMessagingPage extends HookWidget {
  final String rideId;
  final String passengerId;
  final String passengerName;

  const DriverPassengerMessagingPage({
    super.key,
    required this.rideId,
    required this.passengerId,
    required this.passengerName,
  });

  @override
  Widget build(BuildContext context) {
    final messagingService = MessagingService();
    final supabase = Supabase.instance.client;
    final currentUserId = supabase.auth.currentUser?.id;
    final passengerPhone = useState<String?>(null);

    final messageController = useTextEditingController();
    final scrollController = useScrollController();
    final isUploading = useState(false);

    // Mark messages as read on open
    useEffect(() {
      messagingService.markAsRead(passengerId);

      // Fetch passenger phone number for call button
      Future.microtask(() async {
        try {
          final profile = await supabase
              .from('profiles')
              .select('phone_number')
              .eq('id', passengerId)
              .maybeSingle();

          if (profile != null && profile['phone_number'] != null) {
            passengerPhone.value = profile['phone_number'] as String;
          }
        } catch (e) {
          developer.log(
            'Error fetching passenger phone: $e',
            name: 'DriverPassengerMessagingPage',
          );
        }
      });
      return null;
    }, []);

    Future<void> pickAndSendImage() async {
      try {
        final picker = ImagePicker();
        final XFile? image = await picker.pickImage(source: ImageSource.gallery);
        if (image == null) return;

        isUploading.value = true;

        // Upload to Supabase Storage
        final bytes = await File(image.path).readAsBytes();
        final fileName = 'ride_${rideId}_${DateTime.now().millisecondsSinceEpoch}_${image.name}';
        final uploadResult = await supabase.storage
            .from('ride-images')
            .uploadBinary(fileName, bytes);

        developer.log('✅ Image uploaded: $uploadResult', name: 'DriverPassengerMessagingPage');

        // Get public URL for the image
        final imageUrl = supabase.storage
            .from('ride-images')
            .getPublicUrl(fileName);

        developer.log('📸 Image URL: $imageUrl', name: 'DriverPassengerMessagingPage');

        // Send image message using MessagingService
        await messagingService.sendMessage(
          receiverId: passengerId,
          messageText: '📷 Image',
          rideId: rideId,
          imageUrl: imageUrl,
        );

        developer.log('✅ Image message sent', name: 'DriverPassengerMessagingPage');
      } catch (e) {
        developer.log('❌ Error uploading image: $e', name: 'DriverPassengerMessagingPage');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to send image: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        isUploading.value = false;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(passengerName),
            Text(
              'Ride Messaging',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.7),
                  ),
            ),
          ],
        ),
        actions: [
          if (passengerPhone.value != null &&
              passengerPhone.value!.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.phone, color: Colors.green),
              tooltip: 'Call $passengerName',
              onPressed: () =>
                  _makePhoneCall(context, passengerPhone.value!),
            ),
        ],
      ),
      body: Column(
        children: [
          // Messages list
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: messagingService.getMessages(otherUserId: passengerId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text('Error: ${snapshot.error}'),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.message_outlined, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'No messages yet',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Start the conversation!',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  );
                }

                final messages = snapshot.data!;

                // Auto-scroll to bottom when new messages arrive
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (scrollController.hasClients) {
                    scrollController.animateTo(
                      scrollController.position.maxScrollExtent,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  }
                });

                return ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final isSentByMe = message['sender_id'] == currentUserId;
                    final sentAt = DateTime.parse(message['sent_at'] as String).toUtc();
                    final sentAtMalaysia = TimezoneHelper.utcToMalaysia(sentAt);

                    return _MessageBubble(
                      message: message['message_text'] as String?,
                      isMine: isSentByMe,
                      time: sentAtMalaysia,
                      imageUrl: message['image_url'] as String?,
                    );
                  },
                );
              },
            ),
          ),

          // Message Input
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(
                    icon: isUploading.value
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.image),
                    onPressed: isUploading.value ? null : pickAndSendImage,
                    tooltip: 'Send Image',
                  ),
                  Expanded(
                    child: TextField(
                      controller: messageController,
                      decoration: const InputDecoration(
                        hintText: 'Type a message...',
                        border: InputBorder.none,
                      ),
                      maxLines: null,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send),
                    color: Theme.of(context).colorScheme.primary,
                    onPressed: () async {
                      if (messageController.text.trim().isEmpty) return;
                      final text = messageController.text.trim();
                      messageController.clear();

                      try {
                        await messagingService.sendMessage(
                          receiverId: passengerId,
                          messageText: text,
                          rideId: rideId,
                        );
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to send: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _makePhoneCall(
    BuildContext context,
    String phoneNumber,
  ) async {
    try {
      // Normalize Malaysian phone format similar to passenger app
      String formattedNumber =
          phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');

      if (!formattedNumber.startsWith('+')) {
        if (formattedNumber.startsWith('60')) {
          formattedNumber = '+$formattedNumber';
        } else if (formattedNumber.startsWith('0')) {
          formattedNumber = '+60${formattedNumber.substring(1)}';
        } else {
          formattedNumber = '+60$formattedNumber';
        }
      }

      final uri = Uri(scheme: 'tel', path: formattedNumber);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Unable to make phone call'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      developer.log(
        'Error making phone call: $e',
        name: 'DriverPassengerMessagingPage',
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error initiating call: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

// Bubble widget as in ChatPage
class _MessageBubble extends StatelessWidget {
  final String? message;
  final bool isMine;
  final DateTime time;
  final String? imageUrl;

  const _MessageBubble({
    this.message,
    required this.isMine,
    required this.time,
    this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        decoration: BoxDecoration(
          color: isMine
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16).copyWith(
            bottomRight: isMine ? const Radius.circular(4) : null,
            bottomLeft: !isMine ? const Radius.circular(4) : null,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (imageUrl != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  imageUrl!,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      padding: const EdgeInsets.all(8),
                      color: Colors.grey[300],
                      child: const Icon(Icons.broken_image),
                    );
                  },
                ),
              ),
              const SizedBox(height: 4),
            ],
            if (message != null && message!.isNotEmpty)
              Text(
                message!,
                style: TextStyle(
                  color: isMine
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 4),
            Text(
              TimezoneHelper.formatMalaysiaTime(time),
              style: TextStyle(
                fontSize: 10,
                color: isMine
                    ? theme.colorScheme.onPrimary.withOpacity(0.7)
                    : theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
