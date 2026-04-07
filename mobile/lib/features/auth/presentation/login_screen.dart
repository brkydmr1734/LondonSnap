import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:londonsnaps/core/theme/app_theme.dart';
import 'package:londonsnaps/core/utils/validators.dart';
import 'package:londonsnaps/features/auth/providers/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authProvider = AuthProvider();
  bool _obscurePassword = true;
  bool _autoValidate = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() => _autoValidate = true);
    if (!_formKey.currentState!.validate()) return;
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final success = await _authProvider.login(email, password);
    if (mounted) {
      if (success) {
        context.go('/camera');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_authProvider.error ?? 'Login failed')),
        );
      }
    }
  }

  Future<void> _forgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your email first')),
      );
      return;
    }
    await _authProvider.requestPasswordReset(email);
    if (mounted) {
      if (_authProvider.error == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password reset email sent')),
        );
        context.push('/reset-password', extra: email);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_authProvider.error ?? 'Failed to send reset email')),
        );
      }
    }
  }

  String _generateNonce([int length = 32]) {
    const charset = '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)]).join();
  }

  String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<void> _signInWithApple() async {
    try {
      final rawNonce = _generateNonce();
      final nonce = _sha256ofString(rawNonce);

      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
      );

      final displayName = [
        credential.givenName,
        credential.familyName,
      ].where((n) => n != null && n.isNotEmpty).join(' ');

      final success = await _authProvider.socialAuth(
        provider: 'APPLE',
        providerId: credential.userIdentifier ?? '',
        email: credential.email,
        displayName: displayName.isNotEmpty ? displayName : null,
      );

      if (mounted) {
        if (success) {
          context.go('/camera');
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_authProvider.error ?? 'Apple Sign-In failed')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString();
        if (!msg.contains('AuthorizationErrorCode.canceled')) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Apple Sign-In error: $msg')),
          );
        }
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    try {
      final googleSignIn = GoogleSignIn(scopes: ['email', 'profile']);
      final account = await googleSignIn.signIn();
      if (account == null) return; // User cancelled

      final success = await _authProvider.socialAuth(
        provider: 'GOOGLE',
        providerId: account.id,
        email: account.email,
        displayName: account.displayName,
        avatarUrl: account.photoUrl,
      );

      if (mounted) {
        if (success) {
          context.go('/camera');
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_authProvider.error ?? 'Google Sign-In failed')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Google Sign-In error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            autovalidateMode: _autoValidate ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              const SizedBox(height: 60),
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.asset(
                  'assets/images/app_icon.png',
                  width: 100,
                  height: 100,
                  filterQuality: FilterQuality.high,
                ),
              ),
              const SizedBox(height: 32),
              Text('LondonSnaps', style: Theme.of(context).textTheme.headlineLarge, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text('Connect with London students', style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center),
              const SizedBox(height: 48),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(hintText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
                validator: Validators.email,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _login(),
                decoration: InputDecoration(
                  hintText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                validator: (v) => Validators.required(v, 'Password'),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _forgotPassword,
                  child: const Text('Forgot Password?', style: TextStyle(color: AppTheme.primaryColor, fontSize: 13)),
                ),
              ),
              const SizedBox(height: 8),
              ListenableBuilder(
                listenable: _authProvider,
                builder: (context, _) => ElevatedButton(
                  onPressed: _authProvider.isLoading ? null : _login,
                  child: _authProvider.isLoading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Log In'),
                ),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: Divider(color: AppTheme.surfaceColor)),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text('or', style: Theme.of(context).textTheme.bodySmall)),
                Expanded(child: Divider(color: AppTheme.surfaceColor)),
              ]),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _authProvider.isLoading ? null : _signInWithApple,
                icon: const Icon(Icons.apple),
                label: const Text('Continue with Apple'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _authProvider.isLoading ? null : _signInWithGoogle,
                icon: const Icon(Icons.g_mobiledata),
                label: const Text('Continue with Google'),
              ),
              const SizedBox(height: 32),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text("Don't have an account? ", style: Theme.of(context).textTheme.bodyMedium),
                GestureDetector(
                  onTap: () => context.push('/register'),
                  child: const Text('Sign Up', style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.w600)),
                ),
              ]),
            ],
            ),
          ),
        ),
      ),
    );
  }
}
