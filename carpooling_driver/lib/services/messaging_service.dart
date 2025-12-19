import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:developer' as developer;
import '../utils/profanity_filter.dart';

class MessagingService {
  final _supabase = Supabase.instance.client;

  /// Send a message
  Future<String> sendMessage({
    required String receiverId,
    required String messageText,
    String? rideId,
    String? imageUrl,
  }) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) {
        throw Exception('User not authenticated');
      }

      // Validate message is not empty
      if (messageText.trim().isEmpty && (imageUrl == null || imageUrl.trim().isEmpty)) {
        throw Exception('Message cannot be empty. Provide either text or an image.');
      }

      // Check for profanity in text messages
      if (messageText.trim().isNotEmpty) {
        if (ProfanityFilter.hasProfanity(messageText)) {
          final badWord = ProfanityFilter.getFirstProfaneWord(messageText);
          throw Exception('Profanity detected! Please avoid vulgar words. (Found: "$badWord")');
        }
      }

      final result = await _supabase.rpc('send_message', params: {
        'p_sender_id': currentUserId,
        'p_recipient_id': receiverId,
        'p_ride_id': rideId,
        'p_message_text': messageText.trim(),
        'p_image_url': imageUrl,
        'p_sent_at': DateTime.now().toUtc().toIso8601String(),
      });

      developer.log('✅ Message sent', name: 'MessagingService');
      return result as String;
    } catch (e) {
      developer.log('❌ Error sending message: $e', name: 'MessagingService');
      rethrow;
    }
  }

  /// Get messages with a specific user (real-time)
  Stream<List<Map<String, dynamic>>> getMessages({
    required String otherUserId,
    String? rideId,
  }) async* {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null) {
      yield [];
      return;
    }

    // Listen to all messages and filter in code
    final stream = _supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .order('sent_at', ascending: true);

    await for (final data in stream) {
      // Filter to only messages between current user and other user
      final filtered = data.where((msg) {
        final senderId = msg['sender_id'] as String;
        final recipientId = msg['recipient_id'] as String;
        return (senderId == currentUserId && recipientId == otherUserId) ||
               (senderId == otherUserId && recipientId == currentUserId);
      }).toList();

      yield filtered;
    }
  }

  /// Mark messages as read
  Future<void> markAsRead(String senderId) async {
    try {
      await _supabase.rpc('mark_messages_read', params: {
        'p_sender_id': senderId,
      });
      developer.log('✅ Messages marked as read', name: 'MessagingService');
    } catch (e) {
      developer.log('❌ Error marking as read: $e', name: 'MessagingService');
    }
  }

  /// Get unread count
  Future<int> getUnreadCount() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return 0;

    try {
      final response = await _supabase
          .from('messages')
          .select()
          .eq('recipient_id', userId)
          .eq('is_read', false);

      return (response as List).length;
    } catch (e) {
      developer.log('❌ Error getting unread count: $e', name: 'MessagingService');
      return 0;
    }
  }

  /// Get list of conversations (people you've messaged)
  Future<List<Map<String, dynamic>>> getConversations() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return [];

    try {
      // Get unique user IDs from messages
      final messages = await _supabase
          .from('messages')
          .select('sender_id, recipient_id, message_text, sent_at, is_read')
          .or('sender_id.eq.$userId,recipient_id.eq.$userId')
          .order('sent_at', ascending: false);

      // Group by other user
      final Map<String, Map<String, dynamic>> conversations = {};

      for (final msg in messages as List) {
        final otherUserId = msg['sender_id'] == userId
            ? msg['recipient_id']
            : msg['sender_id'];

        if (!conversations.containsKey(otherUserId)) {
          conversations[otherUserId] = {
            'other_user_id': otherUserId,
            'last_message': msg['message_text'] ?? '[Image]',
            'last_message_time': msg['sent_at'],
            'unread_count': 0,
          };
        }

        // Count unread
        if (msg['recipient_id'] == userId && msg['is_read'] == false) {
          conversations[otherUserId]!['unread_count'] =
              (conversations[otherUserId]!['unread_count'] as int) + 1;
        }
      }

      // Get user profiles
      final List<Map<String, dynamic>> result = [];
      for (final conv in conversations.values) {
        final profile = await _supabase
            .from('profiles')
            .select('full_name, email')
            .eq('id', conv['other_user_id'])
            .maybeSingle();

        if (profile != null) {
          result.add({
            ...conv,
            'other_user_name': profile['full_name'],
            'other_user_email': profile['email'],
          });
        }
      }

      return result;
    } catch (e) {
      developer.log('❌ Error getting conversations: $e', name: 'MessagingService');
      return [];
    }
  }
}
