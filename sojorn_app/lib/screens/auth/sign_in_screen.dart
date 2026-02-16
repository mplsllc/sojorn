import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import '../../providers/auth_provider.dart';
import '../../providers/api_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/auth/turnstile_widget.dart';
import '../../widgets/sojorn_button.dart';
import '../../widgets/sojorn_input.dart';
import 'sign_up_screen.dart';
import 'forgot_password_screen.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  final _localAuth = LocalAuthentication();
  final _secureStorage = const FlutterSecureStorage();
  bool _supportsBiometric = false;
  bool _hasStoredCredentials = false;
  bool _isBiometricAuthenticating = false;
  bool _saveCredentials = true;
  String? _storedEmail;
  String? _storedPassword;
  String? _turnstileToken;

  // Turnstile site key from environment or default production key
  static const String _turnstileSiteKey = String.fromEnvironment(
    'TURNSTILE_SITE_KEY',
    defaultValue: '0x4AAAAAACYFlz_g513d6xAf', // Cloudflare production key
  );

  static const _savedEmailKey = 'saved_login_email';
  static const _savedPasswordKey = 'saved_login_password';

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _prepareBiometric();
  }

  Future<void> _prepareBiometric() async {
    try {
      if (kIsWeb) return; // Local Auth not supported reliably on web right now.

      final deviceSupported = await _localAuth.isDeviceSupported();
      final canCheckBiometrics = await _localAuth.canCheckBiometrics;
      final supports = deviceSupported || canCheckBiometrics;
      await _loadStoredCredentials();

      if (mounted) {
        setState(() {
          _supportsBiometric = supports;
        });
      }
    } catch (e) {
    }
  }

  Future<void> _loadStoredCredentials() async {
    final savedEmail = await _secureStorage.read(key: _savedEmailKey);
    final savedPassword = await _secureStorage.read(key: _savedPasswordKey);
    if (mounted) {
      setState(() {
        _storedEmail = savedEmail;
        _storedPassword = savedPassword;
        _hasStoredCredentials = savedEmail != null && savedPassword != null;
      });
    }
  }

  Future<void> _persistCredentials(String email, String password) async {
    if (_supportsBiometric && _saveCredentials) {
      await _secureStorage.write(key: _savedEmailKey, value: email);
      await _secureStorage.write(key: _savedPasswordKey, value: password);
    } else {
      await _secureStorage.delete(key: _savedEmailKey);
      await _secureStorage.delete(key: _savedPasswordKey);
    }
    await _loadStoredCredentials();
  }

  bool get _canUseBiometricLogin =>
      _supportsBiometric &&
      _hasStoredCredentials &&
      !_isBiometricAuthenticating &&
      _turnstileToken != null; // Require Turnstile for biometric too

  Future<void> _signIn() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _errorMessage = 'Please enter a valid email address';
      });
      return;
    }

    if (_passwordController.text.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter your password';
      });
      return;
    }

    // Validate Turnstile token
    if (_turnstileToken == null || _turnstileToken!.isEmpty) {
      setState(() {
        _errorMessage = 'Please complete the security verification';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authService = ref.read(authServiceProvider);
      await authService.signInWithGoBackend(
        email: email,
        password: password,
        turnstileToken: _turnstileToken!,
      );
      await _persistCredentials(email, password);
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          // Reset Turnstile token on error so user must re-verify
          _turnstileToken = null;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _signInWithBiometrics() async {
    if (!_canUseBiometricLogin) return;

    setState(() {
      _isBiometricAuthenticating = true;
      _errorMessage = null;
    });

    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Unlock sojorn with biometrics',
      );

      if (!authenticated) {
        if (mounted) {
          setState(() {
            _errorMessage = 'Biometric authentication was canceled.';
          });
        }
        return;
      }

      _emailController.text = _storedEmail ?? '';
      _passwordController.text = _storedPassword ?? '';
      await _signIn();
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Unable to unlock with biometrics right now.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isBiometricAuthenticating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(emailVerifiedEventProvider, (previous, next) {
      if (next) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Email verified! You can now sign in.'),
            backgroundColor: Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
        ref.read(emailVerifiedEventProvider.notifier).set(false);
      }
    });

    final isSubmitting = _isLoading;
    final canUseBiometricAction = _canUseBiometricLogin;
    final logoSize = MediaQuery.sizeOf(context).width.clamp(220.0, 320.0);

    return Scaffold(
      body: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.scaffoldBg,
                AppTheme.cardSurface,
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Center(
            child: ScrollConfiguration(
              behavior: const _NoScrollbarBehavior(),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacingLg,
                  vertical: AppTheme.spacingMd,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: AppTheme.spacingLg),
                        Container(
                          padding: const EdgeInsets.all(32),
                          decoration: BoxDecoration(
                            color: AppTheme.cardSurface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: AppTheme.queenPink.withValues(alpha: 0.6),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0x0F000000),
                                blurRadius: 24,
                                offset: const Offset(0, 16),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Center(
                                child: SizedBox(
                                  width: logoSize,
                                  height: logoSize,
                                  child: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Image.asset(
                                      'assets/images/sojorn_logo.png',
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: AppTheme.spacingLg),
                              if (_errorMessage != null) ...[
                                Container(
                                  padding:
                                      const EdgeInsets.all(AppTheme.spacingMd),
                                  decoration: BoxDecoration(
                                    color: AppTheme.error.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color: AppTheme.error, width: 1),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.error_outline,
                                        color: AppTheme.error,
                                        size: 20,
                                      ),
                                      const SizedBox(width: AppTheme.spacingSm),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _errorMessage!,
                                              style: AppTheme
                                                  .textTheme.labelSmall
                                                  ?.copyWith(
                                                color: AppTheme.error,
                                              ),
                                            ),
                                            if (_errorMessage!.contains(
                                                'Email verification required'))
                                              Padding(
                                                padding:
                                                    const EdgeInsets.only(top: 8.0),
                                                child: InkWell(
                                                  onTap: () async {
                                                    final email = _emailController
                                                        .text
                                                        .trim();
                                                    try {
                                                      final api = ref
                                                          .read(apiServiceProvider);
                                                      await api
                                                          .resendVerificationEmail(
                                                              email);
                                                      if (mounted) {
                                                        ScaffoldMessenger.of(
                                                                context)
                                                            .showSnackBar(
                                                          const SnackBar(
                                                              content: Text(
                                                                  'Verification link resent!')),
                                                        );
                                                      }
                                                    } catch (e) {
                                                      if (mounted) {
                                                        ScaffoldMessenger.of(
                                                                context)
                                                            .showSnackBar(
                                                          SnackBar(
                                                              content: Text(
                                                                  'Failed to resend: $e')),
                                                        );
                                                      }
                                                    }
                                                  },
                                                  child: Text(
                                                    'Resend Link',
                                                    style: AppTheme
                                                        .textTheme.labelSmall
                                                        ?.copyWith(
                                                      color: AppTheme.error,
                                                      fontWeight: FontWeight.bold,
                                                      decoration:
                                                          TextDecoration.underline,
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
                                const SizedBox(height: AppTheme.spacingLg),
                              ],
                              sojornInput(
                                label: 'Email',
                                hint: 'you@sojorn.com',
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                prefixIcon: Icons.alternate_email,
                                autofillHints: const [AutofillHints.email],
                                onChanged: (_) {
                                  if (_errorMessage != null) {
                                    setState(() {
                                      _errorMessage = null;
                                    });
                                  }
                                },
                              ),
                              const SizedBox(height: AppTheme.spacingMd),
                              sojornInput(
                                label: 'Password',
                                controller: _passwordController,
                                obscureText: true,
                                textInputAction: TextInputAction.done,
                                prefixIcon: Icons.lock_outline,
                                onEditingComplete: _turnstileToken != null ? _signIn : null,
                                autofillHints: const [AutofillHints.password],
                                onChanged: (_) {
                                  if (_errorMessage != null) {
                                    setState(() {
                                      _errorMessage = null;
                                    });
                                  }
                                },
                              ),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const ForgotPasswordScreen(),
                                      ),
                                    );
                                  },
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: const Size(0, 32),
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: Text(
                                    'Forgot Password?',
                                    style: AppTheme.textTheme.labelSmall?.copyWith(
                                      color: AppTheme.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: AppTheme.spacingLg),
                              
                              // Turnstile CAPTCHA
                              Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: _turnstileToken != null 
                                        ? AppTheme.success 
                                        : AppTheme.egyptianBlue.withValues(alpha: 0.3),
                                    width: 1,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.all(AppTheme.spacingMd),
                                child: Column(
                                  children: [
                                    if (_turnstileToken == null) ...[
                                      TurnstileWidget(
                                        siteKey: _turnstileSiteKey,
                                        onToken: (token) {
                                          setState(() {
                                            _turnstileToken = token;
                                          });
                                        },
                                      ),
                                    ] else ...[
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.check_circle, color: AppTheme.success, size: 20),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Security verified',
                                            style: TextStyle(color: AppTheme.success, fontWeight: FontWeight.w600),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: AppTheme.spacingLg),

                              if (_supportsBiometric) ...[
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Save login for biometric unlock',
                                        style: AppTheme.textTheme.labelSmall
                                            ?.copyWith(
                                          color: AppTheme.navyText
                                              .withValues(alpha: 0.75),
                                        ),
                                      ),
                                    ),
                                    Switch.adaptive(
                                      value: _saveCredentials,
                                      onChanged: (value) {
                                        setState(() {
                                          _saveCredentials = value;
                                        });
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: AppTheme.spacingMd),
                              ],
                              sojornButton(
                                label: 'Sign In',
                                onPressed: (isSubmitting || _turnstileToken == null) ? null : _signIn,
                                isLoading: isSubmitting,
                                isFullWidth: true,
                                variant: sojornButtonVariant.primary,
                                size: sojornButtonSize.large,
                              ),
                              if (canUseBiometricAction) ...[
                                const SizedBox(height: AppTheme.spacingMd),
                                Center(
                                  child: Column(
                                    children: [
                                      InkResponse(
                                        onTap: _isBiometricAuthenticating
                                            ? null
                                            : _signInWithBiometrics,
                                        radius: 32,
                                        child: Container(
                                          width: 52,
                                          height: 52,
                                          decoration: BoxDecoration(
                                            color: AppTheme.cardSurface,
                                            borderRadius:
                                                BorderRadius.circular(26),
                                            border: Border.all(
                                              color: AppTheme.egyptianBlue
                                                  .withValues(alpha: 0.5),
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: const Color(0x0F000000),
                                                blurRadius: 12,
                                                offset: const Offset(0, 6),
                                              ),
                                            ],
                                          ),
                                          child: _isBiometricAuthenticating
                                              ? const Padding(
                                                  padding: EdgeInsets.all(14),
                                                  child:
                                                      CircularProgressIndicator(
                                                          strokeWidth: 2),
                                                )
                                              : Icon(
                                                  Icons.fingerprint,
                                                  color: AppTheme.brightNavy,
                                                  size: 24,
                                                ),
                                        ),
                                      ),
                                      const SizedBox(
                                          height: AppTheme.spacingSm),
                                      Text(
                                        'Use biometrics',
                                        style: AppTheme.textTheme.labelSmall
                                            ?.copyWith(
                                          color: AppTheme.navyText
                                              .withValues(alpha: 0.7),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: AppTheme.spacingMd),
                              if (!kIsWeb) ...[
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'New to Sojorn? ',
                                      style: AppTheme.textTheme.bodyMedium,
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => const SignUpScreen(),
                                          ),
                                        );
                                      },
                                      child: const Text('Create an account'),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: AppTheme.spacingLg),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NoScrollbarBehavior extends ScrollBehavior {
  const _NoScrollbarBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}
