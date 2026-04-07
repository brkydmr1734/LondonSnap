import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:londonsnaps/core/utils/validators.dart';
import 'package:londonsnaps/features/auth/providers/auth_provider.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _usernameController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authProvider = AuthProvider();
  bool _obscurePassword = true;
  bool _autoValidate = false;

  @override
  void dispose() {
    _emailController.dispose();
    _usernameController.dispose();
    _displayNameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    setState(() => _autoValidate = true);
    if (!_formKey.currentState!.validate()) return;
    final success = await _authProvider.register(
      email: _emailController.text.trim(), password: _passwordController.text,
      username: _usernameController.text.trim(), displayName: _displayNameController.text.trim(),
    );
    if (mounted) {
      if (success) {
        context.go('/camera');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_authProvider.error ?? 'Registration failed')),
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

  Future<void> _signUpWithApple() async {
    try {
      final rawNonce = _generateNonce();
      final nonce = _sha256ofString(rawNonce);
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
        nonce: nonce,
      );
      final displayName = [credential.givenName, credential.familyName]
          .where((n) => n != null && n.isNotEmpty).join(' ');
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
            SnackBar(content: Text(_authProvider.error ?? 'Apple Sign-Up failed')),
          );
        }
      }
    } catch (e) {
      if (mounted && !e.toString().contains('AuthorizationErrorCode.canceled')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Apple Sign-Up error: $e')),
        );
      }
    }
  }

  Future<void> _signUpWithGoogle() async {
    try {
      final googleSignIn = GoogleSignIn(scopes: ['email', 'profile']);
      final account = await googleSignIn.signIn();
      if (account == null) return;
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
            SnackBar(content: Text(_authProvider.error ?? 'Google Sign-Up failed')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Google Sign-Up error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop())),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            autovalidateMode: _autoValidate ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Create Account', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text('Join the London student community', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 32),
              TextFormField(
                controller: _emailController, keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(hintText: 'University Email', prefixIcon: Icon(Icons.email_outlined)),
                validator: Validators.email,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _usernameController, textInputAction: TextInputAction.next,
                decoration: const InputDecoration(hintText: 'Username', prefixIcon: Icon(Icons.alternate_email)),
                validator: Validators.username,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _displayNameController, textInputAction: TextInputAction.next,
                decoration: const InputDecoration(hintText: 'Display Name', prefixIcon: Icon(Icons.person_outline)),
                validator: Validators.displayName,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController, obscureText: _obscurePassword,
                textInputAction: TextInputAction.done, onFieldSubmitted: (_) => _register(),
                decoration: InputDecoration(
                  hintText: 'Password', prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                validator: Validators.password,
              ),
              // Password strength indicator
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _passwordController,
                builder: (_, value, _) {
                  if (value.text.isEmpty) return const SizedBox.shrink();
                  final strength = Validators.passwordStrength(value.text);
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LinearProgressIndicator(
                          value: strength,
                          backgroundColor: Colors.grey[800],
                          valueColor: AlwaysStoppedAnimation(
                            strength < 0.4 ? Colors.red : strength < 0.7 ? Colors.orange : Colors.green,
                          ),
                          minHeight: 4,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          strength < 0.4 ? 'Weak' : strength < 0.7 ? 'Medium' : 'Strong',
                          style: TextStyle(
                            fontSize: 11,
                            color: strength < 0.4 ? Colors.red : strength < 0.7 ? Colors.orange : Colors.green,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              ListenableBuilder(
                listenable: _authProvider,
                builder: (context, _) => ElevatedButton(
                  onPressed: _authProvider.isLoading ? null : _register,
                  child: _authProvider.isLoading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Create Account'),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _authProvider.isLoading ? null : _signUpWithApple,
                icon: const Icon(Icons.apple),
                label: const Text('Sign Up with Apple'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _authProvider.isLoading ? null : _signUpWithGoogle,
                icon: const Icon(Icons.g_mobiledata),
                label: const Text('Sign Up with Google'),
              ),
              const SizedBox(height: 24),
              Text('By signing up, you agree to our Terms of Service and Privacy Policy',
                style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
            ],
          ),
          ),
        ),
      ),
    );
  }
}
