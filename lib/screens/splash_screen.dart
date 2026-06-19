import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../config/theme.dart';
import '../services/notification_service.dart';

/// ──────────────────────────────────────────────────────────────────────────────
/// Redesigned Splash Screen — Pastel gradient background with glassmorphic
/// logo container, floating orbs, staggered animations, and shimmer text.
/// ──────────────────────────────────────────────────────────────────────────────
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _logoCtrl;
  late AnimationController _contentCtrl;
  late AnimationController _shimmerCtrl;
  late AnimationController _orbCtrl;

  late Animation<double> _logoScale;
  late Animation<double> _logoFade;
  late Animation<double> _titleFade;
  late Animation<Offset> _titleSlide;
  late Animation<double> _taglineFade;
  late Animation<double> _loaderFade;
  late Animation<double> _ringRotation;
  late Animation<double> _ringScale;
  late Animation<double> _orbPulse;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));

    _logoCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
    _logoScale = Tween<double>(begin: 0.2, end: 1.0).animate(
      CurvedAnimation(parent: _logoCtrl, curve: const Interval(0.0, 0.7, curve: Curves.elasticOut)),
    );
    _logoFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _logoCtrl, curve: const Interval(0.0, 0.35, curve: Curves.easeOut)),
    );
    _ringRotation = Tween<double>(begin: 0, end: 2 * pi).animate(
      CurvedAnimation(parent: _logoCtrl, curve: Curves.easeInOut),
    );
    _ringScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _logoCtrl, curve: const Interval(0.1, 0.55, curve: Curves.easeOutBack)),
    );

    _contentCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));
    _titleFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _contentCtrl, curve: const Interval(0.0, 0.5, curve: Curves.easeOut)),
    );
    _titleSlide = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
      CurvedAnimation(parent: _contentCtrl, curve: const Interval(0.0, 0.6, curve: Curves.easeOutCubic)),
    );
    _taglineFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _contentCtrl, curve: const Interval(0.3, 0.7, curve: Curves.easeOut)),
    );
    _loaderFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _contentCtrl, curve: const Interval(0.5, 1.0, curve: Curves.easeOut)),
    );

    _shimmerCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))..repeat();

    _orbCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 3000))..repeat(reverse: true);
    _orbPulse = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _orbCtrl, curve: Curves.easeInOut),
    );

    _logoCtrl.forward();
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _contentCtrl.forward();
    });

    Future.delayed(const Duration(milliseconds: 1800), () async {
      if (!mounted) return;
      try {
        final user = await FirebaseAuth.instance.authStateChanges().first;
        if (!mounted) return;
        if (user != null) {
          Navigator.pushReplacementNamed(context, '/main');
          Future.delayed(const Duration(milliseconds: 500), () {
            NotificationService.processPendingPayload();
          });
        } else {
          Navigator.pushReplacementNamed(context, '/onboarding');
        }
      } catch (_) {
        if (mounted) Navigator.pushReplacementNamed(context, '/onboarding');
      }
    });
  }

  @override
  void dispose() {
    _logoCtrl.dispose();
    _contentCtrl.dispose();
    _shimmerCtrl.dispose();
    _orbCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(gradient: AppTheme.screenGradient),
        child: Stack(
          children: [
            // Animated floating orbs with pulse
            ..._buildFloatingOrbs(size),

            // Frosted glass overlay area
            Positioned(
              top: size.height * 0.15,
              left: 40,
              right: 40,
              child: AnimatedBuilder(
                animation: _logoCtrl,
                builder: (context, child) => Opacity(
                  opacity: _logoFade.value * 0.3,
                  child: child,
                ),
                child: RepaintBoundary(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(40),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      height: size.height * 0.45,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(40),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                      ),
                    ),
                  ),
                ),
              ),
              ),
            ),

            // Main content
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Animated logo with glowing teal ring
                  AnimatedBuilder(
                    animation: Listenable.merge([_logoCtrl, _orbCtrl]),
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _logoScale.value,
                        child: Opacity(
                          opacity: _logoFade.value,
                          child: SizedBox(
                            width: 180,
                            height: 180,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                // Outer glow pulse
                                Transform.scale(
                                  scale: _orbPulse.value,
                                  child: Container(
                                    width: 175,
                                    height: 175,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppTheme.primaryColor.withValues(alpha: 0.15),
                                          blurRadius: 40,
                                          spreadRadius: 10,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                // Rotating ring
                                Transform.rotate(
                                  angle: _ringRotation.value,
                                  child: Transform.scale(
                                    scale: _ringScale.value,
                                    child: Container(
                                      width: 160,
                                      height: 160,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: AppTheme.primaryColor.withValues(alpha: 0.35),
                                          width: 2.5,
                                        ),
                                      ),
                                      child: Stack(
                                        children: [
                                          Positioned(
                                            top: 0, left: 75,
                                            child: Container(
                                              width: 10, height: 10,
                                              decoration: const BoxDecoration(
                                                color: AppTheme.primaryColor,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                          ),
                                          Positioned(
                                            bottom: 20, right: 5,
                                            child: Container(
                                              width: 6, height: 6,
                                              decoration: BoxDecoration(
                                                color: AppTheme.primaryLight.withValues(alpha: 0.7),
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                // Inner frosted glass circle
                                RepaintBoundary(
                                  child: ClipOval(
                                    child: BackdropFilter(
                                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                                      child: Container(
                                      width: 120,
                                      height: 120,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.white.withValues(alpha: 0.4),
                                        border: Border.all(
                                          color: Colors.white.withValues(alpha: 0.6),
                                          width: 1.5,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppTheme.primaryColor.withValues(alpha: 0.2),
                                            blurRadius: 30,
                                            spreadRadius: 5,
                                          ),
                                        ],
                                      ),
                                    ),
                                    ),
                                  ),
                                ),
                                // Logo image
                                ClipOval(
                                  child: Image.asset(
                                    'assets/images/logo.webp',
                                    width: 96,
                                    height: 96,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      width: 96, height: 96,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: AppTheme.primaryGradient,
                                        boxShadow: AppTheme.glowShadow,
                                      ),
                                      child: const Icon(Icons.auto_stories_rounded, size: 44, color: Colors.white),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 44),

                  // Title with slide
                  SlideTransition(
                    position: _titleSlide,
                    child: FadeTransition(
                      opacity: _titleFade,
                      child: Text(
                        'UPSC Daily Edge',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.primaryDark,
                          letterSpacing: -1.2,
                          height: 1,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Shimmer tagline
                  FadeTransition(
                    opacity: _taglineFade,
                    child: AnimatedBuilder(
                      animation: _shimmerCtrl,
                      builder: (context, child) {
                        return ShaderMask(
                          shaderCallback: (Rect bounds) {
                            return LinearGradient(
                              colors: [
                                AppTheme.primaryColor.withValues(alpha: 0.4),
                                AppTheme.primaryColor,
                                AppTheme.accentViolet,
                                AppTheme.primaryColor.withValues(alpha: 0.4),
                              ],
                              stops: [
                                (_shimmerCtrl.value - 0.3).clamp(0.0, 1.0),
                                _shimmerCtrl.value.clamp(0.0, 1.0),
                                (_shimmerCtrl.value + 0.15).clamp(0.0, 1.0),
                                (_shimmerCtrl.value + 0.3).clamp(0.0, 1.0),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ).createShader(bounds);
                          },
                          child: Text(
                            'Your Daily UPSC Companion',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                              letterSpacing: 2.5,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

            // Bottom loader section
            Positioned(
              bottom: 80,
              left: 0, right: 0,
              child: FadeTransition(
                opacity: _loaderFade,
                child: Column(
                  children: [
                    SizedBox(
                      width: 200,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.12),
                          valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
                          minHeight: 3,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Preparing your study dashboard...',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppTheme.primaryDark.withValues(alpha: 0.5),
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Version
            Positioned(
              bottom: 30,
              left: 0, right: 0,
              child: FadeTransition(
                opacity: _loaderFade,
                child: Text(
                  'v1.0.0',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: AppTheme.primaryDark.withValues(alpha: 0.25),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildFloatingOrbs(Size size) {
    return [
      // Top-right teal orb
      AnimatedBuilder(
        animation: _orbPulse,
        builder: (context, child) => Positioned(
          top: -50,
          right: -30,
          child: Transform.scale(
            scale: _orbPulse.value,
            child: Container(
              width: 200, height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppTheme.primaryColor.withValues(alpha: 0.15),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      // Bottom-left violet orb
      AnimatedBuilder(
        animation: _orbPulse,
        builder: (context, child) => Positioned(
          bottom: 80,
          left: -70,
          child: Transform.scale(
            scale: 2.2 - _orbPulse.value,
            child: Container(
              width: 260, height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppTheme.accentViolet.withValues(alpha: 0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      // Mid-right pink orb
      AnimatedBuilder(
        animation: _orbPulse,
        builder: (context, child) => Positioned(
          top: size.height * 0.35,
          right: -40,
          child: Transform.scale(
            scale: _orbPulse.value * 0.9,
            child: Container(
              width: 160, height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFF5C6E0).withValues(alpha: 0.25),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ];
  }
}
