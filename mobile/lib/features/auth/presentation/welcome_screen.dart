import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:londonsnaps/features/auth/providers/auth_provider.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with TickerProviderStateMixin {
  late final AnimationController _glowController;
  late final AnimationController _fadeController;
  late final Animation<double> _glowAnimation;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _buttonSlide;

  final _authProvider = AuthProvider();
  bool _isCheckingAuth = true;
  bool _isAuthenticated = false;

  @override
  void initState() {
    super.initState();

    // Pulsing glow for the button
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _glowAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    // Fade-in entrance animation
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );

    _buttonSlide = Tween<double>(begin: 40.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _fadeController,
        curve: const Interval(0.4, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    _fadeController.forward();

    _checkAuth();
  }

  Future<void> _checkAuth() async {
    await _authProvider.checkAuthState();
    if (mounted) {
      setState(() {
        _isAuthenticated = _authProvider.isAuthenticated;
        _isCheckingAuth = false;
      });
    }
  }

  @override
  void dispose() {
    _glowController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  void _goToNext() {
    HapticFeedback.mediumImpact();
    if (_isAuthenticated) {
      context.go('/camera');
    } else {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Full-screen background image
          Image.asset(
            'assets/images/welcome_bg.jpg',
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
          ),

          // Subtle gradient overlay at bottom for readability
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.15),
                    Colors.black.withValues(alpha: 0.5),
                  ],
                  stops: const [0.0, 0.5, 0.75, 1.0],
                ),
              ),
            ),
          ),

          // Button positioned at bottom
          Positioned(
            left: 40,
            right: 40,
            bottom: MediaQuery.of(context).padding.bottom + 80,
            child: AnimatedBuilder(
              animation: Listenable.merge([_fadeAnimation, _glowAnimation]),
              builder: (context, child) {
                return Opacity(
                  opacity: _fadeAnimation.value,
                  child: Transform.translate(
                    offset: Offset(0, _buttonSlide.value),
                    child: _buildGlowButton(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlowButton() {
    final glowOpacity = _glowAnimation.value;

    return GestureDetector(
      onTap: _isCheckingAuth ? null : _goToNext,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            // Outer premium glow — Snapchat yellow
            BoxShadow(
              color: const Color(0xFFFFFC00).withValues(alpha: 0.35 * glowOpacity),
              blurRadius: 32,
              spreadRadius: 2,
            ),
            // Inner tighter glow
            BoxShadow(
              color: const Color(0xFFFFFC00).withValues(alpha: 0.55 * glowOpacity),
              blurRadius: 14,
              spreadRadius: 0,
            ),
          ],
        ),
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            gradient: const LinearGradient(
              colors: [
                Color(0xFFFFFC00), // Snapchat yellow
                Color(0xFFFFD600), // Slightly deeper gold
              ],
            ),
          ),
          child: Center(
            child: _isCheckingAuth
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.black,
                    ),
                  )
                : const Text(
                    "Let's Go!",
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
