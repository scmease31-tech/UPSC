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
/// SignupScreen — Registration form with glassmorphic card.
/// ──────────────────────────────────────────────────────────────────────────────
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> with SingleTickerProviderStateMixin {
  final _nameCtrl = TextEditingController();
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
    _nameCtrl.dispose();
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
          Container(
            width: 100, height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: AppTheme.accentViolet.withValues(alpha: 0.2), blurRadius: 25, spreadRadius: 5),
              ],
            ),
            child: ClipOval(
              child: Image.asset(
                'assets/images/logo.png',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  decoration: BoxDecoration(gradient: AppTheme.primaryGradient),
                  child: const Icon(Icons.person_add_rounded, size: 40, color: Colors.white),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text('Create Account', style: GoogleFonts.plusJakartaSans(fontSize: 26, fontWeight: FontWeight.w800, color: AppTheme.textP(context))),
          const SizedBox(height: 4),
          Text('Start your UPSC journey', style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textS(context))),
          const SizedBox(height: 28),
        ],

        kIsWeb
            ? _buildFormBody(auth)
            : GlassCard(
                padding: const EdgeInsets.all(24),
                child: _buildFormBody(auth),
              ),

        const SizedBox(height: 20),

        // Google
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton.icon(
            onPressed: auth.isLoading ? null : _googleSignIn,
            icon: SvgPicture.asset('assets/icons/google_logo.svg', width: 22, height: 22),
            label: Text('Sign up with Google', style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.textP(context),
              side: BorderSide(color: AppTheme.textS(context).withValues(alpha: 0.2)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),

        const SizedBox(height: 20),

        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Already have an account? ', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textS(context))),
            GestureDetector(
              onTap: () => Navigator.pushReplacementNamed(context, '/login'),
              child: Text('Sign In', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.primaryColor)),
            ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );

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
          if (kIsWeb) ...[
            Text('Create Account', style: GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.textP(context))),
            const SizedBox(height: 4),
            Text('Start your UPSC journey', style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textS(context))),
            const SizedBox(height: 24),
          ],
          TextFormField(
            controller: _nameCtrl,
            decoration: _inputDec('Full Name', Icons.person_rounded),
            validator: (v) => v != null && v.trim().isNotEmpty ? null : 'Enter your name',
          ),
          const SizedBox(height: 14),
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
            height: 50,
            child: ElevatedButton(
              onPressed: auth.isLoading ? null : _signUp,
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
                        const Icon(Icons.person_add_rounded, size: 20),
                        const SizedBox(width: 8),
                        Text('Create Account', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700)),
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

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;
    HapticFeedback.mediumImpact();
    setState(() => _error = null);
    final err = await context.read<AuthProvider>().signUp(_nameCtrl.text, _emailCtrl.text, _passwordCtrl.text);
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
