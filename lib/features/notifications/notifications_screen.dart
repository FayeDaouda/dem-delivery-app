import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/error/app_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/client_text.dart';
import '../../core/utils/dem_toast.dart';
import '../../shared/widgets/skeleton_loader.dart';
import 'data/notifications_repository.dart';

const _kTypeIcons = {
  'ORDER_ACCEPTED': Icons.check_circle_outline,
  'ORDER_DELIVERED': Icons.inventory_2_outlined,
  'ORDER_CANCELLED': Icons.cancel_outlined,
  'PROMO': Icons.local_offer_outlined,
  'PAYMENT': Icons.payments_outlined,
  'DRIVER_ASSIGNED': Icons.two_wheeler_outlined,
};

String _relativeTime(DateTime dt) {
  final diff = DateTime.now().difference(dt.toLocal());
  if (diff.inMinutes < 1) return 'À l\'instant';
  if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'Il y a ${diff.inHours} h';
  if (diff.inDays < 7) return 'Il y a ${diff.inDays} j';
  final local = dt.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}/${local.year}';
}

/// Centre de notifications — le backend persiste déjà chaque notif envoyée
/// (voir dem-backend/src/utils/notifications.js:notify), mais rien ne
/// permettait jusqu'ici de les consulter après la disparition de la bannière
/// éphémère de 6s affichée à la réception.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _repo = NotificationsRepository();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _repo.getMyNotifications();
      if (mounted)
        setState(() {
          _items = items;
          _loading = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _error = friendlyError(e);
          _loading = false;
        });
    }
  }

  Future<void> _markAllRead() async {
    final hadUnread = _items.any((n) => n['read'] != true);
    if (!hadUnread) return;
    setState(() {
      _items = _items.map((n) => {...n, 'read': true}).toList();
    });
    try {
      await _repo.markAllRead();
    } catch (e) {
      if (mounted) showDemToast(context, friendlyError(e), isError: true);
    }
  }

  Future<void> _onTapItem(Map<String, dynamic> notif) async {
    if (notif['read'] != true) {
      setState(() {
        final idx = _items.indexWhere((n) => n['id'] == notif['id']);
        if (idx >= 0) _items[idx] = {..._items[idx], 'read': true};
      });
      _repo.markRead(notif['id'] as String).catchError((_) {});
    }
    final data = notif['data'] as Map<String, dynamic>?;
    final orderId = data?['orderId'] as String?;
    final screen = data?['screen'] as String?;
    if (orderId != null && mounted) {
      context.push('/orders/detail', extra: {'orderId': orderId});
    } else if (screen == 'documents' && mounted) {
      context.push('/driver/documents');
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = _items.any((n) => n['read'] != true);
    return Scaffold(
      backgroundColor: AppColors.lightBg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: const BoxDecoration(gradient: AppColors.gradientSplash),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => context.pop(),
                      icon: const Icon(
                        Icons.arrow_back_ios_new,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Notifications',
                      style: ClientText.subtitle.copyWith(color: Colors.white),
                    ),
                    const Spacer(),
                    SizedBox(
                      width: 48,
                      child: hasUnread
                          ? IconButton(
                              onPressed: _markAllRead,
                              icon: const Icon(
                                Icons.done_all,
                                color: Colors.white,
                                size: 20,
                              ),
                              tooltip: 'Tout marquer lu',
                            )
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    itemCount: 6,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, _) => const _NotificationSkeleton(),
                  )
                : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.wifi_off_outlined,
                          color: AppColors.textMuted,
                          size: 48,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: _load,
                          child: const Text(
                            'Réessayer',
                            style: TextStyle(color: AppColors.primary),
                          ),
                        ),
                      ],
                    ),
                  )
                : _items.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.notifications_none_rounded,
                          color: AppColors.lightIconMuted,
                          size: 64,
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Aucune notification pour le moment',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    color: AppColors.primary,
                    onRefresh: _load,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      itemCount: _items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _NotificationTile(
                        notif: _items[i],
                        onTap: () => _onTapItem(_items[i]),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final Map<String, dynamic> notif;
  final VoidCallback onTap;
  const _NotificationTile({required this.notif, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final read = notif['read'] == true;
    final type = notif['type'] as String? ?? '';
    final icon = _kTypeIcons[type] ?? Icons.notifications_outlined;
    final title = notif['title'] as String? ?? '';
    final body = notif['body'] as String? ?? '';
    final createdAt = DateTime.tryParse(notif['createdAt'] as String? ?? '');

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: read
              ? null
              : Border.all(color: AppColors.primary.withValues(alpha: 0.30)),
          boxShadow: AppShadows.card,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: (read ? AppColors.textMuted : AppColors.primary)
                    .withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: read ? AppColors.textMuted : AppColors.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            color: AppColors.textDark,
                            fontSize: 14,
                            fontWeight: read
                                ? FontWeight.w600
                                : FontWeight.w800,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!read) ...[
                        const SizedBox(width: 6),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    body,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    createdAt != null ? _relativeTime(createdAt) : '',
                    style: const TextStyle(
                      color: AppColors.lightIconMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationSkeleton extends StatelessWidget {
  const _NotificationSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 84,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          const SkeletonBox(
            width: 40,
            height: 40,
            borderRadius: BorderRadius.all(Radius.circular(20)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const SkeletonBox(width: 140, height: 13),
                const SizedBox(height: 8),
                SkeletonBox(
                  width: MediaQuery.of(context).size.width * 0.5,
                  height: 11,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
