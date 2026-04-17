import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/storage/auth_storage.dart';

// ── Données des slides ────────────────────────────────────────────────────────
class _Slide {
  final IconData icon;
  final String   title;
  final String   subtitle;
  final Color    iconColor;
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
    title: 'Livraison express',
    subtitle: 'Commandez en quelques secondes.\nVotre colis récupéré et livré rapidement au Sénégal.',
    iconColor: Color(0xFF00E5FF),
    gradientColors: [Color(0xFF00D4FF), Color(0xFF0CB8DE), Color(0xFF0260A8), Color(0xFF011840)],
  ),
  _Slide(
    icon: Icons.location_on_rounded,
    title: 'Suivi en temps réel',
    subtitle: 'Suivez votre livreur en direct sur la carte.\nPlus d\'appels, moins de stress.',
    iconColor: Color(0xFF40F0C0),
    gradientColors: [Color(0xFF00C9C8), Color(0xFF0AADCA), Color(0xFF045EA0), Color(0xFF011840)],
  ),
  _Slide(
    icon: Icons.verified_rounded,
    title: 'Livreurs vérifiés',
    subtitle: 'Chaque livreur est contrôlé et noté.\nVotre sécurité, notre priorité.',
    iconColor: Color(0xFF80EAFF),
    gradientColors: [Color(0xFF0CB8DE), Color(0xFF0671BA), Color(0xFF04317C), Color(0xFF020822)],
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

  // Animation pour le contenu de chaque slide (fade + slide-up)
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
    if (mounted) context.go('/phone');
  }

  @override
  Widget build(BuildContext context) {
    final slide      = _slides[_page];
    final isLast     = _page == _slides.length - 1;

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
          child: Column(
            children: [

              // ── Bouton Passer ──
              Align(
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
              ),

              // ── Pages ──
              Expanded(
                child: PageView.builder(
                  controller: _pageCtrl,
                  onPageChanged: _onPageChanged,
                  itemCount: _slides.length,
                  itemBuilder: (_, i) => _SlidePage(
                    slide: _slides[i],
                    contentFade: _contentFade,
                    contentSlide: _contentSlide,
                    active: i == _page,
                  ),
                ),
              ),

              // ── Dots + Bouton ──
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 32),
                child: Column(
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

                    const SizedBox(height: 32),

                    // Bouton Suivant / Commencer
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: isLast
                            ? _finish
                            : () => _goToPage(_page + 1),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF04317C),
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
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Contenu d'un slide ────────────────────────────────────────────────────────
class _SlidePage extends StatelessWidget {
  final _Slide               slide;
  final Animation<double>    contentFade;
  final Animation<Offset>    contentSlide;
  final bool                 active;

  const _SlidePage({
    required this.slide,
    required this.contentFade,
    required this.contentSlide,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [

          // ── Illustration glassmorphism ──
          Container(
            width: 180, height: 180,
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
            child: Icon(slide.icon, size: 80, color: slide.iconColor),
          ),

          const SizedBox(height: 52),

          // ── Texte animé ──
          FadeTransition(
            opacity: contentFade,
            child: SlideTransition(
              position: contentSlide,
              child: Column(
                children: [
                  Text(
                    slide.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    slide.subtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontSize: 15,
                      height: 1.6,
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
}
