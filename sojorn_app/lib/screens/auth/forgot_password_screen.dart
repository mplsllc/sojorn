// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/sojorn_button.dart';
import '../../widgets/sojorn_input.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  bool _emailSent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendResetLink() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _errorMessage = 'Please enter a valid email address';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await ref.read(authServiceProvider).resetPassword(email);
      if (mounted) {
        setState(() {
          _emailSent = true;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reset Password'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppTheme.navyText),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
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
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppTheme.spacingLg),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Container(
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
                  child: _emailSent
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.mark_email_read_outlined,
                              size: 64,
                              color: AppTheme.success,
                            ),
                            const SizedBox(height: AppTheme.spacingMd),
                            Text(
                              'Check your email',
                              style: AppTheme.textTheme.headlineMedium,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: AppTheme.spacingSm),
                            Text(
                              'We have sent a password reset link to ${_emailController.text}',
                              style: AppTheme.textTheme.bodyMedium,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: AppTheme.spacingLg),
                            sojornButton(
                              label: 'Back to Sign In',
                              onPressed: () => Navigator.of(context).pop(),
                              isFullWidth: true,
                              variant: sojornButtonVariant.secondary,
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Forgot Password?',
                              style: AppTheme.textTheme.headlineMedium,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: AppTheme.spacingSm),
                            Text(
                              'Enter your email address and we will send you a link to reset your password.',
                              style: AppTheme.textTheme.bodyMedium?.copyWith(
                                color: AppTheme.navyText.withValues(alpha: 0.7),
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: AppTheme.spacingLg),
                            if (_errorMessage != null)
                              Container(
                                margin: const EdgeInsets.only(
                                    bottom: AppTheme.spacingMd),
                                padding:
                                    const EdgeInsets.all(AppTheme.spacingSm),
                                decoration: BoxDecoration(
                                  color: AppTheme.error.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  _errorMessage!,
                                  style: AppTheme.textTheme.bodyMedium?.copyWith(
                                    color: AppTheme.error,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            sojornInput(
                              label: 'Email',
                              hint: 'you@sojorn.com',
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              prefixIcon: Icons.email_outlined,
                            ),
                            const SizedBox(height: AppTheme.spacingLg),
                            sojornButton(
                              label: 'Send Reset Link',
                              onPressed: _isLoading ? null : _sendResetLink,
                              isLoading: _isLoading,
                              isFullWidth: true,
                              variant: sojornButtonVariant.primary,
                            ),
                          ],
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
