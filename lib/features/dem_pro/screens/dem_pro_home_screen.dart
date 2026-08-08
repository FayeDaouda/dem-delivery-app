import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/api/api_client.dart';
import '../../../core/router/app_startup_notifier.dart';
import '../../../core/services/places_autocomplete_service.dart';
import '../../../core/storage/auth_storage.dart';
import '../../home_driver/navigation/navigation_service.dart';
import '../../profile/data/profile_repository.dart';
import '../../deliveries/data/orders_repository.dart';
import '../data/dem_pro_repository.dart';
import '../../../shared/widgets/place_suggestions_list.dart';
import '../../../shared/widgets/promo_highlight_popup.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/client_text.dart';
import '../../../core/utils/price_format.dart';
import '../widgets/dem_pro_nav_bar.dart';
import '../../../core/utils/location_gate.dart';
import '../../../shared/widgets/swipe_to_confirm.dart';

const _sectorLabels = {
  'commerce': 'Commerce',
  'restauration': 'Restauration',
  'services': 'Services',
  'artisanat': 'Artisanat',
  'autre': 'Autre',
};

const _volumeLabels = {
  'low': '1 à 4 livraisons / semaine',
  'medium': '5 à 8 livraisons / semaine',
  'high': '9 ou plus / semaine',
};

const _dayNames = [
  'Lundi',
  'Mardi',
  'Mercredi',
  'Jeudi',
  'Vendredi',
  'Samedi',
  'Dimanche',
];
const _monthNames = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];

// ── Filtre livraisons ─────────────────────────────────────────────────────────
enum _OrderFilter {
  all('Toutes'),
  active('En cours'),
  delivered('Livrées'),
  cancelled('Annulées');

  final String label;
  const _OrderFilter(this.label);
}

enum _ViewType { orders, batches }

// ── Helpers statut tournée ────────────────────────────────────────────────────
String _batchStatusLabel(String s) => switch (s) {
  'PENDING' => 'En attente',
  'ACCEPTED' => 'Livreur assigné',
  'IN_PROGRESS' => 'En cours',
  'COMPLETED' => 'Terminée',
  'CANCELLED' => 'Annulée',
  'SCHEDULED' => 'Programmée',
  _ => s,
};

Color _batchStatusColor(String s) => switch (s) {
  'PENDING' => AppColors.warning,
  'ACCEPTED' => AppColors.primary,
  'IN_PROGRESS' => AppColors.primary,
  'COMPLETED' => AppColors.successLight,
  'CANCELLED' => AppColors.error,
  'SCHEDULED' => AppColors.textMuted,
  _ => AppColors.textMuted,
};

// ── Helpers statut ────────────────────────────────────────────────────────────
bool _isActiveStatus(String s) => const {
  'PENDING',
  'ACCEPTED',
  'PICKED_UP',
  'IN_TRANSIT',
  'SCHEDULED',
}.contains(s);

String _statusLabel(String s) => switch (s) {
  'PENDING' => 'En attente',
  'ACCEPTED' => 'Acceptée',
  'PICKED_UP' => 'Récupéré',
  'IN_TRANSIT' => 'En route',
  'DELIVERED' => 'Livré',
  'CANCELLED' => 'Annulé',
  'SCHEDULED' => 'Programmée',
  _ => s,
};

Color _statusColor(String s) => switch (s) {
  'PENDING' => AppColors.warning,
  'ACCEPTED' => AppColors.primary,
  'PICKED_UP' => AppColors.primary,
  'IN_TRANSIT' => AppColors.primary,
  'DELIVERED' => AppColors.successLight,
  'CANCELLED' => AppColors.error,
  'SCHEDULED' => AppColors.textMuted,
  _ => AppColors.textMuted,
};

String _shortAddress(String addr) => addr.split(',').first.trim();

void _navigateToOrder(BuildContext context, Map<String, dynamic> order) {
  final status = order['status'] as String? ?? '';
  if (status == 'PENDING') {
    context.push('/dem-pro/orders/confirmation', extra: order);
  } else if (const {'ACCEPTED', 'PICKED_UP', 'IN_TRANSIT'}.contains(status)) {
    final driverId =
        (order['driver'] as Map?)?['id'] as String? ??
        order['driverId'] as String? ??
        '';
    context.push(
      '/dem-pro/orders/tracking',
      extra: {
        'orderId': order['id'],
        'driverId': driverId,
        'initialOrder': order,
      },
    );
  } else if (status == 'DELIVERED' ||
      status == 'CANCELLED' ||
      status == 'SCHEDULED') {
    context.push('/dem-pro/orders/receipt', extra: order);
  }
}

String _driverInitials(String? name) {
  if (name == null || name.isEmpty) return '?';
  final p = name.trim().split(RegExp(r'\s+'));
  return p.length >= 2
      ? '${p[0][0]}${p[1][0]}'.toUpperCase()
      : p[0][0].toUpperCase();
}

String _timeAgo(String? iso) {
  if (iso == null) return '';
  final dt = DateTime.tryParse(iso);
  if (dt == null) return '';
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'À l\'instant';
  if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes}min';
  if (diff.inHours < 24) return 'Il y a ${diff.inHours}h';
  return 'Il y a ${diff.inDays}j';
}

String _formatDateTime(String? iso) {
  final dt = iso != null ? DateTime.tryParse(iso)?.toLocal() : null;
  if (dt == null) return '';
  const m = [
    'jan.',
    'fév.',
    'mars',
    'avr.',
    'mai',
    'juin',
    'juil.',
    'août',
    'sep.',
    'oct.',
    'nov.',
    'déc.',
  ];
  const d = ['Lun.', 'Mar.', 'Mer.', 'Jeu.', 'Ven.', 'Sam.', 'Dim.'];
  final h = dt.hour.toString().padLeft(2, '0');
  final mn = dt.minute.toString().padLeft(2, '0');
  return '${d[dt.weekday - 1]} ${dt.day} ${m[dt.month - 1]} · $h:$mn';
}

// ── Palette — alignée sur le thème Client (AppColors), toujours claire ───────
// Anciennement adaptative clair/sombre (jamais persistée, jamais propagée aux
// écrans poussés depuis l'accueil — voir audit). DEM Pro adopte maintenant le
// même thème que le rôle Client : conservé comme sac de constantes pratique
// (déjà threadé dans ~40 widgets de ce fichier) plutôt que de tout retirer.
class _T {
  const _T();

  Color get scaffoldBg => AppColors.lightBg;
  Color get cardBg => Colors.white;
  Color get cardBg2 => AppColors.lightFill;
  Color get cardBg3 => AppColors.lightFill;
  Color get border => AppColors.lightBorder;
  Color get text => AppColors.textDark;
  Color get muted => AppColors.textMuted;

  List<Color> get statGradient => [Colors.white, AppColors.lightBg];
  List<Color> get headerCardGradient => [Colors.white, AppColors.lightBg];
}

// ── Physique du swipe entre onglets — moins nerveuse qu'un PageView par défaut.
// Un petit flick très court génère déjà une vélocité largement au-dessus de la
// tolérance par défaut de ScrollPhysics (proche de 0), ce qui fait basculer de
// page au moindre effleurement. On relève cette tolérance pour qu'il faille un
// vrai geste de swipe (vélocité franche ou plus de la moitié de l'écran
// parcourue) avant de committer le changement de page.
class _PremiumPageScrollPhysics extends PageScrollPhysics {
  const _PremiumPageScrollPhysics({super.parent});

  @override
  _PremiumPageScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _PremiumPageScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  SpringDescription get spring =>
      SpringDescription.withDampingRatio(mass: 0.7, stiffness: 130, ratio: 1.1);

  @override
  Tolerance toleranceFor(ScrollMetrics metrics) =>
      const Tolerance(velocity: 500, distance: 0.01);
}

// ── Transition premium entre onglets : léger fondu + zoom-out proportionnel à
// la distance de la page courante, façon carrousel — purement compositing
// (Transform/Opacity), donc sans impact sur l'état conservé des onglets.
class _PageTransition extends StatelessWidget {
  final PageController controller;
  final int index;
  final Widget child;
  const _PageTransition({
    required this.controller,
    required this.index,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    child: child,
    builder: (context, child) {
      double page = index.toDouble();
      if (controller.hasClients && controller.position.haveDimensions) {
        page = controller.page ?? index.toDouble();
      }
      final delta = (page - index).clamp(-1.0, 1.0);
      final scale = 1 - (delta.abs() * 0.05);
      final opacity = (1 - (delta.abs() * 0.4)).clamp(0.0, 1.0);
      return Opacity(
        opacity: opacity,
        child: Transform.scale(scale: scale, child: child),
      );
    },
  );
}

// ─────────────────────────────────────────────────────────────────────────────

class DemProHomeScreen extends StatefulWidget {
  const DemProHomeScreen({super.key});
  @override
  State<DemProHomeScreen> createState() => _State();
}

class _State extends State<DemProHomeScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;
  late final PageController _pageController = PageController(
    initialPage: _currentIndex,
  );

  final _demProRepo = DemProRepository(ApiClient.dio);
  final _livraisonsKey = GlobalKey<_LivraisonsTabState>();
  final _financesKey = GlobalKey<_FinancesTabState>();

  Map<String, dynamic>? _user;
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _allOrders = [];
  List<Map<String, dynamic>> _activeOrders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Popup "vous avez une réduction disponible" — une seule fois par
      // campagne (voir promo_highlight_popup.dart), silencieuse s'il n'y en
      // a aucune ou en cas d'échec réseau.
      maybeShowPromoHighlight(
        context,
        fetch: OrdersRepository().getHighlightPromo,
        accentColor: AppColors.primary,
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int i) {
    setState(() => _currentIndex = i);
    if (i == 0) _load();
    if (i == 1) _livraisonsKey.currentState?._loadOrders();
    if (i == 3) _financesKey.currentState?._load();
  }

