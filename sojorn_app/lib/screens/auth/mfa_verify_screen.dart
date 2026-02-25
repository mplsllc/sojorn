// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/sojorn_button.dart';

/// Screen shown after login when MFA is required.
/// Accepts a 6-digit TOTP code or a recovery code.
class MFAVerifyScreen extends ConsumerStatefulWidget {
  final String tempToken;
  final VoidCallback? onSuccess;

  const MFAVerifyScreen({
    super.key,
    required this.tempToken,
    this.onSuccess,
  });

  @override
  ConsumerState<MFAVerifyScreen> createState() => _MFAVerifyScreenState();
}

class _MFAVerifyScreenState extends ConsumerState<MFAVerifyScreen> {
  final List<TextEditingController> _digitControllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  final _recoveryController = TextEditingController();

  bool _isLoading = false;
  bool _useRecoveryCode = false;
  String? _errorMessage;

  @override
  void dispose() {
    for (final c in _digitControllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    _recoveryController.dispose();
    super.dispose();
  }

  String get _code => _digitControllers.map((c) => c.text).join();

  Future<void> _verify() async {
    if (_isLoading) return;

    final code = _useRecoveryCode ? null : _code;
    final recovery = _useRecoveryCode ? _recoveryController.text.trim() : null;

    if (!_useRecoveryCode && (code == null || code.length != 6)) {
      setState(() => _errorMessage = 'Enter all 6 digits');
      return;
    }
    if (_useRecoveryCode && (recovery == null || recovery.isEmpty)) {
      setState(() => _errorMessage = 'Enter your recovery code');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authService = ref.read(authServiceProvider);
      await authService.verifyMFA(
        tempToken: widget.tempToken,
        code: code,
        recoveryCode: recovery,
      );
      if (mounted) {
        widget.onSuccess?.call();
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() => _errorMessage = e.message);
        // Clear code fields on error
        if (!_useRecoveryCode) {
          for (final c in _digitControllers) {
            c.clear();
          }
          _focusNodes[0].requestFocus();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Verification failed. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onDigitChanged(int index, String value) {
    if (value.length == 1 && index < 5) {
      _focusNodes[index + 1].requestFocus();
    }
    // Auto-submit when all 6 digits entered
    if (_code.length == 6) {
      _verify();
    }
  }

  void _onDigitKey(int index, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _digitControllers[index].text.isEmpty &&
        index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppTheme.scaffoldBg, AppTheme.cardSurface],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
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
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x0F000000),
                        blurRadius: 24,
                        offset: Offset(0, 16),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppTheme.brightNavy.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.security,
                          color: AppTheme.brightNavy,
                          size: 32,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Two-Factor Authentication',
                        style: TextStyle(
                          color: AppTheme.navyBlue,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _useRecoveryCode
                            ? 'Enter one of your recovery codes'
                            : 'Enter the 6-digit code from your authenticator app',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppTheme.navyText.withValues(alpha: 0.6),
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Error message
                      if (_errorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.error.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.error),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline,
                                  color: AppTheme.error, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: TextStyle(
                                    color: AppTheme.error,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Code input
                      if (!_useRecoveryCode)
                        _buildDigitFields()
                      else
                        TextField(
                          controller: _recoveryController,
                          decoration: InputDecoration(
                            hintText: 'xxxxx-xxxxx',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                          ),
                          textInputAction: TextInputAction.done,
                          onEditingComplete: _verify,
                        ),
                      const SizedBox(height: 24),

                      sojornButton(
                        label: 'Verify',
                        onPressed: _isLoading ? null : _verify,
                        isLoading: _isLoading,
                        isFullWidth: true,
                        variant: sojornButtonVariant.primary,
                        size: sojornButtonSize.large,
                      ),
                      const SizedBox(height: 16),

                      TextButton(
                        onPressed: () {
                          setState(() {
                            _useRecoveryCode = !_useRecoveryCode;
                            _errorMessage = null;
                          });
                        },
                        child: Text(
                          _useRecoveryCode
                              ? 'Use authenticator code instead'
                              : 'Use a recovery code',
                          style: TextStyle(
                            color: AppTheme.brightNavy,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
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

  Widget _buildDigitFields() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(6, (i) {
        return Container(
          width: 46,
          margin: EdgeInsets.only(
            left: i == 0 ? 0 : (i == 3 ? 12 : 6),
            right: i == 5 ? 0 : 0,
          ),
          child: KeyboardListener(
            focusNode: FocusNode(),
            onKeyEvent: (event) => _onDigitKey(i, event),
            child: TextField(
              controller: _digitControllers[i],
              focusNode: _focusNodes[i],
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 1,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppTheme.navyBlue,
              ),
              decoration: InputDecoration(
                counterText: '',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: AppTheme.navyBlue.withValues(alpha: 0.2),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppTheme.brightNavy, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (v) => _onDigitChanged(i, v),
            ),
          ),
        );
      }),
    );
  }
}
