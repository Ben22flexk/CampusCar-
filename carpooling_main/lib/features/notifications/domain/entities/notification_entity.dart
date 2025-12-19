import 'package:equatable/equatable.dart';

/// Domain entity representing a notification
/// This is a pure business object with no external dependencies
class NotificationEntity extends Equatable {
  final String id;
  final String userId;
  final String title;
  final String message;
  final NotificationType type;
  final String? relatedId;
  final bool isRead;
  final DateTime createdAt;
  final DateTime? readAt;
  final Map<String, dynamic>? data;

  const NotificationEntity({
    required this.id,
    required this.userId,
    required this.title,
    required this.message,
    required this.type,
    this.relatedId,
    required this.isRead,
    required this.createdAt,
    this.readAt,
    this.data,
  });

  @override
  List<Object?> get props => [
        id,
        userId,
        title,
        message,
        type,
        relatedId,
        isRead,
        createdAt,
        readAt,
        data,
      ];

  /// Create a copy with modified fields
  NotificationEntity copyWith({
    String? id,
    String? userId,
    String? title,
    String? message,
    NotificationType? type,
    String? relatedId,
    bool? isRead,
    DateTime? createdAt,
    DateTime? readAt,
    Map<String, dynamic>? data,
  }) {
    return NotificationEntity(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      message: message ?? this.message,
      type: type ?? this.type,
      relatedId: relatedId ?? this.relatedId,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt ?? this.createdAt,
      readAt: readAt ?? this.readAt,
      data: data ?? this.data,
    );
  }

  /// Mark notification as read
  NotificationEntity markAsRead() {
    return copyWith(
      isRead: true,
      readAt: DateTime.now(),
    );
  }

  /// Get icon based on notification type
  String getIconEmoji() {
    switch (type) {
      case NotificationType.rideOffer:
        return '🚗';
      case NotificationType.rideAccepted:
        return '✅';
      case NotificationType.rideCancelled:
        return '❌';
      case NotificationType.newMessage:
        return '💬';
      case NotificationType.bookingConfirmed:
        return '🎉';
      case NotificationType.paymentReceived:
        return '💰';
      case NotificationType.rideReminder:
        return '⏰';
      case NotificationType.system:
        return '📢';
    }
  }

  /// Get color based on notification type
  String getColorHex() {
    switch (type) {
      case NotificationType.rideOffer:
        return '#4CAF50'; // Green
      case NotificationType.rideAccepted:
        return '#2196F3'; // Blue
      case NotificationType.rideCancelled:
        return '#F44336'; // Red
      case NotificationType.newMessage:
        return '#9C27B0'; // Purple
      case NotificationType.bookingConfirmed:
        return '#FF9800'; // Orange
      case NotificationType.paymentReceived:
        return '#4CAF50'; // Green
      case NotificationType.rideReminder:
        return '#FFC107'; // Amber
      case NotificationType.system:
        return '#607D8B'; // Blue Grey
    }
  }
}

/// Notification types matching Supabase enum
enum NotificationType {
  rideOffer('ride_offer'),
  rideAccepted('ride_accepted'),
  rideCancelled('ride_cancelled'),
  newMessage('new_message'),
  bookingConfirmed('booking_confirmed'),
  paymentReceived('payment_received'),
  rideReminder('ride_reminder'),
  system('system');

  final String value;
  const NotificationType(this.value);

  static NotificationType fromString(String value) {
    switch (value) {
      case 'ride_offer':
        return NotificationType.rideOffer;
      case 'ride_accepted':
        return NotificationType.rideAccepted;
      case 'ride_cancelled':
        return NotificationType.rideCancelled;
      case 'new_message':
        return NotificationType.newMessage;
      case 'booking_confirmed':
        return NotificationType.bookingConfirmed;
      case 'payment_received':
        return NotificationType.paymentReceived;
      case 'ride_reminder':
        return NotificationType.rideReminder;
      case 'system':
        return NotificationType.system;
      default:
        return NotificationType.system;
    }
  }
}

