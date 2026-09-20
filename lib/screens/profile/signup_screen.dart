import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/glass_widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../design_system/frosted_scholar.dart';

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
                errorBuilder: (_, __, ___) => const DecoratedBox(
                  decoration: BoxDecoration(gradient: AppTheme.primaryGradient),
                  child: Icon(Icons.person_add_rounded, size: 40, color: Colors.white),
                ),
              ),
            ),
          ),
          const SizedBox(height: FsSpace.xs),
          Text('Create Account', style: FsType.display(context)),
          const SizedBox(height: FsSpace.xxs),
          Text('Start your UPSC journey', style: FsType.caption(context)),
          const SizedBox(height: FsSpace.xxl),
        ],

        kIsWeb
            ? _buildFormBody(auth)
            : GlassCard(
                padding: FsSpacing.cardPadding,
                child: _buildFormBody(auth),
              ),

        const SizedBox(height: FsSpace.xl),

        // Google
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton.icon(
            onPressed: auth.isLoading ? null : _googleSignIn,
            icon: SvgPicture.asset('assets/icons/google_logo.svg', width: 22, height: 22),
            label: Text('Sign up with Google', style: FsType.subtitle(context)),
            style: OutlinedButton.styleFrom(
              foregroundColor: FsColors.textPrimary(context),
              side: BorderSide(color: FsColors.textSecondary(context).withValues(alpha: 0.2)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FsRadii.control)),
            ),
          ),
        ),

        const SizedBox(height: FsSpace.xl),

        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Already have an account? ', style: FsType.caption(context)),
            GestureDetector(
              onTap: () => Navigator.pushReplacementNamed(context, '/login'),
              child: Text('Sign In', style: FsType.button(FsColors.accent(context))),
            ),
          ],
        ),
        const SizedBox(height: FsSpace.xxl),
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
            Text('Create Account', style: FsType.display(context)),
            const SizedBox(height: FsSpace.xxs),
            Text('Start your UPSC journey', style: FsType.caption(context)),
            const SizedBox(height: FsSpace.xxl),
          ],
          TextFormField(
            controller: _nameCtrl,
            decoration: _inputDec('Full Name', Icons.person_rounded),
            validator: (v) => v != null && v.trim().isNotEmpty ? null : 'Enter your name',
          ),
          const SizedBox(height: FsSpace.md),
          TextFormField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: _inputDec('Email', Icons.email_rounded),
            validator: (v) => v != null && v.contains('@') ? null : 'Enter a valid email',
          ),
          const SizedBox(height: FsSpace.md),
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
            const SizedBox(height: FsSpace.md),
            Text(_error!, style: FsType.caption(context).copyWith(color: FsColors.danger), textAlign: TextAlign.center),
          ],
          const SizedBox(height: FsSpace.xl),
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: auth.isLoading ? null : _signUp,
              style: ElevatedButton.styleFrom(
                backgroundColor: FsColors.accent(context),
                foregroundColor: FsColors.onAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FsRadii.control)),
                elevation: 0,
              ),
              child: auth.isLoading
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.person_add_rounded, size: 20),
                        const SizedBox(width: FsSpace.xs),
                        Text('Create Account', style: FsType.button(FsColors.onAccent).copyWith(fontSize: 16, fontWeight: FontWeight.w700)),
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
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(FsRadii.control), borderSide: BorderSide.none),
      filled: true,
      fillColor: AppTheme.card(context).withValues(alpha: 0.6),
      labelStyle: FsType.body(context),
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
