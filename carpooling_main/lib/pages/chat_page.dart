import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:carpooling_main/services/messaging_service.dart';
import 'package:carpooling_main/core/utils/timezone_helper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import 'dart:developer' as developer;

class ChatPage extends HookWidget {
  final String otherUserId;
  final String otherUserName;
  final String? rideId;

  const ChatPage({
    super.key,
    required this.otherUserId,
    required this.otherUserName,
    this.rideId,
  });

  @override
  Widget build(BuildContext context) {
    final messagingService = MessagingService();
    final messageController = useTextEditingController();
    final scrollController = useScrollController();
    final isUploading = useState(false);
    final otherUserPhone = useState<String?>(null);

    // Mark messages as read when opening chat and fetch phone number
    useEffect(() {
      messagingService.markAsRead(otherUserId);
      
      // Fetch other user's phone number
      Future.microtask(() async {
        try {
          final profile = await Supabase.instance.client
              .from('profiles')
              .select('phone_number')
              .eq('id', otherUserId)
              .maybeSingle();
          
          if (profile != null && profile['phone_number'] != null) {
            otherUserPhone.value = profile['phone_number'] as String;
          }
        } catch (e) {
          developer.log('Error fetching phone number: $e', name: 'ChatPage');
        }
      });
      
      return null;
    }, []);

    Future<void> pickAndSendImage() async {
      try {
        final picker = ImagePicker();
        final XFile? image = await picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1024,
          maxHeight: 1024,
          imageQuality: 85,
        );

        if (image == null) return;

        isUploading.value = true;

        // Upload to Supabase Storage
        final bytes = await File(image.path).readAsBytes();
        final fileName = 'chat_${DateTime.now().millisecondsSinceEpoch}_${image.name}';
        
        final uploadResult = await Supabase.instance.client.storage
            .from('chat-images')
            .uploadBinary(fileName, bytes);

        developer.log('✅ Image uploaded: $uploadResult', name: 'ChatPage');

        // Get public URL
        final imageUrl = Supabase.instance.client.storage
            .from('chat-images')
            .getPublicUrl(fileName);

        developer.log('📸 Image URL: $imageUrl', name: 'ChatPage');

        // Send message with image
        await messagingService.sendMessage(
          receiverId: otherUserId,
          messageText: '📷 Image',
          rideId: rideId,
          imageUrl: imageUrl,
        );

        developer.log('✅ Image message sent', name: 'ChatPage');
      } catch (e) {
        developer.log('❌ Error uploading image: $e', name: 'ChatPage');
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
            Text(otherUserName),
            if (rideId != null)
              Text(
                'About ride',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
        actions: [
          // Phone Call Button
          if (otherUserPhone.value != null)
            IconButton(
              icon: const Icon(Icons.phone, color: Colors.green),
              tooltip: 'Call ${otherUserName}',
              onPressed: () => _makePhoneCall(context, otherUserPhone.value!),
            ),
        ],
      ),
      body: Column(
        children: [
          // Messages list
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: messagingService.getMessages(otherUserId: otherUserId),
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
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No messages yet',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Say hi! 👋',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.grey[600],
                              ),
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
                    final isMine = message['sender_id'] == 
                        Supabase.instance.client.auth.currentUser?.id;

                    final sentAtUtc = DateTime.parse(message['sent_at'] as String).toUtc();
                    final sentAtMalaysia = TimezoneHelper.utcToMalaysia(sentAtUtc);

                    return _MessageBubble(
                      message: message['message_text'] as String?,
                      isMine: isMine,
                      time: sentAtMalaysia,
                      imageUrl: message['image_url'] as String?,
                    );
                  },
                );
              },
            ),
          ),

          // Message input
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
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
                  ),
                  Expanded(
                    child: TextField(
                      controller: messageController,
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                      maxLines: null,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    child: IconButton(
                      icon: const Icon(Icons.send, size: 20),
                      onPressed: () async {
                        if (messageController.text.trim().isEmpty) return;

                        final text = messageController.text.trim();
                        messageController.clear();

                        try {
                          await messagingService.sendMessage(
                            receiverId: otherUserId,
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
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _makePhoneCall(BuildContext context, String phoneNumber) async {
    try {
      // Format Malaysian phone number (remove spaces, ensure +60 prefix)
      String formattedNumber = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
      
      // Add +60 prefix if not present
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
      developer.log('Error making phone call: $e', name: 'ChatPage');
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

