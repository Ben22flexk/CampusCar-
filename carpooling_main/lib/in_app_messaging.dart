import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Message Model
@immutable
class ChatMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String? text;
  final String? imageUrl;
  final String? imagePath;
  final DateTime timestamp;
  final bool isMe;
  final MessageType type;

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    this.text,
    this.imageUrl,
    this.imagePath,
    required this.timestamp,
    required this.isMe,
    required this.type,
  });
}

enum MessageType {
  text,
  image,
  autoReply,
}

// Chat Provider
final chatMessagesProvider = StateProvider<List<ChatMessage>>((ref) {
  // Mock initial messages
  final now = DateTime.now();
  return [
    ChatMessage(
      id: '1',
      senderId: 'driver1',
      senderName: 'Ahmad Ibrahim',
      text: 'Hello! Thanks for booking.',
      timestamp: now.subtract(const Duration(minutes: 10)),
      isMe: false,
      type: MessageType.text,
    ),
    ChatMessage(
      id: '2',
      senderId: 'passenger1',
      senderName: 'Me',
      text: 'Hi! What time will you pick me up?',
      timestamp: now.subtract(const Duration(minutes: 8)),
      isMe: true,
      type: MessageType.text,
    ),
    ChatMessage(
      id: '3',
      senderId: 'driver1',
      senderName: 'Ahmad Ibrahim',
      text: 'I\'ll be there in 5 minutes',
      timestamp: now.subtract(const Duration(minutes: 5)),
      isMe: false,
      type: MessageType.autoReply,
    ),
  ];
});

// In-App Messaging Page
class InAppMessagingPage extends HookConsumerWidget {
  final String recipientName;
  final String? recipientPhone; // Made optional, will fetch from DB
  final String recipientAvatar;
  final String recipientId;
  final bool isDriver;

