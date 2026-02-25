// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../utils/snackbar_ext.dart';
import '../../widgets/sojorn_button.dart';

/// Three-step MFA setup flow:
/// 1. Show QR code + manual secret
/// 2. Verify first TOTP code
/// 3. Display recovery codes (one-time)
class MFASetupScreen extends StatefulWidget {
  const MFASetupScreen({super.key});

  @override
  State<MFASetupScreen> createState() => _MFASetupScreenState();
}

class _MFASetupScreenState extends State<MFASetupScreen> {
  int _step = 0; // 0=loading, 1=QR, 2=verify, 3=recovery codes
  bool _loading = true;
  bool _verifying = false;
  String? _error;

  String? _secret;
  String? _provisioningUri;
  List<String> _recoveryCodes = [];

  final _codeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _startSetup();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _startSetup() async {
    try {
      final data = await AuthService.instance.setupMFA();
      if (!mounted) return;
      setState(() {
        _secret = data['secret'] as String;
        _provisioningUri = data['provisioning_uri'] as String;
        _recoveryCodes = (data['recovery_codes'] as List).cast<String>();
        _step = 1;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceAll('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  Future<void> _confirmCode() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code');
      return;
    }

    setState(() {
      _verifying = true;
      _error = null;
    });

    try {
      await AuthService.instance.confirmMFA(code);
      if (mounted) setState(() => _step = 3);
    } catch (e) {
      if (mounted) {
        setState(
            () => _error = e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Two-Factor Authentication'),
        backgroundColor: AppTheme.cardSurface,
        foregroundColor: AppTheme.navyBlue,
        elevation: 0,
      ),
      backgroundColor: AppTheme.scaffoldBg,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: _buildStep(),
              ),
      ),
    );
  }

  Widget _buildStep() {
    if (_error != null && _step == 0) {
      return _buildError();
    }
    switch (_step) {
      case 1:
        return _buildQRStep();
      case 2:
        return _buildVerifyStep();
      case 3:
        return _buildRecoveryStep();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, color: AppTheme.error, size: 48),
          const SizedBox(height: 16),
          Text(_error!, style: TextStyle(color: AppTheme.error, fontSize: 14)),
          const SizedBox(height: 24),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Go back'),
          ),
        ],
      ),
    );
  }

  Widget _buildQRStep() {
    return _card(
      children: [
        _stepIndicator(1),
        const SizedBox(height: 16),
        Text(
          'Scan this QR code',
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppTheme.navyBlue,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Open your authenticator app (Google Authenticator, Authy, etc.) and scan this code.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppTheme.navyText.withValues(alpha: 0.6),
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: QrImageView(
            data: _provisioningUri!,
            version: QrVersions.auto,
            size: 200,
            backgroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Or enter this key manually:',
          style: TextStyle(
            color: AppTheme.navyText.withValues(alpha: 0.5),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () {
            Clipboard.setData(ClipboardData(text: _secret!));
            if (mounted) context.showSuccess('Secret copied to clipboard');
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.navyBlue.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: AppTheme.navyBlue.withValues(alpha: 0.12)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    _secret!,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.navyBlue,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.copy, size: 16,
                    color: AppTheme.navyBlue.withValues(alpha: 0.5)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 28),
        sojornButton(
          label: 'Next',
          onPressed: () => setState(() => _step = 2),
          isFullWidth: true,
          variant: sojornButtonVariant.primary,
          size: sojornButtonSize.large,
        ),
      ],
    );
  }

  Widget _buildVerifyStep() {
    return _card(
      children: [
        _stepIndicator(2),
        const SizedBox(height: 16),
        Text(
          'Enter verification code',
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppTheme.navyBlue,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Enter the 6-digit code shown in your authenticator app to confirm setup.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppTheme.navyText.withValues(alpha: 0.6),
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 24),
        if (_error != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.error),
            ),
            child: Text(_error!,
                style: TextStyle(color: AppTheme.error, fontSize: 13)),
          ),
          const SizedBox(height: 16),
        ],
        TextField(
          controller: _codeController,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 6,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: AppTheme.navyBlue,
            letterSpacing: 8,
          ),
          decoration: InputDecoration(
            counterText: '',
            hintText: '000000',
            hintStyle: GoogleFonts.jetBrainsMono(
              fontSize: 28,
              color: AppTheme.navyBlue.withValues(alpha: 0.15),
              letterSpacing: 8,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppTheme.brightNavy, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 16),
          ),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onEditingComplete: _confirmCode,
        ),
        const SizedBox(height: 24),
        sojornButton(
          label: 'Verify & Enable',
          onPressed: _verifying ? null : _confirmCode,
          isLoading: _verifying,
          isFullWidth: true,
          variant: sojornButtonVariant.primary,
          size: sojornButtonSize.large,
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => setState(() {
            _step = 1;
            _error = null;
          }),
          child: Text('Back to QR code',
              style: TextStyle(color: AppTheme.brightNavy)),
        ),
      ],
    );
  }

  Widget _buildRecoveryStep() {
    return _card(
      children: [
        _stepIndicator(3),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.success.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.check_circle, color: AppTheme.success, size: 32),
        ),
        const SizedBox(height: 16),
        Text(
          'MFA Enabled',
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppTheme.navyBlue,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Save these recovery codes in a safe place. You can use them to sign in if you lose your authenticator.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppTheme.navyText.withValues(alpha: 0.6),
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 20),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.navyBlue.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: AppTheme.navyBlue.withValues(alpha: 0.1)),
          ),
          child: Column(
            children: _recoveryCodes
                .map((code) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text(
                        code,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.navyBlue,
                        ),
                      ),
                    ))
                .toList(),
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () {
            final text = _recoveryCodes.join('\n');
            Clipboard.setData(ClipboardData(text: text));
            if (mounted) context.showSuccess('Recovery codes copied');
          },
          icon: const Icon(Icons.copy, size: 16),
          label: const Text('Copy codes'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.brightNavy,
            side: BorderSide(
                color: AppTheme.brightNavy.withValues(alpha: 0.3)),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const SizedBox(height: 24),
        sojornButton(
          label: 'I\'ve saved my codes',
          onPressed: () => Navigator.pop(context, true),
          isFullWidth: true,
          variant: sojornButtonVariant.primary,
          size: sojornButtonSize.large,
        ),
      ],
    );
  }

  Widget _card({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(SojornRadii.card),
        border: Border.all(
          color: AppTheme.queenPink.withValues(alpha: 0.5),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }

  Widget _stepIndicator(int step) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (i) {
        final active = i + 1 <= step;
        final current = i + 1 == step;
        return Row(
          children: [
            Container(
              width: current ? 28 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: active
                    ? AppTheme.brightNavy
                    : AppTheme.navyBlue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            if (i < 2) const SizedBox(width: 6),
          ],
        );
      }),
    );
  }
}
