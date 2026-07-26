import 'package:flutter/material.dart';
import '../../../core/storage/auth_storage.dart';
import '../../../core/router/app_startup_notifier.dart';
import '../../../core/theme/app_theme.dart';

// ── Données des slides ────────────────────────────────────────────────────────
class _Slide {
  final IconData    icon;
  final String      title;
  final String      subtitle;
  final Color       iconColor;
  final List<Color> gradientColors;

  const _Slide({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.iconColor,
    required this.gradientColors,
  });
}

const _slides = [
  _Slide(
    icon: Icons.flash_on_rounded,
    title: 'Livraison express à Dakar',
    subtitle: 'Programmez votre course en quelques secondes. Votre colis est récupéré et livré rapidement à travers Dakar.',
    iconColor: Color(0xFF00E5FF),
    gradientColors: [Color(0xFF00D4FF), Color(0xFF0CB8DE), Color(0xFF0260A8), Color(0xFF011840)],
  ),
  _Slide(
    icon: Icons.location_on_rounded,
    title: 'Suivi en temps réel',
    subtitle: 'Regardez votre livreur se déplacer sur la carte. Fini l\'attente interminable, moins de stress.',
    iconColor: Color(0xFF40F0C0),
    gradientColors: [Color(0xFF00C9C8), Color(0xFF0AADCA), Color(0xFF045EA0), Color(0xFF011840)],
  ),
  _Slide(
    icon: Icons.verified_rounded,
    title: 'Livreurs vérifiés',
    subtitle: 'Chaque livreur est sélectionné et évalué par notre équipe. Vos colis sont entre de bonnes mains.',
    iconColor: Color(0xFF80EAFF),
    gradientColors: [Color(0xFF0CB8DE), Color(0xFF0671BA), Color(0xFF04317C), Color(0xFF020822)],
  ),
  _Slide(
    icon: Icons.support_agent_rounded,
    title: 'Service client',
    subtitle: 'Une question, un problème ou une réclamation ? Notre équipe est disponible et réactive 24h/24 et 7j/7 pour vous accompagner.',
    iconColor: Color(0xFFB0D8FF),
    gradientColors: [Color(0xFF0A6BAD), Color(0xFF084E96), Color(0xFF032878), Color(0xFF010820)],
  ),
];

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {

  final _pageCtrl = PageController();
  int _page = 0;

  late AnimationController _contentCtrl;
  late Animation<double>   _contentFade;
  late Animation<Offset>   _contentSlide;

  @override
  void initState() {
    super.initState();
    _contentCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _contentFade = CurvedAnimation(parent: _contentCtrl, curve: Curves.easeOut);
    _contentSlide = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _contentCtrl, curve: Curves.easeOutCubic));

    _contentCtrl.forward();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  void _goToPage(int index) {
    _pageCtrl.animateToPage(
      index,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeInOutCubic,
    );
  }

  void _onPageChanged(int index) {
    setState(() => _page = index);
    _contentCtrl.reset();
    _contentCtrl.forward();
  }

  Future<void> _finish() async {
    await AuthStorage.setOnboardingSeen();
    appStartupNotifier.markOnboardingSeen();
  }

  @override
  Widget build(BuildContext context) {
    final slide       = _slides[_page];
    final isLast      = _page == _slides.length - 1;
    final size        = MediaQuery.of(context).size;
    final isLandscape = size.width > size.height;
    final isTablet    = size.shortestSide > 600;

    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: slide.gradientColors,
            stops: const [0.0, 0.35, 0.70, 1.0],
          ),
        ),
        child: SafeArea(
          child: isLandscape
              ? _buildLandscape(isLast, isTablet)
              : _buildPortrait(isLast, isTablet),
        ),
      ),
    );
  }

  // ── Portrait : icône en haut, texte en bas ────────────────────────────────
  Widget _buildPortrait(bool isLast, bool isTablet) {
    return Column(
      children: [
        _passerButton(isLast),
        Expanded(
          child: PageView.builder(
            controller: _pageCtrl,
            onPageChanged: _onPageChanged,
            itemCount: _slides.length,
            itemBuilder: (_, i) => _SlidePage(
              slide: _slides[i],
              contentFade: _contentFade,
              contentSlide: _contentSlide,
              isLandscape: false,
              isTablet: isTablet,
            ),
          ),
        ),
        _bottomControls(isLast, isTablet: isTablet, isLandscape: false),
      ],
    );
  }

  // ── Landscape : icône à gauche, texte + boutons à droite ─────────────────
  Widget _buildLandscape(bool isLast, bool isTablet) {
    final hPad = isTablet ? 48.0 : 32.0;

    return Row(
      children: [
        // Gauche : PageView (icône seule, swipeable)
        Expanded(
          flex: 45,
          child: PageView.builder(
            controller: _pageCtrl,
            onPageChanged: _onPageChanged,
            itemCount: _slides.length,
            itemBuilder: (_, i) => _SlidePage(
              slide: _slides[i],
              contentFade: _contentFade,
              contentSlide: _contentSlide,
              isLandscape: true,
              isTablet: isTablet,
            ),
          ),
        ),
        // Droite : texte animé + dots + bouton
        Expanded(
          flex: 55,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _passerButton(isLast),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: hPad),
                  child: _SlideText(
                    slide: _slides[_page],
                    contentFade: _contentFade,
                    contentSlide: _contentSlide,
                    isTablet: isTablet,
                  ),
                ),
              ),
              _bottomControls(isLast, isTablet: isTablet, isLandscape: true),
            ],
          ),
        ),
      ],
    );
  }

  // ── Bouton "Passer" ───────────────────────────────────────────────────────
  Widget _passerButton(bool isLast) {
    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.only(top: 12, right: 20),
        child: AnimatedOpacity(
          opacity: isLast ? 0.0 : 1.0,
          duration: const Duration(milliseconds: 300),
          child: TextButton(
            onPressed: isLast ? null : _finish,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white60,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: const Text('Passer', style: TextStyle(fontSize: 14)),
          ),
        ),
      ),
    );
  }

  // ── Dots + Bouton Suivant/Commencer ───────────────────────────────────────
  Widget _bottomControls(bool isLast, {required bool isTablet, required bool isLandscape}) {
    final hPad     = isTablet ? 48.0 : 28.0;
    final vPad     = isLandscape ? 12.0 : 32.0;
    final btnH     = isLandscape ? 44.0 : 56.0;
    final btnFontS = isTablet ? 18.0 : 16.0;
    final gap      = isLandscape ? 12.0 : 32.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, 0, hPad, vPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Dots
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_slides.length, (i) {
              final active = i == _page;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: active ? 28 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: active
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.30),
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),
          SizedBox(height: gap),
          // Bouton
          SizedBox(
            width: double.infinity,
            height: btnH,
            child: ElevatedButton(
              onPressed: isLast ? _finish : () => _goToPage(_page + 1),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primaryDark,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
                shadowColor: Colors.transparent,
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Text(
                  isLast ? 'Commencer' : 'Suivant',
                  key: ValueKey(isLast),
                  style: TextStyle(
                    fontSize: btnFontS,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Slide : icône (+ texte en portrait) ──────────────────────────────────────
class _SlidePage extends StatelessWidget {
  final _Slide            slide;
  final Animation<double> contentFade;
  final Animation<Offset> contentSlide;
  final bool              isLandscape;
  final bool              isTablet;

  const _SlidePage({
    required this.slide,
    required this.contentFade,
    required this.contentSlide,
    required this.isLandscape,
    required this.isTablet,
  });

  Widget _icon() {
    final circleSize = isLandscape
        ? (isTablet ? 180.0 : 130.0)
        : (isTablet ? 240.0 : 180.0);
    final iconSize = isLandscape
        ? (isTablet ? 90.0 : 64.0)
        : (isTablet ? 120.0 : 80.0);

    return Container(
      width: circleSize, height: circleSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.22),
            Colors.white.withValues(alpha: 0.06),
          ],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.30),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: slide.iconColor.withValues(alpha: 0.25),
            blurRadius: 60,
            spreadRadius: 10,
          ),
        ],
      ),
      child: Icon(slide.icon, size: iconSize, color: slide.iconColor),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLandscape) {
      // En landscape : icône seule, centrée (le texte est dans la colonne de droite)
      return Center(child: _icon());
    }

    // En portrait : icône + texte en colonne
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isTablet ? 48 : 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _icon(),
          SizedBox(height: isTablet ? 64 : 52),
          _SlideText(
            slide: slide,
            contentFade: contentFade,
            contentSlide: contentSlide,
            isTablet: isTablet,
          ),
        ],
      ),
    );
  }
}

// ── Texte animé (titre + sous-titre) ─────────────────────────────────────────
class _SlideText extends StatelessWidget {
  final _Slide            slide;
  final Animation<double> contentFade;
  final Animation<Offset> contentSlide;
  final bool              isTablet;

  const _SlideText({
    required this.slide,
    required this.contentFade,
    required this.contentSlide,
    required this.isTablet,
  });

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: contentFade,
      child: SlideTransition(
        position: contentSlide,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              slide.title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: isTablet ? 36 : 28,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                height: 1.1,
              ),
            ),
            SizedBox(height: isTablet ? 20 : 16),
            Text(
              slide.subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: isTablet ? 18 : 15,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