  const InAppMessagingPage({
    super.key,
    required this.recipientName,
    this.recipientPhone,
    required this.recipientAvatar,
    required this.recipientId,
    this.isDriver = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messageController = useTextEditingController();
    final scrollController = useScrollController();
    final messages = ref.watch(chatMessagesProvider);
    final theme = Theme.of(context);
    final showAutoReplies = useState<bool>(false);
    final actualPhoneNumber = useState<String?>(recipientPhone);

    // Fetch phone number from database if not provided
    useEffect(() {
      if (actualPhoneNumber.value == null || actualPhoneNumber.value!.isEmpty) {
        Future.microtask(() async {
          try {
            final profile = await Supabase.instance.client
                .from('profiles')
                .select('phone_number')
                .eq('id', recipientId)
                .maybeSingle();
            
            if (profile != null && profile['phone_number'] != null) {
              actualPhoneNumber.value = profile['phone_number'] as String;
            }
          } catch (e) {
            debugPrint('Error fetching phone number: $e');
          }
        });
      }
      return null;
    }, []);

    // Scroll to bottom when new message arrives
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scrollController.hasClients) {
          scrollController.animateTo(
            scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
      return null;
    }, [messages.length]);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: <Widget>[
            CircleAvatar(
              radius: 18,
              backgroundImage: NetworkImage(recipientAvatar),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    recipientName,
                    style: const TextStyle(fontSize: 16),
                  ),
                  Text(
                    isDriver ? 'Driver' : 'Passenger',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade300,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: <Widget>[
          // Phone Call Icon
          if (actualPhoneNumber.value != null && actualPhoneNumber.value!.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.phone, color: Colors.green),
              tooltip: 'Call ${recipientName}',
              onPressed: () => _makePhoneCall(context, actualPhoneNumber.value!),
            ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'block') {
                _showBlockDialog(context, recipientName);
              } else if (value == 'report') {
                _showReportDialog(context, recipientName);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'block',
                child: Row(
                  children: <Widget>[
                    Icon(Icons.block, size: 20),
                    SizedBox(width: 8),
                    Text('Block User'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'report',
                child: Row(
                  children: <Widget>[
                    Icon(Icons.flag, size: 20),
                    SizedBox(width: 8),
                    Text('Report'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          // Messages List
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final message = messages[index];
                return _MessageBubble(
                  message: message,
                  onImageTap: (imagePath) =>
                      _showImagePreview(context, imagePath),
                );
              },
            ),
          ),

          // Auto-Reply Buttons (for passengers mainly)
          if (showAutoReplies.value && !isDriver)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                border: Border(
                  top: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: <Widget>[
                    _QuickReplyButton(
                      label: 'On my way',
                      onPressed: () => _sendQuickReply(
                        ref,
                        'On my way',
                        messageController,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _QuickReplyButton(
                      label: 'Running late',
                      onPressed: () => _sendQuickReply(
                        ref,
                        'Running late, sorry!',
                        messageController,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _QuickReplyButton(
                      label: 'I\'m here',
                      onPressed: () => _sendQuickReply(
                        ref,
                        'I\'m here',
                        messageController,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _QuickReplyButton(
                      label: 'Thank you',
                      onPressed: () => _sendQuickReply(
                        ref,
                        'Thank you!',
                        messageController,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Driver Quick Replies
          if (showAutoReplies.value && isDriver)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                border: Border(
                  top: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: <Widget>[
                    _QuickReplyButton(
                      label: 'I\'m here',
                      onPressed: () => _sendQuickReply(
                        ref,
                        'I\'m here',
                        messageController,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _QuickReplyButton(
                      label: 'Will arrive in 2 min',
                      onPressed: () => _sendQuickReply(
                        ref,
                        'Will arrive in 2 minutes',
                        messageController,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _QuickReplyButton(
                      label: 'On the way',
                      onPressed: () => _sendQuickReply(
                        ref,
                        'On the way',
                        messageController,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _QuickReplyButton(
                      label: 'Traffic delay',
                      onPressed: () => _sendQuickReply(
                        ref,
                        'Traffic is heavy, will be slightly delayed',
                        messageController,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Input Area
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: <Widget>[
                  // Attach Photo Button
                  IconButton(
                    icon: Icon(
                      Icons.add_photo_alternate,
                      color: theme.colorScheme.primary,
                    ),
                    onPressed: () => _showImagePickerOptions(context, ref),
                  ),
                  // Quick Reply Toggle
                  IconButton(
                    icon: Icon(
                      showAutoReplies.value
                          ? Icons.keyboard
                          : Icons.flash_on,
                      color: theme.colorScheme.primary,
                    ),
                    onPressed: () {
                      showAutoReplies.value = !showAutoReplies.value;
                    },
                  ),
                  // Text Input
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
                        fillColor: Colors.grey.shade100,
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
                  // Send Button
                  CircleAvatar(
                    backgroundColor: theme.colorScheme.primary,
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white),
                      onPressed: () => _sendMessage(
                        ref,
                        messageController,
                        context,
                      ),
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
      debugPrint('Error making phone call: $e');
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

  void _sendMessage(
    WidgetRef ref,
    TextEditingController controller,
    BuildContext context,
  ) {
    final text = controller.text.trim();
    if (text.isEmpty) return;

    // Profanity filter
    if (_containsProfanity(text)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your message contains inappropriate language. Please revise.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final messages = ref.read(chatMessagesProvider);
    final newMessage = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      senderId: 'me',
      senderName: 'Me',
      text: text,
      timestamp: DateTime.now(),
      isMe: true,
      type: MessageType.text,
    );

    ref.read(chatMessagesProvider.notifier).state = [...messages, newMessage];
    controller.clear();

    // Simulate response after 2 seconds
    Future.delayed(const Duration(seconds: 2), () {
      _simulateResponse(ref);
    });
  }

  void _sendQuickReply(
    WidgetRef ref,
    String text,
    TextEditingController controller,
  ) {
    final messages = ref.read(chatMessagesProvider);
    final newMessage = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      senderId: 'me',
      senderName: 'Me',
      text: text,
      timestamp: DateTime.now(),
      isMe: true,
      type: MessageType.autoReply,
    );

    ref.read(chatMessagesProvider.notifier).state = [...messages, newMessage];
  }

  void _simulateResponse(WidgetRef ref) {
    final messages = ref.read(chatMessagesProvider);
    final responses = [
      'Got it!',
      'Thanks for letting me know',
      'See you soon!',
      'Okay, thanks!',
    ];
    
    final newMessage = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      senderId: recipientId,
      senderName: recipientName,
      text: responses[DateTime.now().millisecond % responses.length],
      timestamp: DateTime.now(),
      isMe: false,
      type: MessageType.text,
    );

    ref.read(chatMessagesProvider.notifier).state = [...messages, newMessage];
  }

  bool _containsProfanity(String text) {
    final profanityList = [
      'fuck',
      'shit',
      'damn',
      'bitch',
      'asshole',
      'bastard',
      'puki',
      'lancau',
      'kimak',
      'bodoh',
      'bangang',
    ];

    final lowerText = text.toLowerCase();
    return profanityList.any((word) => lowerText.contains(word));
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
                'Share Image',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Colors.blue),
                title: const Text('Take Photo'),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndSendImage(ImageSource.camera, ref, context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Colors.green),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndSendImage(ImageSource.gallery, ref, context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndSendImage(
    ImageSource source,
    WidgetRef ref,
    BuildContext context,
  ) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        final messages = ref.read(chatMessagesProvider);
        final newMessage = ChatMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          senderId: 'me',
          senderName: 'Me',
          imagePath: pickedFile.path,
          timestamp: DateTime.now(),
          isMe: true,
          type: MessageType.image,
        );

        ref.read(chatMessagesProvider.notifier).state = [
          ...messages,
          newMessage,
        ];
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error selecting image'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showImagePreview(BuildContext context, String imagePath) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          children: <Widget>[
            Center(
              child: InteractiveViewer(
                child: Image.file(
                  File(imagePath),
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: CircleAvatar(
                backgroundColor: Colors.black54,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showBlockDialog(BuildContext context, String name) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Block User'),
        content: Text('Are you sure you want to block $name?'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$name has been blocked')),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Block'),
          ),
        ],
      ),
    );
  }

  void _showReportDialog(BuildContext context, String name) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Report User'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Report $name for inappropriate behavior?'),
            const SizedBox(height: 16),
            const TextField(
              decoration: InputDecoration(
                labelText: 'Reason (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Report submitted successfully'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Report'),
          ),
        ],
      ),
    );
  }
}

// Message Bubble Widget
class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final Function(String)? onImageTap;

  const _MessageBubble({
    required this.message,
    this.onImageTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMe = message.isMe;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          if (!isMe) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Text(
                message.senderName[0].toUpperCase(),
                style: TextStyle(
                  fontSize: 14,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isMe
                        ? theme.colorScheme.primary
                        : Colors.grey.shade200,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: isMe
                          ? const Radius.circular(16)
                          : const Radius.circular(4),
                      bottomRight: isMe
                          ? const Radius.circular(4)
                          : const Radius.circular(16),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      // Text Message
                      if (message.text != null)
                        Text(
                          message.text!,
                          style: TextStyle(
                            color: isMe ? Colors.white : Colors.black87,
                            fontSize: 15,
                          ),
                        ),
                      // Image Message
                      if (message.imagePath != null || message.imageUrl != null)
                        GestureDetector(
                          onTap: () {
                            if (message.imagePath != null) {
                              onImageTap?.call(message.imagePath!);
                            }
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: message.imagePath != null
                                ? Image.file(
                                    File(message.imagePath!),
                                    width: 200,
                                    height: 200,
                                    fit: BoxFit.cover,
                                  )
                                : Image.network(
                                    message.imageUrl!,
                                    width: 200,
                                    height: 200,
                                    fit: BoxFit.cover,
                                  ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatTime(message.timestamp),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          if (isMe) const SizedBox(width: 8),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else {
      return '${time.day}/${time.month}/${time.year}';
    }
  }
}

// Quick Reply Button Widget
class _QuickReplyButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _QuickReplyButton({
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      child: Text(label),
    );
  }
}