  void _goToTab(int i) {
    _pageController.animateToPage(
      i,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _showCreateOrderSheet() async {
    if (!await ensureLocationEnabled(context)) return;
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) => _CreateOrderSheet(
        onSimple: () {
          Navigator.pop(sheetCtx);
          context.push('/dem-pro/orders/create');
        },
        onExpress: () {
          Navigator.pop(sheetCtx);
          context.push('/dem-pro/orders/create?priority=EXPRESS');
        },
        onBatch: () {
          Navigator.pop(sheetCtx);
          context.push('/dem-pro/batch/create');
        },
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        ProfileRepository().getMe(),
        _demProRepo.getMyStats(),
        _demProRepo.getMyOrders(),
      ]);
      if (!mounted) return;
      final orders = results[2] as List<Map<String, dynamic>>;
      final active = orders.where((o) {
        final s = o['status'] as String? ?? '';
        return const {
          'PENDING',
          'ACCEPTED',
          'PICKED_UP',
          'IN_TRANSIT',
        }.contains(s);
      }).toList();
      setState(() {
        _user = results[0] as Map<String, dynamic>;
        _stats = results[1] as Map<String, dynamic>;
        _allOrders = orders;
        _activeOrders = active;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleLogout() async {
    await AuthStorage.clear();
    appStartupNotifier.markLoggedOut();
    if (mounted) context.go('/phone');
  }

  @override
  Widget build(BuildContext context) {
    const t = _T();
    return Scaffold(
      backgroundColor: t.scaffoldBg,
      body: PageView(
        controller: _pageController,
        physics: const _PremiumPageScrollPhysics(),
        onPageChanged: _onPageChanged,
        children: [
          _PageTransition(
            controller: _pageController,
            index: 0,
            child: _AccueilTab(
              user: _user,
              stats: _stats,
              loading: _loading,
              activeOrders: _activeOrders,
              allOrders: _allOrders,
              onRefresh: _load,
              onOpenDashboard: () => _goToTab(3),
              t: t,
            ),
          ),
          _PageTransition(
            controller: _pageController,
            index: 1,
            child: _LivraisonsTab(key: _livraisonsKey, t: t),
          ),
          _PageTransition(
            controller: _pageController,
            index: 2,
            child: _AdressesTab(t: t),
          ),
          _PageTransition(
            controller: _pageController,
            index: 3,
            child: _FinancesTab(key: _financesKey, t: t, user: _user),
          ),
          _PageTransition(
            controller: _pageController,
            index: 4,
            child: _CompteTab(
              user: _user,
              onLogout: _handleLogout,
              t: t,
              onRefresh: _load,
            ),
          ),
        ],
      ),
      floatingActionButton: switch (_currentIndex) {
        1 => FloatingActionButton(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          onPressed: _showCreateOrderSheet,
          child: const Icon(Icons.add, size: 28),
        ),
        _ => null,
      },
      bottomNavigationBar: DemProNavBar(
        currentIndex: _currentIndex,
        onTap: _goToTab,
      ),
    );
  }
}

// ── Choix du type de course — feuille modale ouverte par le "+" ─────────────

class _CreateOrderSheet extends StatelessWidget {
  final VoidCallback onSimple;
  final VoidCallback onExpress;
  final VoidCallback onBatch;
  const _CreateOrderSheet({
    required this.onSimple,
    required this.onExpress,
    required this.onBatch,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.fromLTRB(
      20,
      12,
      20,
      MediaQuery.of(context).viewPadding.bottom + 20,
    ),
    decoration: const BoxDecoration(
      gradient: AppColors.gradientSplash,
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 18),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Text(
          'Nouvelle livraison',
          style: ClientText.title.copyWith(color: Colors.white, fontSize: 18),
        ),
        const SizedBox(height: 4),
        Text(
          'Choisissez le type de course',
          style: ClientText.body.copyWith(
            color: Colors.white.withValues(alpha: 0.75),
          ),
        ),
        const SizedBox(height: 20),
        _CreateOrderOption(
          icon: Icons.bolt_rounded,
          color: AppColors.warning,
          title: 'Express',
          subtitle: 'Prioritaire, prise en charge plus rapide',
          onTap: onExpress,
        ),
        const SizedBox(height: 10),
        _CreateOrderOption(
          icon: Icons.two_wheeler_rounded,
          color: AppColors.primary,
          title: 'Simple',
          subtitle: 'Livraison standard, un point à l\'autre',
          onTap: onSimple,
        ),
        const SizedBox(height: 10),
        _CreateOrderOption(
          icon: Icons.route_rounded,
          color: AppColors.accentIndigo,
          title: 'Groupée',
          subtitle: 'Plusieurs arrêts avec un seul livreur',
          onTap: onBatch,
        ),
      ],
    ),
  );
}

class _CreateOrderOption extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _CreateOrderOption({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color, color.withValues(alpha: 0.7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: ClientText.bodyStrong.copyWith(
                    color: Colors.white,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: ClientText.label.copyWith(
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: Colors.white.withValues(alpha: 0.6),
            size: 20,
          ),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Onglet Accueil
// ─────────────────────────────────────────────────────────────────────────────

class _AccueilTab extends StatelessWidget {
  final Map<String, dynamic>? user;
  final Map<String, dynamic>? stats;
  final bool loading;
  final List<Map<String, dynamic>> activeOrders;
  final List<Map<String, dynamic>> allOrders;
  final Future<void> Function() onRefresh;
  final VoidCallback onOpenDashboard;
  final _T t;
  const _AccueilTab({
    required this.user,
    required this.stats,
    required this.loading,
    required this.activeOrders,
    required this.allOrders,
    required this.onRefresh,
    required this.onOpenDashboard,
    required this.t,
  });

  void _goToActiveOrder(BuildContext context, Map<String, dynamic> o) {
    final status = o['status'] as String? ?? '';
    if (status == 'PENDING') {
      context.push('/dem-pro/orders/confirmation', extra: o);
    } else {
      final driverId =
          (o['driver'] as Map?)?['id'] as String? ??
          o['driverId'] as String? ??
          '';
      context.push(
        '/dem-pro/orders/tracking',
        extra: {'orderId': o['id'], 'driverId': driverId, 'initialOrder': o},
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final businessName = (user?['proBusinessName'] as String?)?.trim();

    final delivered =
        (stats?['deliveriesToday']?['completed'] as num?)?.toInt() ?? 0;
    final inProgress =
        (stats?['deliveriesToday']?['inProgress'] as num?)?.toInt() ?? 0;

    final now0 = DateTime.now();
    int salesToday = 0;
    int salesMonth = 0;
    for (final o in allOrders) {
      final s = (o['status'] as String? ?? '').toUpperCase();
      if (s != 'DELIVERED' && s != 'PAYMENT_CONFIRMED') continue;
      final items = o['items'] as List?;
      if (items == null) continue;
      int orderSales = 0;
      for (final item in items) {
        orderSales +=
            ((item['price'] as num?)?.toInt() ?? 0) *
            ((item['quantity'] as num?)?.toInt() ?? 1);
      }
      final dt = DateTime.tryParse(o['createdAt'] as String? ?? '')?.toLocal();
      if (dt != null && dt.year == now0.year && dt.month == now0.month) {
        salesMonth += orderSales;
        if (dt.day == now0.day) salesToday += orderSales;
      }
    }

    final now = DateTime.now();
    final dateStr =
        '${_dayNames[now.weekday - 1]} ${now.day} ${_monthNames[now.month - 1]}';

    return Column(
      children: [
        // ── Header dégradé cyan — plein-bleed jusqu'en haut de l'écran,
        // comme les headers Client/Livreur (Container hors SafeArea, la
        // SafeArea ne protège que le contenu, pas le fond) ────────────────
        Container(
          width: double.infinity,
          decoration: const BoxDecoration(gradient: AppColors.gradientSplash),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 22),
              child: Row(
                children: [
                  _ProAvatar(
                    avatarUrl: user?['avatar'] as String?,
                    businessName: businessName,
                    size: 42,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      businessName?.isNotEmpty == true
                          ? businessName!
                          : 'Mon entreprise',
                      style: ClientText.headline.copyWith(
                        color: Colors.white,
                        fontSize: 21,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (activeOrders.isNotEmpty) ...[
                    _ActiveOrderIcon(
                      count: activeOrders.length,
                      onTap: () =>
                          _goToActiveOrder(context, activeOrders.first),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.20),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'DEM PRO',
                      style: ClientText.micro.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        Expanded(
          child: RefreshIndicator(
            color: AppColors.primary,
            backgroundColor: t.cardBg,
            onRefresh: onRefresh,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Carte résumé — tableau de bord ────────────────────
                    if (loading)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: AppColors.primary,
                          ),
                        ),
                      )
                    else
                      GestureDetector(
                        onTap: onOpenDashboard,
                        child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.12),
                          ),
                          boxShadow: AppShadows.card,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // En-tête avec date dynamique + affordance "cliquable"
                            Row(
                              children: [
                                const Icon(
                                  Icons.two_wheeler,
                                  color: AppColors.primary,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Livraisons — $dateStr',
                                    style: ClientText.label.copyWith(
                                      color: t.muted,
                                    ),
                                  ),
                                ),
                                Text(
                                  'Détails',
                                  style: ClientText.micro.copyWith(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const Icon(
                                  Icons.chevron_right,
                                  color: AppColors.primary,
                                  size: 14,
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),

                            // Grandes stats livrées / en cours
                            Row(
                              children: [
                                Expanded(
                                  child: _BigStatBox(
                                    value: '$delivered',
                                    label: 'Livrées',
                                    color: AppColors.successLight,
                                    t: t,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _BigStatBox(
                                    value: '$inProgress',
                                    label: 'En cours',
                                    color: AppColors.warning,
                                    t: t,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),

                            // Ventes en 2 mini-cards distinctes
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Ventes aujourd\'hui',
                                          style: ClientText.micro.copyWith(
                                            color: t.muted,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          formatFcfa(salesToday),
                                          style: ClientText.subtitle.copyWith(
                                            color: AppColors.successLight,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Ventes ce mois',
                                          style: ClientText.micro.copyWith(
                                            color: t.muted,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          formatFcfa(salesMonth),
                                          style: ClientText.subtitle.copyWith(
                                            color: AppColors.successLight,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        ),
                      ),
                    const SizedBox(height: 24),

                    // ── Faire une livraison ───────────────────────────────
                    Text(
                      'Faire une livraison',
                      style: ClientText.bodyStrong.copyWith(color: t.text),
                    ),
                    const SizedBox(height: 12),

                    // ── Types de livraison ────────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: _PremiumServiceCard(
                            icon: Icons.bolt_rounded,
                            label: 'Express',
                            color: AppColors.warning,
                            onTap: () async {
                              if (!await ensureLocationEnabled(context)) return;
                              if (!context.mounted) return;
                              context.push(
                                '/dem-pro/orders/create?priority=EXPRESS',
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _PremiumServiceCard(
                            icon: Icons.two_wheeler_rounded,
                            label: 'Simple',
                            color: AppColors.primary,
                            onTap: () async {
                              if (!await ensureLocationEnabled(context)) return;
                              if (!context.mounted) return;
                              context.push('/dem-pro/orders/create');
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _PremiumServiceCard(
                            icon: Icons.route_rounded,
                            label: 'Groupée',
                            color: AppColors.accentIndigo,
                            onTap: () async {
                              if (!await ensureLocationEnabled(context)) return;
                              if (!context.mounted) return;
                              context.push('/dem-pro/batch/create');
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),

                    // ── Produits enregistrés ──────────────────────────────
                    Row(
                      children: [
                        _SectionLabel(label: 'PRODUITS', t: t),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => context.push('/dem-pro/products?add=true'),
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.add,
                              color: AppColors.primary,
                              size: 16,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        GestureDetector(
                          onTap: () => context.push('/dem-pro/products'),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Voir plus',
                                style: ClientText.label.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right,
                                color: AppColors.primary,
                                size: 16,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                  ),
                ),
                const SizedBox(height: 12),
                // ── Catalogue produits — s'étend jusqu'au navbar, défile en
                // interne (tous les produits, pas juste un aperçu de 3).
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: _ProductsPreviewSection(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

}

// ═══════════════════════════════════════════════════════════════════════════
// Onglet Compte
// ─────────────────────────────────────────────────────────────────────────────

class _CompteTab extends StatefulWidget {
  final Map<String, dynamic>? user;
  final VoidCallback onLogout;
  final _T t;
  final Future<void> Function() onRefresh;
  const _CompteTab({
    required this.user,
    required this.onLogout,
    required this.t,
    required this.onRefresh,
  });
  @override
  State<_CompteTab> createState() => _CompteTabState();
}

class _CompteTabState extends State<_CompteTab>
    with AutomaticKeepAliveClientMixin {
  final _repo = DemProRepository(ApiClient.dio);

  @override
  bool get wantKeepAlive => true;

  bool _uploading = false;
  bool _logoutLoading = false;
  bool _deleteLoading = false;
  int _logoutSwipeTick = 0;
  int _deleteSwipeTick = 0;
  int _pendingRequestCount = 0;

  @override
  void initState() {
    super.initState();
    _loadPendingRequestCount();
  }

  Future<void> _loadPendingRequestCount() async {
    try {
      final requests = await _repo.getOrderRequests(status: 'PENDING');
      if (mounted) setState(() => _pendingRequestCount = requests.length);
    } catch (_) {}
  }

  void _shareOrderLink() {
    final id = widget.user?['id'] as String?;
    if (id == null) return;
    final businessName = (widget.user?['proBusinessName'] as String?)?.trim();
    final link = 'https://www.dem.sn/commander/$id';
    final label = businessName?.isNotEmpty == true
        ? businessName!
        : 'ma boutique';
    SharePlus.instance.share(
      ShareParams(
        text: 'Commandez chez $label et faites-vous livrer par DEM : $link',
      ),
    );
  }

  Future<void> _pickAndUploadAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      imageQuality: 80,
    );
    if (picked == null) return;

    setState(() => _uploading = true);
    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          picked.path,
          filename: picked.name,
        ),
        'field': 'avatar',
      });
      await ApiClient.dio.post('/users/driver/documents', data: formData);
      await widget.onRefresh();
    } catch (e) {
      debugPrint('[AVATAR UPLOAD] error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Échec de l\'upload. Réessayez.')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _confirmLogout(BuildContext ctx) async {
    final t = widget.t;
    await showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: t.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(sheetCtx).viewPadding.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: t.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.logout_rounded,
                  color: AppColors.primary,
                  size: 26,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Se déconnecter ?',
                style: ClientText.title.copyWith(color: t.text, fontSize: 16),
              ),
              const SizedBox(height: 6),
              Text(
                'Vous devrez vous reconnecter avec votre numéro de téléphone pour retrouver votre espace DEM Pro.',
                textAlign: TextAlign.center,
                style: ClientText.body.copyWith(color: t.muted, height: 1.4),
              ),
              const SizedBox(height: 24),
              SwipeToConfirm(
                key: ValueKey('dem-pro-logout-$_logoutSwipeTick'),
                label: 'Glissez pour se déconnecter',
                loading: _logoutLoading,
                trackColor: AppColors.primary,
                thumbColor: Colors.white,
                iconColor: AppColors.primary,
                labelColor: Colors.white,
                onConfirmed: () {
                  setSheetState(() => _logoutLoading = true);
                  widget.onLogout();
                  if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                },
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _logoutLoading
                    ? null
                    : () => Navigator.pop(sheetCtx),
                child: Text(
                  'Annuler',
                  style: ClientText.body.copyWith(color: t.muted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDeleteAccount(BuildContext ctx) async {
    final t = widget.t;
    await showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: t.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(sheetCtx).viewPadding.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: t.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.delete_forever_outlined,
                  color: AppColors.error,
                  size: 28,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Supprimer mon compte ?',
                style: ClientText.title.copyWith(color: t.text, fontSize: 16),
              ),
              const SizedBox(height: 6),
              Text(
                'Cette action est irréversible. Toutes vos données, livraisons et adresses seront définitivement supprimées.',
                textAlign: TextAlign.center,
                style: ClientText.body.copyWith(color: t.muted, height: 1.4),
              ),
              const SizedBox(height: 24),
              SwipeToConfirm(
                key: ValueKey('dem-pro-delete-$_deleteSwipeTick'),
                label: 'Glissez pour supprimer',
                loading: _deleteLoading,
                trackColor: AppColors.error,
                thumbColor: Colors.white,
                iconColor: AppColors.error,
                labelColor: Colors.white,
                onConfirmed: () async {
                  setSheetState(() => _deleteLoading = true);
                  try {
                    await ApiClient.dio.delete('/users/me');
                    await AuthStorage.clear();
                    appStartupNotifier.markLoggedOut();
                    if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                    if (mounted) context.go('/phone');
                  } catch (_) {
                    setSheetState(() {
                      _deleteLoading = false;
                      _deleteSwipeTick++;
                    });
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Échec de la suppression. Réessayez.'),
                        ),
                      );
                    }
                  }
                },
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _deleteLoading
                    ? null
                    : () => Navigator.pop(sheetCtx),
                child: Text(
                  'Annuler',
                  style: ClientText.body.copyWith(color: t.muted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showSectorPicker(String? current) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        backgroundColor: widget.t.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Domaine d\'activité',
          style: ClientText.title.copyWith(color: widget.t.text),
        ),
        children: _sectorLabels.entries
            .map(
              (e) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, e.key),
                child: Row(
                  children: [
                    Icon(
                      e.key == current
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: e.key == current
                          ? AppColors.primary
                          : widget.t.muted,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      e.value,
                      style: ClientText.body.copyWith(
                        color: widget.t.text,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
    if (result == null || result == current) return;
    try {
      await ApiClient.dio.patch(
        '/users/me/profile',
        data: {'proSector': result},
      );
      await widget.onRefresh();
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Une erreur est survenue.')),
        );
    }
  }

  Future<void> _showVolumePicker(String? current) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        backgroundColor: widget.t.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Volume hebdomadaire',
          style: ClientText.title.copyWith(color: widget.t.text),
        ),
        children: _volumeLabels.entries
            .map(
              (e) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, e.key),
                child: Row(
                  children: [
                    Icon(
                      e.key == current
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: e.key == current
                          ? AppColors.primary
                          : widget.t.muted,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      e.value,
                      style: ClientText.body.copyWith(
                        color: widget.t.text,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
    if (result == null || result == current) return;
    try {
      await ApiClient.dio.patch(
        '/users/me/profile',
        data: {'proWeeklyVolume': result},
      );
      await widget.onRefresh();
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Une erreur est survenue.')),
        );
    }
  }

  Future<void> _requestPhoneChange(String currentPhone) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: widget.t.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Changer de numéro',
          style: ClientText.title.copyWith(color: widget.t.text),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Numéro actuel : $currentPhone',
              style: ClientText.body.copyWith(color: widget.t.muted),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.phone,
              style: ClientText.body.copyWith(color: widget.t.text),
              decoration: InputDecoration(
                hintText: '77 000 00 00',
                prefixText: '+221 ',
                prefixStyle: ClientText.body.copyWith(color: widget.t.muted),
                hintStyle: ClientText.body.copyWith(color: widget.t.muted),
                filled: true,
                fillColor: widget.t.cardBg2,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'La demande sera validée par l\'équipe DEM.',
              style: ClientText.label.copyWith(color: widget.t.muted),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Annuler',
              style: ClientText.body.copyWith(color: widget.t.muted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: Text(
              'Envoyer',
              style: ClientText.bodyStrong.copyWith(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
    if (result == null || result.length < 9) return;
    try {
      await ApiClient.dio.post(
        '/users/dem-pro/phone-change',
        data: {'newPhone': '+221$result'},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Demande envoyée. L\'équipe DEM va la valider.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is DioException
                  ? (e.response?.data?['message'] ?? 'Erreur')
                  : 'Erreur',
            ),
          ),
        );
      }
    }
  }

  Future<void> _editField(
    String label,
    String currentValue,
    String fieldKey,
  ) async {
    final ctrl = TextEditingController(text: currentValue);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: widget.t.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Modifier $label',
          style: ClientText.title.copyWith(color: widget.t.text),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: ClientText.body.copyWith(color: widget.t.text),
          decoration: InputDecoration(
            hintText: label,
            hintStyle: ClientText.body.copyWith(color: widget.t.muted),
            filled: true,
            fillColor: widget.t.cardBg2,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Annuler',
              style: ClientText.body.copyWith(color: widget.t.muted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: Text(
              'Enregistrer',
              style: ClientText.bodyStrong.copyWith(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty || result == currentValue) return;
    try {
      await ApiClient.dio.patch('/users/me/profile', data: {fieldKey: result});
      await widget.onRefresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Échec de la mise à jour.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final t = widget.t;
    final user = widget.user;
    final businessName = (user?['proBusinessName'] as String?)?.trim();
    final name = user?['name'] as String?;
    final phone = user?['phone'] as String?;
    final email = user?['email'] as String?;
    final sector = user?['proSector'] as String?;
    final volume = user?['proWeeklyVolume'] as String?;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Carte entreprise ──────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: t.headerCardGradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.15),
                ),
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _uploading ? null : _pickAndUploadAvatar,
                    child: Stack(
                      children: [
                        _ProAvatar(
                          avatarUrl: user?['avatar'] as String?,
                          businessName: businessName,
                          size: 56,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                              border: Border.all(color: t.cardBg, width: 2),
                            ),
                            child: _uploading
                                ? const Padding(
                                    padding: EdgeInsets.all(3),
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 1.5,
                                    ),
                                  )
                                : const Icon(
                                    Icons.camera_alt,
                                    color: Colors.white,
                                    size: 12,
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: () => _editField(
                            'Nom entreprise',
                            businessName ?? '',
                            'proBusinessName',
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  businessName?.isNotEmpty == true
                                      ? businessName!
                                      : 'Mon entreprise',
                                  style: ClientText.title.copyWith(
                                    color: t.text,
                                    fontSize: 17,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Icon(
                                Icons.edit_outlined,
                                color: t.muted,
                                size: 14,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        const _ProBadge(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            _SectionLabel(label: 'INFORMATIONS', t: t),
            const SizedBox(height: 12),
            _InfoCard(
              t: t,
              children: [
                _EditableInfoRow(
                  icon: Icons.person_outline,
                  label: 'Responsable',
                  value: name ?? '—',
                  t: t,
                  onTap: () => _editField('Responsable', name ?? '', 'name'),
                ),
                _EditableInfoRow(
                  icon: Icons.phone_outlined,
                  label: 'Téléphone',
                  value: phone ?? '—',
                  t: t,
                  onTap: () => _requestPhoneChange(phone ?? ''),
                ),
                _EditableInfoRow(
                  icon: Icons.email_outlined,
                  label: 'Email',
                  value: email?.isNotEmpty == true
                      ? email!
                      : 'Ajouter un email',
                  isPlaceholder: email == null || email.isEmpty,
                  t: t,
                  onTap: () => _editField('Email', email ?? '', 'email'),
                ),
                _EditableInfoRow(
                  icon: Icons.category_outlined,
                  label: 'Secteur',
                  value: _sectorLabels[sector] ?? '—',
                  t: t,
                  onTap: () => _showSectorPicker(sector),
                ),
                _EditableInfoRow(
                  icon: Icons.bar_chart_outlined,
                  label: 'Volume hebdo',
                  value: _volumeLabels[volume] ?? '—',
                  t: t,
                  isLast: true,
                  onTap: () => _showVolumePicker(volume),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── Catalogue ────────────────────────────────────────────────
            _SectionLabel(label: 'CATALOGUE', t: t),
            const SizedBox(height: 12),
            _InfoCard(
              t: t,
              children: [
                _TapRow(
                  icon: Icons.inventory_2_outlined,
                  label: 'Mes produits',
                  subtitle: 'Réutilisez-les à chaque commande',
                  t: t,
                  isLast: true,
                  onTap: () => context.push('/dem-pro/products'),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── Lien de commande ───────────────────────────────────────────
            _SectionLabel(label: 'LIEN DE COMMANDE', t: t),
            const SizedBox(height: 12),
            _InfoCard(
              t: t,
              children: [
                _TapRow(
                  icon: Icons.share_outlined,
                  label: 'Partager mon lien de commande',
                  subtitle: 'Vos clients commandent directement, sans compte',
                  t: t,
                  onTap: _shareOrderLink,
                ),
                _TapRow(
                  icon: Icons.inbox_outlined,
                  label: 'Demandes reçues',
                  subtitle: _pendingRequestCount > 0
                      ? '$_pendingRequestCount en attente de confirmation'
                      : 'Aucune demande en attente',
                  t: t,
                  isLast: true,
                  trailing: _pendingRequestCount > 0
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '$_pendingRequestCount',
                            style: ClientText.label.copyWith(
                              color: AppColors.warning,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        )
                      : null,
                  onTap: () async {
                    await context.push('/dem-pro/order-requests');
                    _loadPendingRequestCount();
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── Promotions ───────────────────────────────────────────────
            _SectionLabel(label: 'PROMOTIONS', t: t),
            const SizedBox(height: 12),
            _InfoCard(
              t: t,
              children: [
                _TapRow(
                  icon: Icons.local_offer_outlined,
                  label: 'Code promo',
                  subtitle: 'Réduction sur votre prochaine commande',
                  t: t,
                  isLast: true,
                  onTap: () => context.push('/dem-pro/promo-code'),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── Abonnement ───────────────────────────────────────────────
            _SectionLabel(label: 'ABONNEMENT', t: t),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.workspace_premium,
                      color: AppColors.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'DEM Pro',
                          style: ClientText.subtitle.copyWith(color: t.text),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Plan gratuit — lancement',
                          style: ClientText.label.copyWith(
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Support ──────────────────────────────────────────────────
            _SectionLabel(label: 'SUPPORT', t: t),
            const SizedBox(height: 12),
            _InfoCard(
              t: t,
              children: [
                _TapRow(
                  icon: Icons.phone_outlined,
                  label: 'Appeler le support',
                  t: t,
                  subtitle: '+221 71 006 46 64',
                  onTap: () => launchUrl(Uri.parse('tel:+221710064664')),
                ),
                _TapRow(
                  icon: Icons.chat_bubble_outline,
                  label: 'WhatsApp',
                  t: t,
                  subtitle: '+221 71 006 46 64',
                  onTap: () => launchUrl(
                    Uri.parse('https://wa.me/221710064664'),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
                _TapRow(
                  icon: Icons.email_outlined,
                  label: 'Envoyer un e-mail',
                  t: t,
                  subtitle: 'support@dem.sn',
                  onTap: () => launchUrl(Uri.parse('mailto:support@dem.sn')),
                ),
                _TapRow(
                  icon: Icons.description_outlined,
                  label: 'Conditions d\'utilisation',
                  t: t,
                  isLast: true,
                  onTap: () => launchUrl(
                    Uri.parse('https://www.dem.sn/#cgu'),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── Déconnexion ───────────────────────────────────────────────
            _LogoutButton(onTap: () => _confirmLogout(context), t: t),

            const SizedBox(height: 12),

            // ── Supprimer le compte ──────────────────────────────────────
            GestureDetector(
              onTap: () => _confirmDeleteAccount(context),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.delete_outline,
                      color: AppColors.error,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Supprimer mon compte',
                      style: ClientText.bodyStrong.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),
            Center(
              child: Text(
                'DEM v1.1.1',
                style: ClientText.label.copyWith(
                  color: t.muted.withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widgets locaux
// ─────────────────────────────────────────────────────────────────────────────

class _ProBadge extends StatelessWidget {
  const _ProBadge();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: AppColors.primary.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      'DEM PRO',
      style: ClientText.micro.copyWith(
        color: AppColors.primary,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.5,
      ),
    ),
  );
}

class _ActiveOrderIcon extends StatefulWidget {
  final int count;
  final VoidCallback onTap;
  const _ActiveOrderIcon({required this.count, required this.onTap});
  @override
  State<_ActiveOrderIcon> createState() => _ActiveOrderIconState();
}

class _ActiveOrderIconState extends State<_ActiveOrderIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: widget.onTap,
    child: AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(
            alpha: 0.12 + _ctrl.value * 0.08,
          ),
          shape: BoxShape.circle,
          border: Border.all(
            color: AppColors.primary.withValues(
              alpha: 0.4 + _ctrl.value * 0.3,
            ),
            width: 1.5,
          ),
        ),
        child: child,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Icon(Icons.two_wheeler, color: AppColors.primary, size: 20),
          if (widget.count > 1)
            Positioned(
              top: 2,
              right: 2,
              child: Container(
                width: 14,
                height: 14,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '${widget.count}',
                    style: ClientText.micro.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _ProAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String? businessName;
  final double size;
  const _ProAvatar({this.avatarUrl, this.businessName, this.size = 40});

  String get _initials {
    final name = (businessName ?? '').trim();
    if (name.isEmpty) return 'P';
    final parts = name.split(RegExp(r'\s+'));
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final hasUrl = avatarUrl != null && avatarUrl!.isNotEmpty;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primary.withValues(alpha: 0.15),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasUrl
          ? Image.network(
              avatarUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Center(
                child: Text(
                  _initials,
                  style: ClientText.bodyStrong.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: size * 0.38,
                  ),
                ),
              ),
            )
          : Center(
              child: Text(
                _initials,
                style: ClientText.bodyStrong.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w800,
                  fontSize: size * 0.38,
                ),
              ),
            ),
    );
  }
}

// Grande stat dans la carte (livrées / en cours)
class _BigStatBox extends StatelessWidget {
  final String value, label;
  final Color color;
  final _T t;
  const _BigStatBox({
    required this.value,
    required this.label,
    required this.color,
    required this.t,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      children: [
        Text(value, style: ClientText.hero.copyWith(color: color, height: 1)),
        const SizedBox(height: 4),
        Text(label, style: ClientText.label.copyWith(color: t.muted)),
      ],
    ),
  );
}

// ── Raccourci type de livraison — carte animée (pression = léger zoom-out) ──
class _PremiumServiceCard extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _PremiumServiceCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  State<_PremiumServiceCard> createState() => _PremiumServiceCardState();
}

class _PremiumServiceCardState extends State<_PremiumServiceCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scale = Tween<double>(
      begin: 1.0,
      end: 0.94,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown: (_) => _ctrl.forward(),
    onTapUp: (_) => _ctrl.reverse(),
    onTapCancel: () => _ctrl.reverse(),
    onTap: widget.onTap,
    child: AnimatedBuilder(
      animation: _scale,
      builder: (_, child) =>
          Transform.scale(scale: _scale.value, child: child),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: widget.color.withValues(alpha: 0.14)),
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: 0.16),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    widget.color,
                    widget.color.withValues(alpha: 0.75),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(widget.icon, color: Colors.white, size: 22),
            ),
            const SizedBox(height: 10),
            Text(
              widget.label,
              style: ClientText.bodyStrong.copyWith(
                color: AppColors.textDark,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ── Aperçu du catalogue produits sur l'Accueil ───────────────────────────────
class _ProductsPreviewSection extends StatefulWidget {
  const _ProductsPreviewSection();

  @override
  State<_ProductsPreviewSection> createState() =>
      _ProductsPreviewSectionState();
}

class _ProductsPreviewSectionState extends State<_ProductsPreviewSection>
    with AutomaticKeepAliveClientMixin {
  final _repo = DemProRepository(ApiClient.dio);
  List<Map<String, dynamic>> _products = [];
  bool _loading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final products = await _repo.getProducts();
      if (mounted) setState(() { _products = products; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _goToProducts() async {
    await context.push('/dem-pro/products');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppColors.primary,
          strokeWidth: 2,
        ),
      );
    }

    if (_products.isEmpty) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
          boxShadow: AppShadows.card,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.inventory_2_outlined,
                color: AppColors.primary,
                size: 28,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Aucun produit enregistré',
              style: ClientText.subtitle.copyWith(color: AppColors.textDark),
            ),
            const SizedBox(height: 6),
            Text(
              'Ajoutez vos produits pour les retrouver instantanément à chaque commande.',
              textAlign: TextAlign.center,
              style: ClientText.label.copyWith(
                color: AppColors.textMuted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: _goToProducts,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Ajouter un produit',
                      style: ClientText.button.copyWith(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Même habillage que la carte tableau de bord — s'étend jusqu'au
    // navbar (contrainte de hauteur héritée du parent Expanded) et
    // défile en interne pour montrer tout le catalogue, pas juste un
    // aperçu, sans faire grandir le reste de l'Accueil.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
        boxShadow: AppShadows.card,
      ),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: _products.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _ProductPreviewCard(
          product: _products[i],
          onTap: _goToProducts,
        ),
      ),
    );
  }
}

class _ProductPreviewCard extends StatelessWidget {
  final Map<String, dynamic> product;
  final VoidCallback onTap;
  const _ProductPreviewCard({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = product['name'] as String? ?? '';
    final price = product['defaultPrice'] as num?;
    final quantity = (product['quantity'] as num?)?.toInt();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.lightBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.inventory_2_outlined,
                color: AppColors.primary,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: ClientText.bodyStrong.copyWith(
                      color: AppColors.textDark,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (price != null)
                    Text(
                      formatFcfa(price),
                      style: ClientText.label.copyWith(
                        color: AppColors.successLight,
                      ),
                    ),
                ],
              ),
            ),
            if (quantity != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: (quantity > 0 ? AppColors.successLight : AppColors.warning)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  quantity > 0 ? '$quantity' : 'Rupture',
                  style: ClientText.micro.copyWith(
                    color: quantity > 0 ? AppColors.successLight : AppColors.warning,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final _T t;
  const _SectionLabel({required this.label, required this.t});
  @override
  Widget build(BuildContext context) => Text(
    label,
    style: ClientText.label.copyWith(
      color: t.muted,
      fontWeight: FontWeight.w700,
      letterSpacing: 1,
    ),
  );
}

class _InfoCard extends StatelessWidget {
  final List<Widget> children;
  final _T t;
  const _InfoCard({required this.children, required this.t});
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: t.cardBg,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: t.border),
    ),
    child: Column(children: children),
  );
}

class _EditableInfoRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final _T t;
  final VoidCallback onTap;
  final bool isPlaceholder;
  final bool isLast;
  const _EditableInfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.t,
    required this.onTap,
    this.isPlaceholder = false,
    this.isLast = false,
  });
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: isLast ? null : Border(bottom: BorderSide(color: t.border)),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: ClientText.body.copyWith(color: t.muted)),
          ),
          Text(
            value,
            style: ClientText.body.copyWith(
              color: isPlaceholder
                  ? AppColors.primary.withValues(alpha: 0.6)
                  : t.text,
              fontWeight: isPlaceholder ? FontWeight.w500 : FontWeight.w600,
              fontStyle: isPlaceholder ? FontStyle.italic : FontStyle.normal,
            ),
          ),
          const SizedBox(width: 6),
          Icon(Icons.edit_outlined, color: t.muted, size: 14),
        ],
      ),
    ),
  );
}

class _TapRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final _T t;
  final VoidCallback onTap;
  final bool isLast;
  final Widget? trailing;
  const _TapRow({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.t,
    required this.onTap,
    this.isLast = false,
    this.trailing,
  });
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: isLast ? null : Border(bottom: BorderSide(color: t.border)),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: ClientText.bodyStrong.copyWith(color: t.text),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: ClientText.label.copyWith(color: t.muted),
                  ),
              ],
            ),
          ),
          if (trailing != null) ...[trailing!, const SizedBox(width: 8)],
          Icon(Icons.chevron_right, color: t.muted, size: 18),
        ],
      ),
    ),
  );
}

class _LogoutButton extends StatelessWidget {
  final VoidCallback onTap;
  final _T t;
  const _LogoutButton({required this.onTap, required this.t});
  @override
  Widget build(BuildContext context) => Material(
    color: t.cardBg,
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: t.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.logout_outlined,
              color: AppColors.error,
              size: 18,
            ),
            const SizedBox(width: 10),
            Text(
              'Se déconnecter',
              style: ClientText.subtitle.copyWith(color: AppColors.error),
            ),
          ],
        ),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Onglet Livraisons
// ─────────────────────────────────────────────────────────────────────────────

class _LivraisonsTab extends StatefulWidget {
  final _T t;
  const _LivraisonsTab({super.key, required this.t});
  @override
  State<_LivraisonsTab> createState() => _LivraisonsTabState();
}

class _LivraisonsTabState extends State<_LivraisonsTab>
    with AutomaticKeepAliveClientMixin {
  late final DemProRepository _repo;

  @override
  bool get wantKeepAlive => true;

  // ── Livraisons ─────────────────────────────────────────────────────────────
  static const _ordersPageSize = 50;
  List<Map<String, dynamic>> _orders = [];
  bool _loadingOrders = true;
  int _ordersPage = 1;
  bool _loadingMoreOrders = false;
  bool _hasMoreOrders = true;
  _OrderFilter _filter = _OrderFilter.all;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  // ── Tournées ───────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _batches = [];
  bool _loadingBatches = false;

  _ViewType _viewType = _ViewType.orders;

  @override
  void initState() {
    super.initState();
    _repo = DemProRepository(ApiClient.dio);
    _loadOrders();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadOrders() async {
    if (!_loadingOrders) setState(() => _loadingOrders = true);
    try {
      final orders = await _repo.getMyOrders(page: 1, limit: _ordersPageSize);
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _ordersPage = 1;
        _hasMoreOrders = orders.length >= _ordersPageSize;
        _loadingOrders = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingOrders = false);
    }
  }

  Future<void> _loadMoreOrders() async {
    if (_loadingMoreOrders || !_hasMoreOrders) return;
    setState(() => _loadingMoreOrders = true);
    try {
      final next = _ordersPage + 1;
      final more = await _repo.getMyOrders(page: next, limit: _ordersPageSize);
      if (!mounted) return;
      setState(() {
        _orders = [..._orders, ...more];
        _ordersPage = next;
        _hasMoreOrders = more.length >= _ordersPageSize;
        _loadingMoreOrders = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMoreOrders = false);
    }
  }

  Future<void> _loadBatches() async {
    setState(() => _loadingBatches = true);
    try {
      final batches = await _repo.getMyBatches();
      if (!mounted) return;
      setState(() {
        _batches = batches;
        _loadingBatches = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingBatches = false);
    }
  }

  void _switchView(_ViewType v) {
    setState(() => _viewType = v);
    if (v == _ViewType.batches && _batches.isEmpty && !_loadingBatches) {
      _loadBatches();
    }
  }

  bool _matchesSearch(Map<String, dynamic> o) {
    if (_searchQuery.isEmpty) return true;
    final q = _searchQuery.toLowerCase();
    final pickup = (o['pickupAddress'] as String? ?? '').toLowerCase();
    final delivery = (o['deliveryAddress'] as String? ?? '').toLowerCase();
    final receiver = (o['receiverName'] as String? ?? '').toLowerCase();
    final id = (o['id'] as String? ?? '').toLowerCase();
    return pickup.contains(q) ||
        delivery.contains(q) ||
        receiver.contains(q) ||
        id.contains(q);
  }

  List<Map<String, dynamic>> get _activeOrders => _orders
      .where((o) => _isActiveStatus(o['status'] as String))
      .where(_matchesSearch)
      .toList();

  List<Map<String, dynamic>> get _historyOrders {
    Iterable<Map<String, dynamic>> base;
    if (_filter == _OrderFilter.delivered) {
      base = _orders.where((o) => o['status'] == 'DELIVERED');
    } else if (_filter == _OrderFilter.cancelled) {
      base = _orders.where((o) => o['status'] == 'CANCELLED');
    } else {
      base = _orders.where((o) => !_isActiveStatus(o['status'] as String));
    }
    return base.where(_matchesSearch).toList();
  }

  int get _activeCount => _activeOrders.length;
  int get _deliveredCount =>
      _orders.where((o) => o['status'] == 'DELIVERED').length;
  int get _cancelledCount =>
      _orders.where((o) => o['status'] == 'CANCELLED').length;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final t = widget.t;

    // ── Tap en dehors de la barre de recherche → referme le clavier ────────
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.translucent,
      child: Column(
      children: [
        // ── Header dégradé cyan — même pattern que l'Accueil, plein-bleed
        // jusqu'en haut de l'écran (Container hors SafeArea) ────────────────
        Container(
          width: double.infinity,
          decoration: const BoxDecoration(gradient: AppColors.gradientSplash),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 22),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.20),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.two_wheeler_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Livraisons',
                      style: ClientText.headline.copyWith(
                        color: Colors.white,
                        fontSize: 21,
                      ),
                    ),
                  ),
                  if (_activeCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.20),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$_activeCount en cours',
                        style: ClientText.micro.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // ── Toggle Livraisons / Tournées ────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _ViewToggleBar(
            viewType: _viewType,
            onChanged: _switchView,
            t: t,
          ),
        ),
        const SizedBox(height: 12),
        // ── Contenu ──────────────────────────────────────────────────────
        Expanded(
          child: _viewType == _ViewType.orders
              ? _buildOrdersView(t)
              : _buildBatchesView(t),
        ),
      ],
      ),
    );
  }

  // ── Vue Livraisons ─────────────────────────────────────────────────────────

  Widget _buildOrdersView(_T t) {
    if (_loadingOrders) {
      return Container(
        color: t.scaffoldBg,
        child: const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    final showActive =
        _filter == _OrderFilter.all || _filter == _OrderFilter.active;
    final showHistory = _filter != _OrderFilter.active;
    final activeToShow = showActive ? _activeOrders : <Map<String, dynamic>>[];
    final historyToShow = showHistory
        ? _historyOrders
        : <Map<String, dynamic>>[];
    final isEmpty = activeToShow.isEmpty && historyToShow.isEmpty;
    final isSearchEmpty = isEmpty && _searchQuery.isNotEmpty;
    final canLoadMore =
        _hasMoreOrders && _filter != _OrderFilter.active && _searchQuery.isEmpty;

    return Column(
      children: [
        if (_orders.isNotEmpty || _searchQuery.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: _OrderSearchField(
              controller: _searchCtrl,
              t: t,
              onChanged: (v) => setState(() => _searchQuery = v.trim()),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.primary,
            backgroundColor: t.cardBg,
            onRefresh: _loadOrders,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _FilterTabs(
                    filter: _filter,
                    totalCount: _orders.length,
                    activeCount: _activeCount,
                    deliveredCount: _deliveredCount,
                    cancelledCount: _cancelledCount,
                    t: t,
                    onFilterChanged: (f) => setState(() => _filter = f),
                  ),
                  if (isEmpty)
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.45,
                      child: _EmptyOrdersState(
                        t: t,
                        globallyEmpty: _orders.isEmpty,
                        searching: isSearchEmpty,
                        onOrder: () => context.push('/dem-pro/orders/create'),
                      ),
                    )
                  else ...[
                    if (activeToShow.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                        child: _SectionLabel(label: 'EN COURS', t: t),
                      ),
                      for (int i = 0; i < activeToShow.length; i++)
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            20,
                            0,
                            20,
                            i < activeToShow.length - 1 ? 12 : 0,
                          ),
                          child: _ActiveOrderCard(order: activeToShow[i], t: t),
                        ),
                    ],
                    if (historyToShow.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                        child: _SectionLabel(label: 'HISTORIQUE', t: t),
                      ),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 20),
                        decoration: BoxDecoration(
                          color: t.cardBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: t.border),
                        ),
                        child: Column(
                          children: [
                            for (int i = 0; i < historyToShow.length; i++)
                              _HistoriqueRow(
                                order: historyToShow[i],
                                t: t,
                                isLast: i == historyToShow.length - 1,
                              ),
                          ],
                        ),
                      ),
                    ],
                    if (canLoadMore)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                        child: _LoadMoreButton(
                          loading: _loadingMoreOrders,
                          onTap: _loadMoreOrders,
                          t: t,
                        ),
                      ),
                    const SizedBox(height: 90),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Vue Tournées ───────────────────────────────────────────────────────────

  Widget _buildBatchesView(_T t) {
    if (_loadingBatches && _batches.isEmpty) {
      return Center(
        child: CircularProgressIndicator(
          color: AppColors.primary,
          strokeWidth: 2,
        ),
      );
    }

    if (_batches.isEmpty) {
      return RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: t.cardBg,
        onRefresh: _loadBatches,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.55,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.route_outlined,
                        color: AppColors.primary,
                        size: 34,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Aucune tournée',
                      style: ClientText.title.copyWith(
                        color: t.text,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Créez une tournée pour regrouper plusieurs livraisons avec un seul livreur.',
                      style: ClientText.body.copyWith(
                        color: t.muted,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    GestureDetector(
                      onTap: () => context.push('/dem-pro/batch/create'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.add,
                              color: Colors.white,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Créer une tournée',
                              style: ClientText.button.copyWith(fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final active = _batches.where((b) {
      final s = b['status'] as String? ?? '';
      return s == 'PENDING' ||
          s == 'ACCEPTED' ||
          s == 'IN_PROGRESS' ||
          s == 'SCHEDULED';
    }).toList();
    final history = _batches.where((b) {
      final s = b['status'] as String? ?? '';
      return s == 'COMPLETED' || s == 'CANCELLED';
    }).toList();

    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: t.cardBg,
      onRefresh: _loadBatches,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
        children: [
          if (active.isNotEmpty) ...[
            _SectionLabel(label: 'EN COURS', t: t),
            const SizedBox(height: 10),
            for (final b in active) ...[
              _BatchCard(batch: b, t: t),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 12),
          ],
          if (history.isNotEmpty) ...[
            _SectionLabel(label: 'HISTORIQUE', t: t),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: t.cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: t.border),
              ),
              child: Column(
                children: [
                  for (int i = 0; i < history.length; i++)
                    _BatchHistoryRow(
                      batch: history[i],
                      t: t,
                      isLast: i == history.length - 1,
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Recherche livraisons ──────────────────────────────────────────────────────

class _OrderSearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final _T t;
  final String hintText;
  const _OrderSearchField({
    required this.controller,
    required this.onChanged,
    required this.t,
    this.hintText = 'Rechercher une adresse, un destinataire…',
  });

  @override
  Widget build(BuildContext context) => Container(
    height: 44,
    decoration: BoxDecoration(
      color: AppColors.primary.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
    ),
    child: TextField(
      controller: controller,
      onChanged: onChanged,
      cursorColor: AppColors.primary,
      style: ClientText.body.copyWith(color: t.text),
      decoration: InputDecoration(
        isDense: true,
        isCollapsed: true,
        filled: false,
        hintText: hintText,
        hintStyle: ClientText.body.copyWith(color: t.muted),
        prefixIcon: Icon(Icons.search, color: AppColors.primary, size: 20),
        prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 20),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                icon: Icon(Icons.close, color: t.muted, size: 18),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              ),
        // ── Neutralise l'InputDecorationTheme ambiant (fond + bordure carrée
        // qui apparaissait au focus) : ce champ ne doit tenir son style QUE de
        // son Container parent, quel que soit l'état focus/enabled/error.
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
      ),
    ),
  );
}

// ── Charger plus ──────────────────────────────────────────────────────────────

class _LoadMoreButton extends StatelessWidget {
  final bool loading;
  final VoidCallback onTap;
  final _T t;
  const _LoadMoreButton({
    required this.loading,
    required this.onTap,
    required this.t,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: loading ? null : onTap,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: t.cardBg2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary,
                ),
              )
            : Text(
                'Charger plus',
                style: ClientText.bodyStrong.copyWith(
                  color: AppColors.primary,
                ),
              ),
      ),
    ),
  );
}

// ── Filtres ───────────────────────────────────────────────────────────────────

class _FilterTabs extends StatelessWidget {
  final _OrderFilter filter;
  final int totalCount, activeCount, deliveredCount, cancelledCount;
  final ValueChanged<_OrderFilter> onFilterChanged;
  final _T t;
  const _FilterTabs({
    required this.filter,
    required this.totalCount,
    required this.activeCount,
    required this.deliveredCount,
    required this.cancelledCount,
    required this.onFilterChanged,
    required this.t,
  });

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
    child: Row(
      children: [
        _FilterChip(
          label: 'Toutes',
          count: totalCount,
          active: filter == _OrderFilter.all,
          onTap: () => onFilterChanged(_OrderFilter.all),
          t: t,
        ),
        const SizedBox(width: 8),
        _FilterChip(
          label: 'En cours',
          count: activeCount,
          active: filter == _OrderFilter.active,
          onTap: () => onFilterChanged(_OrderFilter.active),
          t: t,
        ),
        const SizedBox(width: 8),
        _FilterChip(
          label: 'Livrées',
          count: deliveredCount,
          active: filter == _OrderFilter.delivered,
          onTap: () => onFilterChanged(_OrderFilter.delivered),
          t: t,
        ),
        const SizedBox(width: 8),
        _FilterChip(
          label: 'Annulées',
          count: cancelledCount,
          active: filter == _OrderFilter.cancelled,
          onTap: () => onFilterChanged(_OrderFilter.cancelled),
          t: t,
        ),
      ],
    ),
  );
}

class _FilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;
  final _T t;
  const _FilterChip({
    required this.label,
    required this.count,
    required this.active,
    required this.onTap,
    required this.t,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: active ? AppColors.primary : t.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: active ? AppColors.primary : t.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: ClientText.body.copyWith(
              color: active ? Colors.white : t.muted,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          if (count > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: active
                    ? Colors.white.withValues(alpha: 0.25)
                    : AppColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: ClientText.label.copyWith(
                  color: active ? Colors.white : AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

// ── Carte livraison active ────────────────────────────────────────────────────

class _ActiveOrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final _T t;
  const _ActiveOrderCard({required this.order, required this.t});

  @override
  Widget build(BuildContext context) {
    final status = order['status'] as String;
    final pickup = _shortAddress(order['pickupAddress'] as String? ?? '');
    final delivery = _shortAddress(order['deliveryAddress'] as String? ?? '');
    final price = order['price'] as num? ?? 0;
    final createdAt = order['createdAt'] as String?;
    final scheduledAt = order['scheduledAt'] as String?;
    final isScheduled = status == 'SCHEDULED';
    final isExpress = order['priority'] == 'EXPRESS';
    final driver = order['driver'] as Map<String, dynamic>?;
    final driverName = driver?['name'] as String?;
    final hasDriver = driver != null;
    final batchOrderId = order['batchOrderId'] as String?;
    final statusColor = _statusColor(status);
    final statusLbl = _statusLabel(status);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Livreur + badge statut ──────────────────────────────────────
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: hasDriver
                      ? AppColors.primary.withValues(alpha: 0.15)
                      : t.cardBg2,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: hasDriver
                      ? Text(
                          _driverInitials(driverName),
                          style: ClientText.bodyStrong.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        )
                      : Icon(Icons.two_wheeler, color: t.muted, size: 18),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasDriver
                          ? (driverName ?? 'Livreur')
                          : 'En attente d\'un livreur…',
                      style: ClientText.bodyStrong.copyWith(color: t.text),
                    ),
                    if (hasDriver)
                      Text(
                        'Moto · DEM',
                        style: ClientText.label.copyWith(color: t.muted),
                      ),
                  ],
                ),
              ),
              if (isExpress) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.bolt_rounded,
                        color: AppColors.warning,
                        size: 12,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        'Express',
                        style: ClientText.label.copyWith(
                          color: AppColors.warning,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  statusLbl,
                  style: ClientText.label.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Adresses ─────────────────────────────────────────────────────
          _AddressRow(
            icon: Icons.radio_button_on,
            color: AppColors.successLight,
            label: pickup,
            t: t,
          ),
          Padding(
            padding: const EdgeInsets.only(left: 7, top: 2, bottom: 2),
            child: Container(width: 1.5, height: 12, color: t.border),
          ),
          _AddressRow(
            icon: Icons.location_on,
            color: AppColors.error,
            label: delivery,
            t: t,
          ),
          const SizedBox(height: 12),

          // ── Pied : prix · temps · bouton Suivre ───────────────────────
          Row(
            children: [
              Icon(Icons.payments_outlined, color: t.muted, size: 14),
              const SizedBox(width: 4),
              Text(
                formatFcfa(price),
                style: ClientText.bodyStrong.copyWith(color: t.text),
              ),
              const SizedBox(width: 14),
              Icon(
                isScheduled ? Icons.event_outlined : Icons.schedule_outlined,
                color: t.muted,
                size: 14,
              ),
              const SizedBox(width: 4),
              Text(
                isScheduled
                    ? 'Prévue ${_formatDateTime(scheduledAt)}'
                    : _timeAgo(createdAt),
                style: ClientText.label.copyWith(color: t.muted),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  if (batchOrderId != null) {
                    context.push(
                      '/dem-pro/batch/tracking',
                      extra: {'batchId': batchOrderId},
                    );
                  } else {
                    _navigateToOrder(context, order);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.map_outlined,
                        color: AppColors.primary,
                        size: 13,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Suivre',
                        style: ClientText.label.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AddressRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final _T t;
  const _AddressRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.t,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: color, size: 14),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          label,
          style: ClientText.body.copyWith(color: t.text),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );
}

// ── Ligne historique compacte ─────────────────────────────────────────────────

class _HistoriqueRow extends StatelessWidget {
  final Map<String, dynamic> order;
  final bool isLast;
  final _T t;
  const _HistoriqueRow({
    required this.order,
    required this.isLast,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    final status = order['status'] as String;
    final pickup = _shortAddress(order['pickupAddress'] as String? ?? '');
    final delivery = _shortAddress(order['deliveryAddress'] as String? ?? '');
    final price = order['price'] as num? ?? 0;
    final isScheduled = status == 'SCHEDULED';
    final isExpress = order['priority'] == 'EXPRESS';
    final date = _formatDateTime(
      isScheduled
          ? order['scheduledAt'] as String?
          : order['deliveredAt'] as String? ?? order['createdAt'] as String?,
    );
    final statusColor = _statusColor(status);
    final statusLbl = _statusLabel(status);
    final radius = isLast
        ? const BorderRadius.vertical(bottom: Radius.circular(16))
        : BorderRadius.zero;

    return InkWell(
      onTap: () => _navigateToOrder(context, order),
      borderRadius: radius,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: isLast ? null : Border(bottom: BorderSide(color: t.border)),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$pickup → $delivery',
                    style: ClientText.bodyStrong.copyWith(color: t.text),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    date,
                    style: ClientText.label.copyWith(color: t.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatFcfa(price),
                  style: ClientText.bodyStrong.copyWith(color: t.text),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: (isExpress ? AppColors.warning : AppColors.primary)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isExpress
                                ? Icons.bolt_rounded
                                : Icons.two_wheeler_rounded,
                            size: 10,
                            color: isExpress
                                ? AppColors.warning
                                : AppColors.primary,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            isExpress ? 'Express' : 'Simple',
                            style: ClientText.micro.copyWith(
                              color: isExpress
                                  ? AppColors.warning
                                  : AppColors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        statusLbl,
                        style: ClientText.micro.copyWith(color: statusColor),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Toggle vue Livraisons / Tournées — pastille glissante premium ────────────

class _ViewToggleBar extends StatelessWidget {
  final _ViewType viewType;
  final ValueChanged<_ViewType> onChanged;
  final _T t;
  const _ViewToggleBar({
    required this.viewType,
    required this.onChanged,
    required this.t,
  });

  static const _gap = 8.0;

  @override
  Widget build(BuildContext context) => Container(
    height: 48,
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: t.cardBg2,
      borderRadius: BorderRadius.circular(15),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final btnWidth = (constraints.maxWidth - _gap) / 2;
        final left = viewType == _ViewType.orders ? 0.0 : btnWidth + _gap;
        return Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              left: left,
              top: 0,
              bottom: 0,
              width: btnWidth,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.30),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
              ),
            ),
            Row(
              children: [
                SizedBox(
                  width: btnWidth,
                  child: _ToggleTapZone(
                    label: 'Livraisons',
                    icon: Icons.two_wheeler,
                    active: viewType == _ViewType.orders,
                    onTap: () => onChanged(_ViewType.orders),
                    t: t,
                  ),
                ),
                const SizedBox(width: _gap),
                SizedBox(
                  width: btnWidth,
                  child: _ToggleTapZone(
                    label: 'Tournées',
                    icon: Icons.route_outlined,
                    active: viewType == _ViewType.batches,
                    onTap: () => onChanged(_ViewType.batches),
                    t: t,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    ),
  );
}

class _ToggleTapZone extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final _T t;
  const _ToggleTapZone({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
    required this.t,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: Center(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 15, color: active ? Colors.white : t.muted),
          const SizedBox(width: 6),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            style: ClientText.body.copyWith(
              color: active ? Colors.white : t.muted,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
            child: Text(label),
          ),
        ],
      ),
    ),
  );
}

// ── Carte tournée active ──────────────────────────────────────────────────────

class _BatchCard extends StatelessWidget {
  final Map<String, dynamic> batch;
  final _T t;
  const _BatchCard({required this.batch, required this.t});

  @override
  Widget build(BuildContext context) {
    final status = batch['status'] as String? ?? 'PENDING';
    final orders =
        (batch['orders'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final total = (batch['totalPrice'] as num?) ?? 0;
    final pickup = batch['pickupAddress'] as String? ?? '';
    final driver = batch['driver'] as Map<String, dynamic>?;
    final createdAt = batch['createdAt'] as String?;
    final delivered = orders.where((o) => o['status'] == 'DELIVERED').length;
    final statusColor = _batchStatusColor(status);
    final statusLbl = _batchStatusLabel(status);
    final isActive = status == 'ACCEPTED' || status == 'IN_PROGRESS';

    return GestureDetector(
      onTap: () => context.push(
        '/dem-pro/batch/tracking',
        extra: {'batchId': batch['id'] as String},
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: t.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.border),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.route_outlined,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${orders.length} arrêt${orders.length > 1 ? 's' : ''}',
                        style: ClientText.subtitle.copyWith(color: t.text),
                      ),
                      Text(
                        driver != null
                            ? 'Livreur : ${driver['name'] as String? ?? 'DEM'}'
                            : 'En recherche de livreur…',
                        style: ClientText.label.copyWith(color: t.muted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    statusLbl,
                    style: ClientText.label.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Pickup ───────────────────────────────────────────────────────
            Row(
              children: [
                const Icon(
                  Icons.radio_button_on,
                  color: AppColors.primary,
                  size: 13,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    pickup.split(',').first.trim(),
                    style: ClientText.label.copyWith(color: t.muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ── Barre de progression ─────────────────────────────────────────
            if (isActive && orders.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: delivered / orders.length,
                  backgroundColor: t.cardBg2,
                  color: AppColors.successLight,
                  minHeight: 5,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '$delivered / ${orders.length} livrés',
                style: ClientText.label.copyWith(color: t.muted),
              ),
              const SizedBox(height: 10),
            ],

            // ── Pied ─────────────────────────────────────────────────────────
            Row(
              children: [
                Icon(Icons.payments_outlined, color: t.muted, size: 13),
                const SizedBox(width: 4),
                Text(
                  formatFcfa(total),
                  style: ClientText.bodyStrong.copyWith(color: t.text),
                ),
                const SizedBox(width: 12),
                Icon(Icons.schedule_outlined, color: t.muted, size: 13),
                const SizedBox(width: 4),
                Text(
                  _timeAgo(createdAt),
                  style: ClientText.label.copyWith(color: t.muted),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.map_outlined,
                        color: AppColors.primary,
                        size: 13,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Suivi',
                        style: ClientText.label.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Ligne historique tournée ──────────────────────────────────────────────────

class _BatchHistoryRow extends StatelessWidget {
  final Map<String, dynamic> batch;
  final bool isLast;
  final _T t;
  const _BatchHistoryRow({
    required this.batch,
    required this.isLast,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    final status = batch['status'] as String? ?? '';
    final total = (batch['totalPrice'] as num?) ?? 0;
    final orders = (batch['orders'] as List?)?.length ?? 0;
    final createdAt = batch['createdAt'] as String?;
    final statusColor = _batchStatusColor(status);
    final statusLbl = _batchStatusLabel(status);
    final radius = isLast
        ? const BorderRadius.vertical(bottom: Radius.circular(16))
        : BorderRadius.zero;

    return InkWell(
      onTap: () => context.push(
        '/dem-pro/batch/tracking',
        extra: {'batchId': batch['id'] as String},
      ),
      borderRadius: radius,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: isLast ? null : Border(bottom: BorderSide(color: t.border)),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$orders arrêt${orders > 1 ? 's' : ''}',
                    style: ClientText.bodyStrong.copyWith(color: t.text),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatDateTime(createdAt),
                    style: ClientText.label.copyWith(color: t.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatFcfa(total),
                  style: ClientText.bodyStrong.copyWith(color: t.text),
                ),
                const SizedBox(height: 3),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    statusLbl,
                    style: ClientText.micro.copyWith(color: statusColor),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── État vide intelligent ─────────────────────────────────────────────────────

class _EmptyOrdersState extends StatelessWidget {
  final _T t;
  final bool globallyEmpty;
  final bool searching;
  final VoidCallback onOrder;
  const _EmptyOrdersState({
    required this.t,
    required this.globallyEmpty,
    this.searching = false,
    required this.onOrder,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(
              searching ? Icons.search_off_rounded : Icons.two_wheeler,
              color: AppColors.primary,
              size: 40,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            searching
                ? 'Aucun résultat'
                : globallyEmpty
                ? 'Aucune livraison encore'
                : 'Aucune livraison ici',
            style: ClientText.title.copyWith(color: t.text, fontSize: 17),
          ),
          const SizedBox(height: 8),
          Text(
            searching
                ? 'Aucune livraison ne correspond à votre recherche.'
                : globallyEmpty
                ? 'Passez votre première commande et suivez-la ici en temps réel'
                : 'Aucune livraison dans cette catégorie pour le moment.',
            style: ClientText.body.copyWith(color: t.muted, height: 1.5),
            textAlign: TextAlign.center,
          ),
          if (globallyEmpty && !searching) ...[
            const SizedBox(height: 24),
            GestureDetector(
              onTap: onOrder,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Commander maintenant',
                      style: ClientText.button.copyWith(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Onglet Adresses
// ─────────────────────────────────────────────────────────────────────────────

const _iconMeta = {
  'store': (Icons.storefront_outlined, 'Boutique'),
  'warehouse': (Icons.warehouse_outlined, 'Entrepôt'),
  'office': (Icons.business_outlined, 'Bureau'),
  'home': (Icons.home_outlined, 'Domicile'),
  'other': (Icons.place_outlined, 'Autre'),
};

// ── Bouton d'action dans un header dégradé — cercle blanc translucide avec
// un léger rebond au tap (même famille que les autres micro-animations du
// module, sans avoir besoin d'un AnimationController).
class _HeaderIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _HeaderIconButton({required this.icon, required this.onTap});

  @override
  State<_HeaderIconButton> createState() => _HeaderIconButtonState();
}

class _HeaderIconButtonState extends State<_HeaderIconButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown: (_) => setState(() => _pressed = true),
    onTapUp: (_) => setState(() => _pressed = false),
    onTapCancel: () => setState(() => _pressed = false),
    onTap: widget.onTap,
    child: AnimatedScale(
      scale: _pressed ? 0.86 : 1.0,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.20),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(widget.icon, color: Colors.white, size: 22),
      ),
    ),
  );
}

// ── Menu d'actions sur une adresse — feuille modale stylée au lieu du
// PopupMenuButton Material par défaut, pour rester cohérent avec le reste
// du module (mêmes codes couleur que les autres feuilles : primary/warning/
// error selon la gravité de l'action).
void _showAddressActions(
  BuildContext context, {
  required bool isDefault,
  required VoidCallback onEdit,
  required VoidCallback onSetDefault,
  required VoidCallback onDelete,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) => Container(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.of(sheetCtx).viewPadding.bottom + 20,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: AppColors.lightBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          _AddressActionTile(
            icon: Icons.edit_outlined,
            color: AppColors.primary,
            label: 'Modifier',
            onTap: () {
              Navigator.pop(sheetCtx);
              onEdit();
            },
          ),
          if (!isDefault) ...[
            const SizedBox(height: 8),
            _AddressActionTile(
              icon: Icons.star_outline_rounded,
              color: AppColors.warning,
              label: 'Définir par défaut',
              onTap: () {
                Navigator.pop(sheetCtx);
                onSetDefault();
              },
            ),
          ],
          const SizedBox(height: 8),
          _AddressActionTile(
            icon: Icons.delete_outline_rounded,
            color: AppColors.error,
            label: 'Supprimer',
            onTap: () {
              Navigator.pop(sheetCtx);
              onDelete();
            },
          ),
        ],
      ),
    ),
  );
}

class _AddressActionTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  const _AddressActionTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Text(label, style: ClientText.bodyStrong.copyWith(color: color)),
        ],
      ),
    ),
  );
}

class _AdressesTab extends StatefulWidget {
  final _T t;
  const _AdressesTab({required this.t});
  @override
  State<_AdressesTab> createState() => _AdressesTabState();
}

class _AdressesTabState extends State<_AdressesTab>
    with AutomaticKeepAliveClientMixin {
  final _repo = DemProRepository(ApiClient.dio);
  final _search = TextEditingController();

  @override
  bool get wantKeepAlive => true;

  List<Map<String, dynamic>> _addresses = [];
  List<Map<String, dynamic>> _recent = [];
  bool _loading = true;
  String _query = '';

  _T get t => widget.t;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _repo.getAddresses(),
        _repo.getRecentPickups(),
      ]);
      if (!mounted) return;
      setState(() {
        _addresses = results[0];
        _recent = results[1];
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_query.isEmpty) return _addresses;
    return _addresses.where((a) {
      final label = (a['label'] as String? ?? '').toLowerCase();
      final address = (a['address'] as String? ?? '').toLowerCase();
      return label.contains(_query) || address.contains(_query);
    }).toList();
  }

  Future<void> _showForm({Map<String, dynamic>? existing}) async {
    final refreshed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddressFormSheet(t: t, repo: _repo, existing: existing),
    );
    if (refreshed == true) _load();
  }

  Future<void> _delete(Map<String, dynamic> addr) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: t.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Supprimer ?',
          style: ClientText.title.copyWith(color: t.text),
        ),
        content: Text(
          'Voulez-vous supprimer "${addr['label']}" ?',
          style: ClientText.body.copyWith(color: t.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Annuler',
              style: ClientText.body.copyWith(color: t.muted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Supprimer',
              style: ClientText.body.copyWith(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repo.deleteAddress(addr['id'] as String);
      _load();
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Une erreur est survenue.')),
        );
    }
  }

  Future<void> _setDefault(Map<String, dynamic> addr) async {
    try {
      await _repo.setDefaultAddress(addr['id'] as String);
      _load();
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Une erreur est survenue.')),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // ── Tap en dehors de la barre de recherche → referme le clavier ────────
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.translucent,
      child: Column(
        children: [
          // ── Header dégradé cyan — même pattern que Livraisons/Accueil ────
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(gradient: AppColors.gradientSplash),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 22),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.20),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.place_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Mes adresses',
                            style: ClientText.headline.copyWith(
                              color: Colors.white,
                              fontSize: 21,
                            ),
                          ),
                          Text(
                            'Points de départ favoris',
                            style: ClientText.micro.copyWith(
                              color: Colors.white.withValues(alpha: 0.75),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_addresses.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.20),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_addresses.length} adresse${_addresses.length > 1 ? 's' : ''}',
                          style: ClientText.micro.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    _HeaderIconButton(
                      icon: Icons.add_rounded,
                      onTap: () => _showForm(),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Barre de recherche ────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _OrderSearchField(
              controller: _search,
              t: t,
              hintText: 'Rechercher une adresse…',
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
          ),
          const SizedBox(height: 4),

          // ── Contenu ───────────────────────────────────────────────────────
          Expanded(
            child: _loading
                ? Center(
                    child: CircularProgressIndicator(
                      color: AppColors.primary,
                      strokeWidth: 2,
                    ),
                  )
                : RefreshIndicator(
                    color: AppColors.primary,
                    backgroundColor: t.cardBg,
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        if (_filtered.isEmpty && _query.isNotEmpty) ...[
                          _buildEmptySearch(),
                        ] else if (_filtered.isEmpty && _recent.isEmpty) ...[
                          _buildEmptyState(),
                        ] else ...[
                          if (_filtered.isNotEmpty) ...[
                            _buildSectionHeader(
                              'Favoris',
                              '${_filtered.length}',
                            ),
                            const SizedBox(height: 10),
                            ..._filtered.map(
                              (a) => _AddressCard(
                                addr: a,
                                t: t,
                                onEdit: () => _showForm(existing: a),
                                onDelete: () => _delete(a),
                                onSetDefault: () => _setDefault(a),
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],
                          if (_recent.isNotEmpty && _query.isEmpty) ...[
                            _buildSectionHeader('Depuis vos commandes', null),
                            const SizedBox(height: 4),
                            Text(
                              'Adresses utilisées récemment comme point de départ',
                              style: ClientText.label.copyWith(
                                color: t.muted,
                              ),
                            ),
                            const SizedBox(height: 10),
                            ..._recent.map(
                              (r) => _RecentPickupRow(
                                addr: r,
                                t: t,
                                onSave: () => _showForm(
                                  existing: {
                                    'address': r['address'],
                                    'lat': r['lat'],
                                    'lng': r['lng'],
                                  },
                                ),
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, String? count) => Row(
    children: [
      Text(title, style: ClientText.bodyStrong.copyWith(color: t.text)),
      if (count != null) ...[
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            count,
            style: ClientText.label.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ],
  );

  Widget _buildEmptySearch() => Padding(
    padding: const EdgeInsets.only(top: 60),
    child: Column(
      children: [
        Icon(Icons.search_off, color: t.muted, size: 40),
        const SizedBox(height: 12),
        Text(
          'Aucun résultat pour "$_query"',
          style: ClientText.subtitle.copyWith(color: t.text, fontSize: 15),
        ),
        const SizedBox(height: 6),
        Text(
          'Essayez avec un autre terme.',
          style: ClientText.body.copyWith(color: t.muted),
        ),
      ],
    ),
  );

  Widget _buildEmptyState() => Padding(
    padding: const EdgeInsets.only(top: 60),
    child: Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            shape: BoxShape.circle,
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.20),
              width: 1.5,
            ),
          ),
          child: const Icon(
            Icons.place_outlined,
            color: AppColors.primary,
            size: 32,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Aucune adresse enregistrée',
          style: ClientText.title.copyWith(color: t.text, fontSize: 17),
        ),
        const SizedBox(height: 8),
        Text(
          'Ajoutez vos points de départ favoris\n(boutique, entrepôt, bureau…)',
          style: ClientText.body.copyWith(color: t.muted, height: 1.5),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        GestureDetector(
          onTap: () => _showForm(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.add, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Ajouter une adresse',
                  style: ClientText.button.copyWith(fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

// ── Card adresse favorite ─────────────────────────────────────────────────────

class _AddressCard extends StatelessWidget {
  final Map<String, dynamic> addr;
  final _T t;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onSetDefault;

  const _AddressCard({
    required this.addr,
    required this.t,
    required this.onEdit,
    required this.onDelete,
    required this.onSetDefault,
  });

  @override
  Widget build(BuildContext context) {
    final isDefault = addr['isDefault'] as bool? ?? false;
    final icon = addr['icon'] as String? ?? 'other';
    final label = addr['label'] as String? ?? '';
    final address = addr['address'] as String? ?? '';
    final landmark = addr['landmark'] as String?;
    final meta = _iconMeta[icon] ?? _iconMeta['other']!;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: t.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDefault
              ? AppColors.primary.withValues(alpha: 0.5)
              : t.border,
          width: isDefault ? 1.5 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onEdit,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(meta.$1, color: AppColors.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            label,
                            style: ClientText.subtitle.copyWith(color: t.text),
                          ),
                          if (isDefault) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(
                                  alpha: 0.12,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Par défaut',
                                style: ClientText.micro.copyWith(
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        address,
                        style: ClientText.label.copyWith(color: t.muted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (landmark != null && landmark.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(Icons.info_outline, color: t.muted, size: 12),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                landmark,
                                style: ClientText.label.copyWith(
                                  color: t.muted,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => _showAddressActions(
                    context,
                    isDefault: isDefault,
                    onEdit: onEdit,
                    onSetDefault: onSetDefault,
                    onDelete: onDelete,
                  ),
                  child: Icon(Icons.more_vert, color: t.muted, size: 20),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Ligne adresse récente (depuis commandes) ──────────────────────────────────

class _RecentPickupRow extends StatelessWidget {
  final Map<String, dynamic> addr;
  final _T t;
  final VoidCallback onSave;

  const _RecentPickupRow({
    required this.addr,
    required this.t,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final address = addr['address'] as String? ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.10)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.history, color: AppColors.primary, size: 18),
        ),
        title: Text(
          address,
          style: ClientText.bodyStrong.copyWith(color: t.text),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: GestureDetector(
          onTap: onSave,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Sauvegarder',
              style: ClientText.label.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Formulaire adresse (bottom sheet) ────────────────────────────────────────

class _AddressFormSheet extends StatefulWidget {
  final _T t;
  final DemProRepository repo;
  final Map<String, dynamic>? existing;
  const _AddressFormSheet({required this.t, required this.repo, this.existing});
  @override
  State<_AddressFormSheet> createState() => _AddressFormSheetState();
}

const _addressSheetSuggestionColors = PlaceSuggestionsColors(
  background: AppColors.lightFill,
  border: AppColors.lightBorder,
  divider: AppColors.lightBorder,
  iconBg: AppColors.lightBorder,
  icon: AppColors.primary,
  mainText: AppColors.textDark,
  secondaryText: AppColors.textMuted,
  accent: AppColors.primary,
);

class _AddressFormSheetState extends State<_AddressFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _label;
  late final TextEditingController _address;
  late final TextEditingController _landmark;
  String _icon = 'other';
  bool _isDefault = false;
  bool _saving = false;

  // ── Autocomplétion — jusqu'ici ce champ était un simple TextFormField
  // sans recherche Google Places ni coordonnées GPS capturées (lat/lng
  // toujours absents du payload malgré leur support côté backend/repo).
  double? _lat, _lng;
  List<Map<String, dynamic>> _suggestions = [];
  bool _searching = false;
  String? _searchError;
  String? _sessionToken;
  bool _locating = false;
  Timer? _debounce;
  final _dio = Dio();
  late final _placesService = PlacesAutocompleteService(_dio);

  bool get _isEdit =>
      widget.existing != null && widget.existing!.containsKey('id');
  _T get t => widget.t;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _label = TextEditingController(text: e?['label'] as String? ?? '');
    _address = TextEditingController(text: e?['address'] as String? ?? '');
    _landmark = TextEditingController(text: e?['landmark'] as String? ?? '');
    _icon = e?['icon'] as String? ?? 'other';
    _isDefault = e?['isDefault'] as bool? ?? false;
    _lat = (e?['lat'] as num?)?.toDouble();
    _lng = (e?['lng'] as num?)?.toDouble();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _label.dispose();
    _address.dispose();
    _landmark.dispose();
    super.dispose();
  }

  void _onAddressChanged(String q) {
    setState(() {
      _lat = null;
      _lng = null;
    });
    _debounce?.cancel();
    if (q.trim().length < 3) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = []);
      return;
    }
    _sessionToken ??= PlacesAutocompleteService.newSessionToken();
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      if (!mounted) return;
      setState(() {
        _searching = true;
        _searchError = null;
      });
      try {
        final preds = await _placesService.autocomplete(
          query: q,
          sessionToken: _sessionToken!,
        );
        if (mounted) {
          setState(() {
            _suggestions = preds;
            _searching = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _searching = false;
            _searchError = e.toString();
          });
        }
      }
    });
  }

  void _retryAddressSearch() => _onAddressChanged(_address.text);

  Future<void> _selectSuggestion(Map<String, dynamic> place) async {
    FocusScope.of(context).unfocus();
    setState(() => _suggestions = []);
    final placeId = place['place_id'] as String?;
    if (placeId == null) return;
    final token = _sessionToken ?? PlacesAutocompleteService.newSessionToken();
    try {
      final result = await _placesService.details(
        placeId: placeId,
        sessionToken: token,
      );
      if (result != null) {
        final loc = result['geometry']['location'];
        final addr =
            result['formatted_address'] as String? ??
            (place['structured_formatting']?['main_text'] as String? ?? '');
        setState(() {
          _lat = (loc['lat'] as num).toDouble();
          _lng = (loc['lng'] as num).toDouble();
          _address.text = addr;
        });
      }
    } catch (_) {
    } finally {
      _sessionToken = null;
    }
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      _locating = true;
      _suggestions = [];
    });
    try {
      final pos = await NavigationService.requestAndGetPosition();
      if (pos == null || !mounted) return;
      String? addr = await _placesService.reverseGeocode(
        pos.latitude,
        pos.longitude,
      );
      if (addr == null || addr.isEmpty) {
        try {
          final marks = await geo
              .placemarkFromCoordinates(pos.latitude, pos.longitude)
              .timeout(const Duration(seconds: 5));
          if (marks.isNotEmpty) {
            final p = marks.first;
            final street = p.street ?? p.name ?? '';
            final local = p.subLocality ?? p.locality ?? '';
            final built = street.isNotEmpty ? '$street, $local' : local;
            if (built.isNotEmpty) addr = built;
          }
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
        _address.text = (addr != null && addr.isNotEmpty)
            ? addr
            : 'Position sélectionnée';
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Impossible de récupérer la position.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_lat == null || _lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Sélectionnez l'adresse dans la liste ou utilisez votre position actuelle.",
          ),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final data = {
        'label': _label.text.trim(),
        'address': _address.text.trim(),
        'landmark': _landmark.text.trim().isEmpty
            ? null
            : _landmark.text.trim(),
        'icon': _icon,
        'isDefault': _isDefault,
        'lat': _lat,
        'lng': _lng,
      };
      if (_isEdit) {
        await widget.repo.updateAddress(widget.existing!['id'] as String, data);
      } else {
        await widget.repo.createAddress(data);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: BoxDecoration(
        color: t.cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottomPadding),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Handle + titre ─────────────────────────────────────────────
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: t.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              Text(
                _isEdit ? 'Modifier l\'adresse' : 'Nouvelle adresse',
                style: ClientText.title.copyWith(color: t.text, fontSize: 18),
              ),
              const SizedBox(height: 20),

              // ── Sélecteur d'icône ──────────────────────────────────────────
              Text(
                'Type de lieu',
                style: ClientText.label.copyWith(color: t.muted),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 64,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: _iconMeta.entries.map((e) {
                    final selected = _icon == e.key;
                    return GestureDetector(
                      onTap: () => setState(() => _icon = e.key),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: selected ? AppColors.primary : t.cardBg2,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected ? AppColors.primary : t.border,
                            width: selected ? 1.5 : 1,
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              e.value.$1,
                              color: selected ? Colors.white : t.muted,
                              size: 20,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              e.value.$2,
                              style: ClientText.micro.copyWith(
                                color: selected ? Colors.white : t.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 16),

              // ── Libellé ────────────────────────────────────────────────────
              _FieldLabel('Libellé', t),
              const SizedBox(height: 6),
              _FormField(
                controller: _label,
                t: t,
                hint: 'ex: Boutique Médina, Entrepôt Pikine…',
                validator: (v) => (v == null || v.trim().length < 2)
                    ? 'Minimum 2 caractères'
                    : null,
              ),
              const SizedBox(height: 14),

              // ── Adresse ────────────────────────────────────────────────────
              _FieldLabel('Adresse', t),
              const SizedBox(height: 6),
              _FormField(
                controller: _address,
                t: t,
                hint: 'ex: Rue 10 x Gueule Tapée, Médina, Dakar',
                validator: (v) => (v == null || v.trim().length < 4)
                    ? 'Adresse trop courte'
                    : null,
                onChanged: _onAddressChanged,
                suffixIcon: _lat != null
                    ? const Icon(
                        Icons.check_circle,
                        color: Colors.green,
                        size: 20,
                      )
                    : _searching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        ),
                      )
                    : _address.text.trim().isNotEmpty
                    ? Icon(
                        Icons.error_outline,
                        color: Colors.orange.shade700,
                        size: 20,
                      )
                    : null,
              ),
              if (_address.text.trim().isNotEmpty &&
                  _lat == null &&
                  !_searching) ...[
                const SizedBox(height: 6),
                Text(
                  'Sélectionnez une adresse dans la liste ou utilisez votre position actuelle.',
                  style: ClientText.label.copyWith(
                    color: Colors.orange.shade800,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _locating ? null : _useCurrentLocation,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      _locating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primary,
                              ),
                            )
                          : const Icon(
                              Icons.my_location,
                              color: AppColors.primary,
                              size: 16,
                            ),
                      const SizedBox(width: 8),
                      Text(
                        _locating
                            ? 'Localisation en cours…'
                            : 'Utiliser ma position actuelle',
                        style: ClientText.body.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_suggestions.isNotEmpty ||
                  _searching ||
                  _searchError != null) ...[
                const SizedBox(height: 4),
                PlaceSuggestionsList(
                  suggestions: _suggestions,
                  loading: _searching,
                  error: _searchError,
                  onRetry: _retryAddressSearch,
                  onSelect: _selectSuggestion,
                  colors: _addressSheetSuggestionColors,
                  maxHeight: 200,
                ),
              ],
              const SizedBox(height: 14),

              // ── Repère ─────────────────────────────────────────────────────
              _FieldLabel('Repère (optionnel)', t),
              const SizedBox(height: 6),
              _FormField(
                controller: _landmark,
                t: t,
                hint: 'ex: Face à la mosquée, derrière la station Total…',
                validator: null,
              ),
              const SizedBox(height: 16),

              // ── Adresse par défaut ─────────────────────────────────────────
              Container(
                decoration: BoxDecoration(
                  color: t.cardBg2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: t.border),
                ),
                child: SwitchListTile(
                  value: _isDefault,
                  onChanged: (v) => setState(() => _isDefault = v),
                  activeTrackColor: AppColors.primary,
                  activeThumbColor: Colors.white,
                  inactiveThumbColor: Colors.white,
                  inactiveTrackColor: t.border,
                  title: Text(
                    'Adresse par défaut',
                    style: ClientText.subtitle.copyWith(color: t.text),
                  ),
                  subtitle: Text(
                    'Pré-sélectionnée lors d\'une nouvelle commande',
                    style: ClientText.label.copyWith(color: t.muted),
                  ),
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 4,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // ── CTA ────────────────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 52,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.30),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _saving ? null : _submit,
                      child: Center(
                        child: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                _isEdit
                                    ? 'Enregistrer les modifications'
                                    : 'Ajouter l\'adresse',
                                style: ClientText.button.copyWith(color: AppColors.textDark),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  final _T t;
  const _FieldLabel(this.text, this.t);
  @override
  Widget build(BuildContext context) =>
      Text(text, style: ClientText.label.copyWith(color: t.muted));
}

class _FormField extends StatelessWidget {
  final TextEditingController controller;
  final _T t;
  final String hint;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final Widget? suffixIcon;
  const _FormField({
    required this.controller,
    required this.t,
    required this.hint,
    required this.validator,
    this.onChanged,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    validator: validator,
    onChanged: onChanged,
    style: ClientText.body.copyWith(color: t.text, fontSize: 14),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: ClientText.body.copyWith(color: t.muted),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: t.cardBg2,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: t.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: t.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.error, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Onglet Finances
// ─────────────────────────────────────────────────────────────────────────────

const _periodOptions = [
  ('today', 'Jour'),
  ('this_week', 'Semaine'),
  ('this_month', 'Mois'),
  ('prev_month', 'Mois -1'),
  ('3months', '3 mois'),
];

enum _FinanceView { sales, deliveries, insights }

class _FinancesTab extends StatefulWidget {
  final _T t;
  final Map<String, dynamic>? user;
  const _FinancesTab({super.key, required this.t, this.user});
  @override
  State<_FinancesTab> createState() => _FinancesTabState();
}

class _FinancesTabState extends State<_FinancesTab>
    with AutomaticKeepAliveClientMixin {
  final _repo = DemProRepository(ApiClient.dio);

  @override
  bool get wantKeepAlive => true;

  String _period = 'this_month';
  _FinanceView _view = _FinanceView.sales;

  Map<String, dynamic>? _financeData;
  Map<String, dynamic>? _insightsData;
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;
  String? _error;

  _T get t => widget.t;

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
      final results = await Future.wait([
        _repo.getMyFinances(_period),
        _repo.getMyOrders(),
        _repo.getBusinessInsights(_period),
      ]);
      if (!mounted) return;
      setState(() {
        _financeData = results[0] as Map<String, dynamic>;
        _orders = (results[1] as List).cast<Map<String, dynamic>>();
        _insightsData = results[2] as Map<String, dynamic>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _selectPeriod(String p) {
    if (p == _period) return;
    setState(() => _period = p);
    _load();
  }

  // ── Filtrage des commandes par période ────────────────────────────────────
  // Filtre et trie sur deliveredAt (pas createdAt) — c'est la date que
  // getMyFinances()/getBusinessInsights() utilisent côté serveur pour ces
  // mêmes indicateurs. Avant ce correctif, une commande créée un jour et
  // livrée le lendemain pouvait apparaître dans une période différente
  // selon la vue (Ventes vs Livraisons/Pilotage), pour un même total
  // affiché deux fois différemment — gênant pour la compta du commerçant.
  List<Map<String, dynamic>> get _filteredOrders {
    final now = DateTime.now();
    final delivered = _orders
        .where((o) => (o['status'] as String? ?? '').toUpperCase() == 'DELIVERED')
        .where((o) {
          final dt = DateTime.tryParse(
            o['deliveredAt'] as String? ?? '',
          )?.toLocal();
          if (dt == null) return false;
          return switch (_period) {
            'today' =>
              dt.year == now.year && dt.month == now.month && dt.day == now.day,
            'this_week' => now.difference(dt).inDays < 7,
            'this_month' => dt.year == now.year && dt.month == now.month,
            'prev_month' => switch (now.month) {
              1 => dt.year == now.year - 1 && dt.month == 12,
              _ => dt.year == now.year && dt.month == now.month - 1,
            },
            '3months' => now.difference(dt).inDays < 90,
            _ => true,
          };
        })
        .toList();
    delivered.sort(
      (a, b) => (b['deliveredAt'] as String? ?? '').compareTo(
        a['deliveredAt'] as String? ?? '',
      ),
    );
    return delivered;
  }

  int get _totalSales {
    int total = 0;
    for (final o in _filteredOrders) {
      final items = o['items'] as List?;
      if (items != null) {
        for (final item in items) {
          total +=
              ((item['price'] as num?)?.toInt() ?? 0) *
              ((item['quantity'] as num?)?.toInt() ?? 1);
        }
      }
    }
    return total;
  }

  int get _totalDelivery {
    int total = 0;
    for (final o in _filteredOrders) {
      total += (o['price'] as num?)?.toInt() ?? 0;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SafeArea(
      child: Column(
        children: [
          // ── Header ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Finances',
                    style: ClientText.headline.copyWith(
                      color: t.text,
                      fontSize: 22,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Filtre 1 — Période ───────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Row(
              children: _periodOptions.map((opt) {
                final selected = _period == opt.$1;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => _selectPeriod(opt.$1),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: EdgeInsets.only(
                        right: opt.$1 != '3months' ? 6 : 0,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: selected ? AppColors.primary : t.cardBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected ? AppColors.primary : t.border,
                        ),
                      ),
                      child: Text(
                        opt.$2,
                        textAlign: TextAlign.center,
                        style: ClientText.label.copyWith(
                          color: selected ? Colors.white : t.muted,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // ── Filtre 2 — Ventes / Livraisons ──────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: t.cardBg2,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  _FinanceToggle(
                    label: 'Ventes',
                    icon: Icons.shopping_bag_outlined,
                    active: _view == _FinanceView.sales,
                    onTap: () => setState(() => _view = _FinanceView.sales),
                    t: t,
                  ),
                  _FinanceToggle(
                    label: 'Livraisons',
                    icon: Icons.two_wheeler,
                    active: _view == _FinanceView.deliveries,
                    onTap: () =>
                        setState(() => _view = _FinanceView.deliveries),
                    t: t,
                  ),
                  _FinanceToggle(
                    label: 'Pilotage',
                    icon: Icons.insights_rounded,
                    active: _view == _FinanceView.insights,
                    onTap: () =>
                        setState(() => _view = _FinanceView.insights),
                    t: t,
                  ),
                ],
              ),
            ),
          ),

          // ── Contenu ───────────────────────────────────────────────────────
          Expanded(
            child: _loading
                ? Center(
                    child: CircularProgressIndicator(
                      color: AppColors.primary,
                      strokeWidth: 2,
                    ),
                  )
                : _error != null
                ? _buildError()
                : RefreshIndicator(
                    color: AppColors.primary,
                    backgroundColor: t.cardBg,
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: switch (_view) {
                        _FinanceView.sales => _buildSalesContent(),
                        _FinanceView.deliveries => _buildDeliveriesContent(),
                        _FinanceView.insights => _buildInsightsContent(),
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.wifi_off_rounded, color: t.muted, size: 36),
        const SizedBox(height: 12),
        Text(
          'Impossible de charger les données',
          style: ClientText.subtitle.copyWith(color: t.text, fontSize: 15),
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: _load,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'Réessayer',
              style: ClientText.button.copyWith(fontSize: 14),
            ),
          ),
        ),
      ],
    ),
  );

  // ── Vue VENTES ──────────────────────────────────────────────────────────────

  List<Widget> _buildSalesContent() {
    final orders = _filteredOrders;
    int totalItems = 0;
    for (final o in orders) {
      final items = o['items'] as List?;
      if (items != null) totalItems += items.length;
    }

    return [
      // Résumé ventes
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.white, AppColors.lightBg],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.successLight.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.trending_up,
                    color: AppColors.successLight,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Ventes',
                  style: ClientText.label.copyWith(color: t.muted),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              formatFcfa(_totalSales),
              style: ClientText.hero.copyWith(color: t.text),
            ),
            Text(
              'Chiffre d\'affaires',
              style: ClientText.label.copyWith(color: t.muted),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _MiniStat(
                    value: orders.length.toString(),
                    label: 'Commandes',
                    color: AppColors.primary,
                    t: t,
                  ),
                ),
                Container(width: 1, height: 40, color: t.border),
                Expanded(
                  child: _MiniStat(
                    value: totalItems.toString(),
                    label: 'Articles vendus',
                    color: AppColors.successLight,
                    t: t,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),

      // Historique ventes
      Row(
        children: [
          Text(
            'Historique des ventes',
            style: ClientText.bodyStrong.copyWith(color: t.text),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${orders.length}',
              style: ClientText.label.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      if (orders.isEmpty)
        _buildEmpty('Aucune vente sur cette période')
      else
        ...orders.map((o) => _SaleRow(order: o, t: t)),
    ];
  }

  // ── Vue LIVRAISONS ─────────────────────────────────────────────────────────

  List<Widget> _buildDeliveriesContent() {
    final orders = _filteredOrders;
    final summary = _financeData?['summary'] as Map<String, dynamic>? ?? {};
    final total = (summary['totalSpent'] as num?) ?? _totalDelivery;
    final count = (summary['deliveriesCount'] as num?) ?? orders.length;
    final avg =
        (summary['avgCostPerDelivery'] as num?) ??
        (orders.isNotEmpty ? _totalDelivery / orders.length : 0);
    final breakdown =
        (_financeData?['breakdown'] as List?)?.cast<Map<String, dynamic>>() ??
        [];

    return [
      // Résumé livraisons
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.white, AppColors.lightBg],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.two_wheeler,
                    color: AppColors.primary,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Livraisons',
                  style: ClientText.label.copyWith(color: t.muted),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              formatFcfa(total.toInt()),
              style: ClientText.hero.copyWith(color: t.text),
            ),
            Text(
              'Total dépensé',
              style: ClientText.label.copyWith(color: t.muted),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _MiniStat(
                    value: count.toInt().toString(),
                    label: 'Livraisons',
                    color: AppColors.primary,
                    t: t,
                  ),
                ),
                Container(width: 1, height: 40, color: t.border),
                Expanded(
                  child: _MiniStat(
                    value: '${formatFcfa(avg.toInt())}',
                    label: 'Coût moyen',
                    color: AppColors.successLight,
                    t: t,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),

      // Graphique
      if (breakdown.isNotEmpty) ...[
        _buildChart(breakdown),
        const SizedBox(height: 20),
      ],

      // Transactions
      Row(
        children: [
          Text(
            'Transactions',
            style: ClientText.bodyStrong.copyWith(color: t.text),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${orders.length}',
              style: ClientText.label.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      if (orders.isEmpty)
        _buildEmpty('Aucune livraison sur cette période')
      else
        ...orders.map((o) => _DeliveryRow(order: o, t: t)),
    ];
  }

  // ── Vue PILOTAGE ───────────────────────────────────────────────────────────
  // Indicateurs de pilotage business — jusqu'ici l'onglet Finances ne
  // montrait qu'un historique de transactions, jamais de quoi vraiment
  // suivre son activité (délai de livraison, fiabilité, destinataires
  // récurrents, tendance). Toutes ces données existaient déjà côté
  // serveur (Order.acceptedAt/deliveredAt, Rating, cancelReason...), il
  // ne manquait que l'agrégation et cet écran.
  String _formatMinutes(int minutes) {
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h${m.toString().padLeft(2, '0')}';
  }

  List<Widget> _buildInsightsContent() {
    final data = _insightsData;
    if (data == null) return [_buildEmpty('Aucune donnée sur cette période')];

    final avgMinutes = (data['avgDeliveryMinutes'] as num?)?.toInt();
    final topDriver = data['topDriver'] as Map<String, dynamic>?;
    final cancellationRate = (data['cancellationRate'] as num?)?.toDouble() ?? 0;
    final totalCreated = (data['totalOrdersCreated'] as num?)?.toInt() ?? 0;
    final topDestinations =
        (data['topDestinations'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final trend = data['trend'] as Map<String, dynamic>? ?? {};
    final spendTrendPct = (trend['spendTrendPct'] as num?)?.toDouble();
    final currentTotal = (trend['currentTotal'] as num?)?.toInt() ?? 0;
    final currentCount = (trend['currentCount'] as num?)?.toInt() ?? 0;

    // Volume hebdomadaire déclaré à l'inscription — jusqu'ici jamais
    // réutilisé nulle part après l'onboarding, une donnée purement
    // déclarative. Comparé au nombre réel de livraisons de la semaine
    // uniquement quand ce filtre est sélectionné (sinon la comparaison
    // n'a pas de sens).
    final weeklyVolume = widget.user?['proWeeklyVolume'] as String?;
    const weeklyMin = {'low': 1, 'medium': 5, 'high': 9};

    return [
      if (_period == 'this_week' && weeklyVolume != null) ...[
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: t.border),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.flag_outlined,
                    color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Objectif : ${_volumeLabels[weeklyVolume] ?? weeklyVolume}',
                        style: ClientText.bodyStrong.copyWith(color: t.text)),
                    Text('$currentCount livraison(s) cette semaine',
                        style: ClientText.label.copyWith(color: t.muted)),
                  ],
                ),
              ),
              if ((weeklyMin[weeklyVolume] ?? 0) <= currentCount)
                const Icon(Icons.check_circle, color: AppColors.successLight, size: 22),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],

      // ── Tendance ──────────────────────────────────────────────────────────
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.white, AppColors.lightBg],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Dépensé cette période',
                style: ClientText.label.copyWith(color: t.muted)),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(formatFcfa(currentTotal),
                    style: ClientText.hero.copyWith(color: t.text)),
                if (spendTrendPct != null) ...[
                  const SizedBox(width: 10),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: (spendTrendPct >= 0
                                ? AppColors.successLight
                                : AppColors.error)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            spendTrendPct >= 0
                                ? Icons.arrow_upward_rounded
                                : Icons.arrow_downward_rounded,
                            size: 12,
                            color: spendTrendPct >= 0
                                ? AppColors.successLight
                                : AppColors.error,
                          ),
                          Text(
                            '${spendTrendPct.abs().toStringAsFixed(0)}%',
                            style: ClientText.label.copyWith(
                              color: spendTrendPct >= 0
                                  ? AppColors.successLight
                                  : AppColors.error,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
            Text('vs période précédente équivalente',
                style: ClientText.micro.copyWith(color: t.muted)),
          ],
        ),
      ),
      const SizedBox(height: 16),

      // ── Délai moyen + Taux d'annulation ──────────────────────────────────
      Row(
        children: [
          Expanded(
            child: _InsightCard(
              icon: Icons.timer_outlined,
              label: 'Délai moyen',
              value: avgMinutes != null ? _formatMinutes(avgMinutes) : '—',
              t: t,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _InsightCard(
              icon: Icons.cancel_outlined,
              label: 'Annulations',
              value: totalCreated > 0
                  ? '${cancellationRate.toStringAsFixed(0)}%'
                  : '—',
              valueColor: cancellationRate > 15 ? AppColors.error : null,
              t: t,
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),

      // ── Livreur habituel ──────────────────────────────────────────────────
      Text('Livreur habituel',
          style: ClientText.bodyStrong.copyWith(color: t.text)),
      const SizedBox(height: 10),
      if (topDriver == null)
        _buildEmpty('Aucune livraison sur cette période')
      else
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: t.cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: t.border),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.two_wheeler,
                    color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(topDriver['name'] as String? ?? 'Livreur DEM',
                        style: ClientText.bodyStrong.copyWith(color: t.text)),
                    Text('${topDriver['count']} livraison(s) sur la période',
                        style: ClientText.label.copyWith(color: t.muted)),
                  ],
                ),
              ),
              if (topDriver['avgRating'] != null)
                Row(
                  children: [
                    const Icon(Icons.star_rounded,
                        color: AppColors.warning, size: 16),
                    const SizedBox(width: 3),
                    Text(
                      (topDriver['avgRating'] as num).toStringAsFixed(1),
                      style: ClientText.bodyStrong.copyWith(color: t.text),
                    ),
                  ],
                ),
            ],
          ),
        ),
      const SizedBox(height: 16),

      // ── Top destinataires ────────────────────────────────────────────────
      Text('Destinataires les plus fréquents',
          style: ClientText.bodyStrong.copyWith(color: t.text)),
      const SizedBox(height: 10),
      if (topDestinations.isEmpty)
        _buildEmpty('Aucune livraison sur cette période')
      else
        Container(
          decoration: BoxDecoration(
            color: t.cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: t.border),
          ),
          child: Column(
            children: [
              for (var i = 0; i < topDestinations.length; i++) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (topDestinations[i]['receiverName']
                                          as String?) ??
                                  (topDestinations[i]['address'] as String? ??
                                      '—'),
                              style: ClientText.bodyStrong.copyWith(color: AppColors.textDark)
                                  .copyWith(color: t.text),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              topDestinations[i]['address'] as String? ?? '',
                              style: ClientText.label.copyWith(color: AppColors.textDark)
                                  .copyWith(color: t.muted),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${topDestinations[i]['count']}×',
                          style: ClientText.label.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (i < topDestinations.length - 1)
                  Divider(height: 1, color: t.border),
              ],
            ],
          ),
        ),
    ];
  }

  Widget _buildChart(List<Map<String, dynamic>> breakdown) {
    final maxAmt = breakdown
        .map((b) => (b['amount'] as num?)?.toDouble() ?? 0.0)
        .fold(0.0, (a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Évolution',
            style: ClientText.bodyStrong.copyWith(color: t.text),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: breakdown.asMap().entries.map((entry) {
                final b = entry.value;
                final amount = (b['amount'] as num?)?.toDouble() ?? 0.0;
                final label = b['label'] as String? ?? '';
                final count = (b['count'] as num?)?.toInt() ?? 0;
                final ratio = maxAmt > 0 ? amount / maxAmt : 0.0;
                final barH = ratio == 0 ? 4.0 : 8.0 + ratio * 72.0;
                final isLast = entry.key == breakdown.length - 1;

                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: isLast ? 0 : 6),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (count > 0) ...[
                          Text(
                            formatFcfa(amount.toInt()),
                            style: ClientText.micro.copyWith(
                              color: AppColors.primary,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                        ] else
                          const SizedBox(height: 18),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeOut,
                          height: barH,
                          decoration: BoxDecoration(
                            color: count > 0
                                ? AppColors.primary.withValues(
                                    alpha: 0.25 + 0.75 * ratio,
                                  )
                                : t.border,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          label,
                          style: ClientText.micro.copyWith(
                            color: t.muted,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(String msg) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: t.cardBg,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: t.border),
    ),
    child: Column(
      children: [
        Icon(Icons.receipt_long_outlined, color: t.muted, size: 36),
        const SizedBox(height: 10),
        Text(msg, style: ClientText.subtitle.copyWith(color: t.text)),
      ],
    ),
  );
}

// ── Toggle Ventes / Livraisons ──────────────────────────────────────────────

class _FinanceToggle extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final _T t;
  const _FinanceToggle({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
    required this.t,
  });

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: active ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: active ? Colors.white : t.muted),
            const SizedBox(width: 6),
            Text(
              label,
              style: ClientText.label.copyWith(
                color: active ? Colors.white : t.muted,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ── Mini-stat dans la card résumé ────────────────────────────────────────────

class _MiniStat extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  final _T t;
  const _MiniStat({
    required this.value,
    required this.label,
    required this.color,
    required this.t,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: ClientText.title.copyWith(color: color)),
        const SizedBox(height: 2),
        Text(label, style: ClientText.label.copyWith(color: t.muted)),
      ],
    ),
  );
}

// ── Carte indicateur pilotage (délai moyen, taux d'annulation...) ───────────
class _InsightCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final _T t;
  const _InsightCard({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    required this.t,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: t.cardBg,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: t.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.primary, size: 18),
        const SizedBox(height: 10),
        Text(value,
            style: ClientText.title.copyWith(color: valueColor ?? t.text)),
        const SizedBox(height: 2),
        Text(label, style: ClientText.label.copyWith(color: t.muted)),
      ],
    ),
  );
}

// ── Ligne vente (avec articles) ─────────────────────────────────────────────

class _SaleRow extends StatelessWidget {
  final Map<String, dynamic> order;
  final _T t;
  const _SaleRow({required this.order, required this.t});

  @override
  Widget build(BuildContext context) {
    final items = (order['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final desc = order['description'] as String? ?? '';
    final date = _formatDateTime(order['createdAt'] as String?);
    final receiver = order['receiverName'] as String?;
    final address = _shortAddress(order['deliveryAddress'] as String? ?? '');
    final payMode = order['paymentMode'] as String?;

    int saleTotal = 0;
    for (final item in items) {
      saleTotal +=
          ((item['price'] as num?)?.toInt() ?? 0) *
          ((item['quantity'] as num?)?.toInt() ?? 1);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.successLight.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.shopping_bag_outlined,
                  color: AppColors.successLight,
                  size: 17,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      receiver ?? address,
                      style: ClientText.bodyStrong.copyWith(color: t.text),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      date,
                      style: ClientText.label.copyWith(color: t.muted),
                    ),
                  ],
                ),
              ),
              if (saleTotal > 0)
                Text(
                  formatFcfa(saleTotal),
                  style: ClientText.subtitle.copyWith(
                    color: AppColors.successLight,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),

          // Articles
          if (items.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: t.cardBg2,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: items.map((item) {
                  final name = item['name'] as String? ?? '—';
                  final qty = (item['quantity'] as num?)?.toInt() ?? 1;
                  final price = (item['price'] as num?)?.toInt();
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Text(
                          '$name',
                          style: ClientText.label.copyWith(color: t.text),
                        ),
                        Text(
                          '  × $qty',
                          style: ClientText.label.copyWith(color: t.muted),
                        ),
                        const Spacer(),
                        if (price != null)
                          Text(
                            formatFcfa(price * qty),
                            style: ClientText.label.copyWith(color: t.text),
                          ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ] else if (desc.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              desc,
              style: ClientText.label.copyWith(color: t.muted),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],

          // Paiement
          if (payMode != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  payMode == 'merchant'
                      ? Icons.storefront_outlined
                      : Icons.payments_outlined,
                  color: t.muted,
                  size: 13,
                ),
                const SizedBox(width: 4),
                Text(
                  payMode == 'merchant'
                      ? 'Payé par vous'
                      : 'Payé à la livraison',
                  style: ClientText.label.copyWith(color: t.muted),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ── Ligne livraison ─────────────────────────────────────────────────────────

class _DeliveryRow extends StatelessWidget {
  final Map<String, dynamic> order;
  final _T t;
  const _DeliveryRow({required this.order, required this.t});

  @override
  Widget build(BuildContext context) {
    final address = _shortAddress(order['deliveryAddress'] as String? ?? '—');
    final amount = (order['price'] as num?)?.toInt() ?? 0;
    final driver = order['driver'] as Map<String, dynamic>?;
    final driverName = driver?['name'] as String?;
    final date = _formatDateTime(order['createdAt'] as String?);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.two_wheeler,
              color: AppColors.primary,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  address,
                  style: ClientText.bodyStrong.copyWith(color: t.text),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      date,
                      style: ClientText.label.copyWith(color: t.muted),
                    ),
                    if (driverName != null && driverName.isNotEmpty) ...[
                      Text(
                        '  ·  ',
                        style: ClientText.label.copyWith(color: t.muted),
                      ),
                      Expanded(
                        child: Text(
                          driverName,
                          style: ClientText.label.copyWith(color: t.muted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            formatFcfa(amount),
            style: ClientText.bodyStrong.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
