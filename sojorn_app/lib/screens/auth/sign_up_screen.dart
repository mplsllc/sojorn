import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/auth/turnstile_widget.dart';

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _handleController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  
  // Turnstile token
  String? _turnstileToken;
  
  // Legal consent
  bool _acceptTerms = false;
  bool _acceptPrivacy = false;
  
  // Email preferences (single combined option)
  bool _emailUpdates = false;
  
  // Age gate
  int? _birthMonth;
  int? _birthYear;

  // Turnstile site key from environment or default production key
  static const String _turnstileSiteKey = String.fromEnvironment(
    'TURNSTILE_SITE_KEY',
    defaultValue: '0x4AAAAAACYFlz_g513d6xAf', // Cloudflare production key
  );

  @override
  void dispose() {
    _emailController.dispose();
    _handleController.dispose();
    _displayNameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;
    
    // Validate Turnstile token
    if (_turnstileToken == null || _turnstileToken!.isEmpty) {
      setState(() {
        _errorMessage = 'Please complete the security verification';
      });
      return;
    }
    
    // Validate age gate
    if (_birthMonth == null || _birthYear == null) {
      setState(() {
        _errorMessage = 'Please enter your date of birth';
      });
      return;
    }
    
    // Validate legal consent
    if (!_acceptTerms) {
      setState(() {
        _errorMessage = 'You must accept the Terms of Service';
      });
      return;
    }
    
    if (!_acceptPrivacy) {
      setState(() {
        _errorMessage = 'You must accept the Privacy Policy';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authService = ref.read(authServiceProvider);
      await authService.registerWithGoBackend(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        handle: _handleController.text.trim(),
        displayName: _displayNameController.text.trim(),
        turnstileToken: _turnstileToken!,
        acceptTerms: _acceptTerms,
        acceptPrivacy: _acceptPrivacy,
        emailNewsletter: _emailUpdates,
        emailContact: _emailUpdates,
        birthMonth: _birthMonth!,
        birthYear: _birthYear!,
      );

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Verify your email'),
            content: const Text(
                'A verification link has been sent to your email. Please check your inbox (and spam folder) to verify your account before logging in.'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(); // dialog
                  Navigator.of(context).pop(); // signup screen
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _turnstileToken = null; // Reset Turnstile on error
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

  void _showMonthPicker() {
    const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Select Month', style: AppTheme.headlineSmall),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: 12,
                itemBuilder: (ctx, i) => ListTile(
                  title: Text(months[i]),
                  selected: _birthMonth == i + 1,
                  onTap: () {
                    setState(() => _birthMonth = i + 1);
                    Navigator.pop(ctx);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showYearPicker() {
    final currentYear = DateTime.now().year;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Select Year', style: AppTheme.headlineSmall),
            ),
            const Divider(height: 1),
            SizedBox(
              height: 300,
              child: ListView.builder(
                itemCount: currentYear - 1900 + 1,
                itemBuilder: (ctx, i) {
                  final year = currentYear - i;
                  return ListTile(
                    title: Text('$year'),
                    selected: _birthYear == year,
                    onTap: () {
                      setState(() => _birthYear = year);
                      Navigator.pop(ctx);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Account'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppTheme.spacingLg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Welcome message
                    Text(
                      'Welcome to sojorn',
                      style: AppTheme.headlineMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppTheme.spacingSm),

                    Text(
                      'Your vibrant journey begins now',
                      style: AppTheme.bodyMedium.copyWith(
                        color: AppTheme.navyText.withValues(alpha: 0.8),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppTheme.spacingLg * 1.5),

                    // Error message
                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(AppTheme.spacingMd),
                        decoration: BoxDecoration(
                          color: AppTheme.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.error, width: 1),
                        ),
                        child: Text(
                          _errorMessage!,
                          style: AppTheme.textTheme.labelSmall?.copyWith(
                            color: AppTheme.error,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppTheme.spacingLg),
                    ],

                    // Handle field
                    TextFormField(
                      controller: _handleController,
                      decoration: const InputDecoration(
                        labelText: 'Handle (@username)',
                        hintText: 'sojorn_user',
                        prefixIcon: Icon(Icons.alternate_email),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) return 'Handle is required';
                        if (value.length < 3) return 'Handle must be at least 3 characters';
                        if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(value)) {
                          return 'Handle can only contain letters, numbers, and underscores';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: AppTheme.spacingMd),

                    // Display Name field
                    TextFormField(
                      controller: _displayNameController,
                      decoration: const InputDecoration(
                        labelText: 'Display Name',
                        hintText: 'Jane Doe',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) return 'Display Name is required';
                        return null;
                      },
                    ),
                    const SizedBox(height: AppTheme.spacingMd),

                    // Email field
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        hintText: 'your@email.com',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Email is required';
                        }
                        if (!value.contains('@') || !value.contains('.')) {
                          return 'Enter a valid email';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: AppTheme.spacingMd),

                    // Password field
                    TextFormField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        hintText: 'At least 6 characters',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Password is required';
                        }
                        if (value.length < 6) {
                          return 'Password must be at least 6 characters';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: AppTheme.spacingMd),

                    // Confirm password field
                    TextFormField(
                      controller: _confirmPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Confirm Password',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please confirm your password';
                        }
                        if (value != _passwordController.text) {
                          return 'Passwords do not match';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: AppTheme.spacingLg),

                    // Age Gate - Birth Month & Year
                    Text(
                      'Date of Birth',
                      style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'You must be at least 16 to use Sojorn. Users under 18 cannot access sensitive content.',
                      style: AppTheme.textTheme.labelSmall?.copyWith(
                        color: AppTheme.navyText.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacingSm),
                    Row(
                      children: [
                        // Month picker
                        Expanded(
                          flex: 3,
                          child: GestureDetector(
                            onTap: () => _showMonthPicker(),
                            child: AbsorbPointer(
                              child: TextFormField(
                                decoration: InputDecoration(
                                  labelText: 'Month',
                                  prefixIcon: const Icon(Icons.calendar_month),
                                  hintText: 'Select',
                                  suffixIcon: const Icon(Icons.arrow_drop_down),
                                ),
                                controller: TextEditingController(
                                  text: _birthMonth != null
                                      ? const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][_birthMonth! - 1]
                                      : '',
                                ),
                                validator: (_) => _birthMonth == null ? 'Required' : null,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppTheme.spacingSm),
                        // Year picker
                        Expanded(
                          flex: 2,
                          child: GestureDetector(
                            onTap: () => _showYearPicker(),
                            child: AbsorbPointer(
                              child: TextFormField(
                                decoration: InputDecoration(
                                  labelText: 'Year',
                                  hintText: 'Select',
                                  suffixIcon: const Icon(Icons.arrow_drop_down),
                                ),
                                controller: TextEditingController(
                                  text: _birthYear != null ? '$_birthYear' : '',
                                ),
                                validator: (_) => _birthYear == null ? 'Required' : null,
                              ),
                            ),
                          ),
                        ),
                      ],
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

                    // Terms of Service checkbox
                    CheckboxListTile(
                      value: _acceptTerms,
                      onChanged: (value) => setState(() => _acceptTerms = value ?? false),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: RichText(
                        text: TextSpan(
                          style: AppTheme.textTheme.bodySmall?.copyWith(color: AppTheme.navyText),
                          children: [
                            const TextSpan(text: 'I agree to the '),
                            TextSpan(
                              text: 'Terms of Service',
                              style: TextStyle(color: AppTheme.brightNavy, fontWeight: FontWeight.w600),
                              recognizer: TapGestureRecognizer()
                                ..onTap = () => _launchUrl('https://mp.ls/terms'),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Privacy Policy checkbox
                    CheckboxListTile(
                      value: _acceptPrivacy,
                      onChanged: (value) => setState(() => _acceptPrivacy = value ?? false),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: RichText(
                        text: TextSpan(
                          style: AppTheme.textTheme.bodySmall?.copyWith(color: AppTheme.navyText),
                          children: [
                            const TextSpan(text: 'I agree to the '),
                            TextSpan(
                              text: 'Privacy Policy',
                              style: TextStyle(color: AppTheme.brightNavy, fontWeight: FontWeight.w600),
                              recognizer: TapGestureRecognizer()
                                ..onTap = () => _launchUrl('https://mp.ls/privacy'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    // Email updates preference (part of agreement section)
                    CheckboxListTile(
                      value: _emailUpdates,
                      onChanged: (value) => setState(() => _emailUpdates = value ?? false),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(
                        'Please send me email updates about sojorn and MPLS LLC',
                        style: AppTheme.textTheme.bodySmall?.copyWith(color: AppTheme.navyText),
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacingMd),

                    // Sign up button
                    ElevatedButton(
                      onPressed: _isLoading ? null : _signUp,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(SojornColors.basicWhite),
                              ),
                            )
                          : const Text('Create Account'),
                    ),
                    const SizedBox(height: AppTheme.spacingMd),

                    // Footer
                    Text(
                      'A product of MPLS LLC.',
                      style: AppTheme.textTheme.labelSmall?.copyWith(
                        color: AppTheme.egyptianBlue,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
