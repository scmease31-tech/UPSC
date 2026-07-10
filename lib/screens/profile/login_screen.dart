import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/glass_widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// ──────────────────────────────────────────────────────────────────────────────
/// LoginScreen — Glassmorphic auth with Google + email/password sign-in.
/// ──────────────────────────────────────────────────────────────────────────────
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscure = true;
  String? _error;
  late AnimationController _fadeCtrl;
  late CurvedAnimation _fadeCurve;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))..forward();
    _fadeCurve = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _fadeCurve.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    final formContent = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (!kIsWeb) ...[
          // App logo (mobile only — web has branding panel)
          Container(
            width: 120, height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: AppTheme.primaryColor.withValues(alpha: 0.2), blurRadius: 30, spreadRadius: 5),
              ],
            ),
            child: ClipOval(
              child: Image.asset(
                'assets/images/logo.png',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  decoration: BoxDecoration(gradient: AppTheme.primaryGradient),
                  child: const Icon(Icons.auto_stories_rounded, size: 48, color: Colors.white),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('UPSC Daily Edge', style: GoogleFonts.plusJakartaSans(fontSize: 28, fontWeight: FontWeight.w800, color: AppTheme.textP(context))),
          const SizedBox(height: 4),
          Text('Your Daily UPSC Companion', style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textS(context))),
          const SizedBox(height: 36),
        ],

        // Form card
        kIsWeb
            ? _buildFormBody(auth)
            : GlassCard(padding: const EdgeInsets.all(24), child: _buildFormBody(auth)),

        const SizedBox(height: 20),

        // Divider
        Row(
          children: [
            Expanded(child: Divider(color: AppTheme.textS(context).withValues(alpha: 0.2))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('or', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textS(context))),
            ),
            Expanded(child: Divider(color: AppTheme.textS(context).withValues(alpha: 0.2))),
          ],
        ),

        const SizedBox(height: 20),

        // Google sign in
        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton.icon(
            onPressed: auth.isLoading ? null : _googleSignIn,
            icon: SvgPicture.asset('assets/icons/google_logo.svg', width: 22, height: 22),
            label: Text('Continue with Google', style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.textP(context),
              side: BorderSide(color: AppTheme.divider(context)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),

        const SizedBox(height: 20),

        // Sign up link
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("Don't have an account? ", style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textS(context))),
            GestureDetector(
              onTap: () => Navigator.pushReplacementNamed(context, '/signup'),
              child: Text('Sign Up', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.primaryColor)),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Skip
        TextButton(
          onPressed: () => Navigator.pushReplacementNamed(context, '/main'),
          child: Text('Continue without account', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textS(context))),
        ),
      ],
    );

    // On web, content is already wrapped by WebAuthScaffold
    if (kIsWeb) return formContent;

    return GradientScaffold(
      child: SafeArea(
        child: FadeTransition(
          opacity: _fadeCurve,
          child: Center(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: formContent,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormBody(AuthProvider auth) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Welcome Back', style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w700, color: AppTheme.textP(context))),
          const SizedBox(height: 20),
          TextFormField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: _inputDec('Email', Icons.email_rounded),
            validator: (v) => v != null && v.contains('@') ? null : 'Enter a valid email',
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _passwordCtrl,
            obscureText: _obscure,
            decoration: _inputDec('Password', Icons.lock_rounded).copyWith(
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 20),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            validator: (v) => v != null && v.length >= 6 ? null : 'At least 6 characters',
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: GoogleFonts.inter(fontSize: 12, color: AppTheme.errorRed), textAlign: TextAlign.center),
          ],
          const SizedBox(height: 20),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: auth.isLoading ? null : _signIn,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: auth.isLoading
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.login_rounded, size: 20),
                        const SizedBox(width: 8),
                        Text('Sign In', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700)),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDec(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      filled: true,
      fillColor: AppTheme.card(context).withValues(alpha: 0.6),
      labelStyle: GoogleFonts.inter(fontSize: 14),
    );
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    HapticFeedback.mediumImpact();
    setState(() => _error = null);
    final err = await context.read<AuthProvider>().signIn(_emailCtrl.text, _passwordCtrl.text);
    if (err != null) {
      HapticFeedback.heavyImpact();
      setState(() => _error = err);
    } else if (mounted) {
      Navigator.pushReplacementNamed(context, '/main');
    }
  }

  Future<void> _googleSignIn() async {
    HapticFeedback.lightImpact();
    setState(() => _error = null);
    final err = await context.read<AuthProvider>().signInWithGoogle();
    if (err != null) {
      HapticFeedback.heavyImpact();
      setState(() => _error = err);
    } else if (mounted) {
      Navigator.pushReplacementNamed(context, '/main');
    }
  }
}
