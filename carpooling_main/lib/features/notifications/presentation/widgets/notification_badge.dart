import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:carpooling_main/features/notifications/presentation/providers/notification_providers.dart';

/// Notification badge widget that shows unread count
/// Displays a red badge with count on top of an icon
class NotificationBadge extends ConsumerWidget {
  final VoidCallback? onTap;

  const NotificationBadge({
    super.key,
    this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadCountAsync = ref.watch(unreadNotificationCountProvider);

    return unreadCountAsync.when(
      data: (count) => _buildBadge(context, count),
      loading: () => _buildBadge(context, 0),
      error: (_, __) => _buildBadge(context, 0),
    );
  }

  Widget _buildBadge(BuildContext context, int count) {
    return IconButton(
      onPressed: onTap,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.notifications_outlined),
          if (count > 0)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    width: 1.5,
                  ),
                ),
                constraints: const BoxConstraints(
                  minWidth: 18,
                  minHeight: 18,
                ),
                child: Center(
                  child: Text(
                    count > 99 ? '99+' : count.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      tooltip: count > 0 ? '$count unread notification${count != 1 ? 's' : ''}' : 'Notifications',
    );
  }
}

