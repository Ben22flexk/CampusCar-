import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:carpooling_driver/features/notifications/presentation/providers/notification_providers.dart';
import 'package:carpooling_driver/features/notifications/presentation/widgets/notification_item.dart';
import 'package:carpooling_driver/features/notifications/domain/entities/notification_entity.dart';

/// Notifications page showing all notifications with filter options
class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  bool _showUnreadOnly = false;
  bool _isMarkingAllRead = false;
  bool _isClearingRead = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notificationsAsync = ref.watch(notificationsStreamProvider);
    final actions = ref.watch(notificationActionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset(
              'assets/images/campuscar_logo.png',
              height: 32,
              errorBuilder: (context, error, stackTrace) {
                return Icon(Icons.notifications, color: theme.colorScheme.primary);
              },
            ),
            const SizedBox(width: 12),
            const Text('Notifications'),
          ],
        ),
        elevation: 2,
        actions: [
          IconButton(
            icon: Icon(_showUnreadOnly ? Icons.filter_list_off : Icons.filter_list),
            tooltip: _showUnreadOnly ? 'Show all' : 'Show unread only',
            onPressed: () {
              setState(() {
                _showUnreadOnly = !_showUnreadOnly;
              });
            },
          ),
          PopupMenuButton<String>(
            enabled: !_isMarkingAllRead && !_isClearingRead,
            onSelected: (value) async {
              switch (value) {
                case 'mark_all_read':
                  setState(() => _isMarkingAllRead = true);
                  try {
                    await actions.markAllAsRead();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('All notifications marked as read'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  } finally {
                    if (mounted) {
                      setState(() => _isMarkingAllRead = false);
                    }
                  }
                  break;
                case 'clear_read':
                  await _showClearConfirmation(context, actions);
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'mark_all_read',
                enabled: !_isMarkingAllRead,
                child: Row(
                  children: [
                    if (_isMarkingAllRead)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      const Icon(Icons.done_all, size: 20),
                    const SizedBox(width: 12),
                    const Text('Mark all as read'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'clear_read',
                enabled: !_isClearingRead,
                child: Row(
                  children: [
                    if (_isClearingRead)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      const Icon(Icons.delete_sweep, size: 20),
                    const SizedBox(width: 12),
                    const Text('Clear read notifications'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: notificationsAsync.when(
        data: (notifications) {
          final filteredNotifications = _showUnreadOnly
              ? notifications.where((n) => !n.isRead).toList()
              : notifications;

          if (filteredNotifications.isEmpty) {
            return _buildEmptyState(context, _showUnreadOnly);
          }

          return RefreshIndicator(
            onRefresh: () async {
              actions.refresh();
              await Future.delayed(const Duration(milliseconds: 500));
            },
            child: ListView.builder(
              itemCount: filteredNotifications.length,
              itemBuilder: (context, index) {
                final notification = filteredNotifications[index];
                return NotificationItem(
                  notification: notification,
                  onTap: () => _handleNotificationTap(context, notification, actions),
                  onDismiss: () => actions.deleteNotification(notification.id),
                );
              },
            ),
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(),
        ),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.red,
              ),
              const SizedBox(height: 16),
              Text(
                'Failed to load notifications',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                error.toString(),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.textTheme.bodySmall?.color,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => ref.invalidate(notificationsStreamProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool showingUnreadOnly) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // CampusCar Logo
          Container(
            height: 120,
            width: 120,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.05),
              shape: BoxShape.circle,
            ),
            child: Image.asset(
              'assets/images/campuscar_logo.png',
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return Icon(
                  showingUnreadOnly ? Icons.notifications_active : Icons.notifications_none,
                  size: 60,
                  color: theme.colorScheme.primary.withOpacity(0.3),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          Text(
            showingUnreadOnly ? 'No unread notifications' : 'No notifications yet',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              showingUnreadOnly
                  ? 'All caught up! 🎉\nYou\'re up to date with all your notifications'
                  : 'You\'ll see updates about your rides here\nStart driving to get notifications!',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.textTheme.bodySmall?.color,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleNotificationTap(
    BuildContext context,
    NotificationEntity notification,
    NotificationActions actions,
  ) async {
    // Mark as read if unread
    if (!notification.isRead) {
      await actions.markAsRead(notification.id);
    }

    // Navigate to related screen based on notification type
    if (mounted) {
      _navigateToRelatedScreen(context, notification);
    }
  }

  void _navigateToRelatedScreen(
    BuildContext context,
    NotificationEntity notification,
  ) {
    // TODO: Implement navigation based on notification type
    // For now, just show a dialog with notification details
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${notification.getIconEmoji()} ${notification.title}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(notification.message),
            if (notification.data != null) ...[
              const SizedBox(height: 16),
              Text(
                'Additional Info:',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Text(
                notification.data.toString(),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showClearConfirmation(
    BuildContext context,
    NotificationActions actions,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _ClearConfirmationDialog(),
    );

    if (confirmed == true) {
      setState(() => _isClearingRead = true);
      try {
        await actions.clearReadNotifications();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Read notifications cleared'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isClearingRead = false);
        }
      }
    }
  }
}

class _ClearConfirmationDialog extends StatefulWidget {
  @override
  State<_ClearConfirmationDialog> createState() => _ClearConfirmationDialogState();
}

class _ClearConfirmationDialogState extends State<_ClearConfirmationDialog> {
  final bool _isClearing = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Clear Read Notifications?'),
      content: const Text(
        'This will permanently delete all notifications you\'ve already read. This action cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: _isClearing ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _isClearing ? null : () => Navigator.pop(context, true),
          style: TextButton.styleFrom(
            foregroundColor: Colors.red,
          ),
          child: _isClearing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Clear'),
        ),
      ],
    );
  }
}

