import 'package:carpooling_driver/features/notifications/domain/entities/notification_entity.dart';

/// Data model for Notification that handles JSON serialization
/// Maps between Supabase JSON and domain entity
class NotificationModel {
  final String id;
  final String userId;
  final String title;
  final String message;
  final String type;
  final String? relatedId;
  final bool isRead;
  final String createdAt;
  final String? readAt;
  final Map<String, dynamic>? data;

  const NotificationModel({
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

  /// Create model from JSON (Supabase response)
  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      title: json['title'] as String,
      message: json['message'] as String,
      type: (json['type'] as String?) ?? 'general', // Default to 'general' if null
      relatedId: json['related_id'] as String?,
      isRead: json['is_read'] as bool? ?? false,
      createdAt: json['created_at'] as String,
      readAt: json['read_at'] as String?,
      data: json['data'] as Map<String, dynamic>?,
    );
  }

  /// Convert model to JSON (for Supabase updates)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'title': title,
      'message': message,
      'type': type,
      'related_id': relatedId,
      'is_read': isRead,
      'created_at': createdAt,
      'read_at': readAt,
      'data': data,
    };
  }

  /// Convert model to domain entity
  NotificationEntity toDomain() {
    return NotificationEntity(
      id: id,
      userId: userId,
      title: title,
      message: message,
      type: NotificationType.fromString(type),
      relatedId: relatedId,
      isRead: isRead,
      createdAt: DateTime.parse(createdAt),
      readAt: readAt != null ? DateTime.parse(readAt!) : null,
      data: data,
    );
  }

  /// Create model from domain entity
  factory NotificationModel.fromDomain(NotificationEntity entity) {
    return NotificationModel(
      id: entity.id,
      userId: entity.userId,
      title: entity.title,
      message: entity.message,
      type: entity.type.value,
      relatedId: entity.relatedId,
      isRead: entity.isRead,
      createdAt: entity.createdAt.toIso8601String(),
      readAt: entity.readAt?.toIso8601String(),
      data: entity.data,
    );
  }

  /// Create a copy with modified fields
  NotificationModel copyWith({
    String? id,
    String? userId,
    String? title,
    String? message,
    String? type,
    String? relatedId,
    bool? isRead,
    String? createdAt,
    String? readAt,
    Map<String, dynamic>? data,
  }) {
    return NotificationModel(
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
}

