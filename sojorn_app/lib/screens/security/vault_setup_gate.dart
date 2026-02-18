import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:universal_html/html.dart' as universal_html;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import '../../services/key_vault_service.dart';
import '../../providers/vault_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';

/// Mandatory gate after first sign-in.
///
/// New user:  Create password → auto-sync → one-time recovery key → done.
/// Returning: Enter password → restore all keys → done.
///
/// The recovery key is shown ONCE and cannot be retrieved again.
/// If the user loses both their password and recovery key, their
/// encrypted data is gone — that's the security trade-off.
class VaultSetupGate extends ConsumerStatefulWidget {
  final Widget child;
  const VaultSetupGate({super.key, required this.child});

  @override
  ConsumerState<VaultSetupGate> createState() => _VaultSetupGateState();
}

enum _GateMode { create, restore, backupKey }

class _VaultSetupGateState extends ConsumerState<VaultSetupGate> {
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _backupKeyCtrl = TextEditingController();
  bool _submitting = false;
  bool _obscure = true;
  String? _error;
  _GateMode _mode = _GateMode.create;

  // Recovery key (shown once after setup)
  String? _recoveryKey;
  bool _keyCopied = false;

  // Reactivation state
  bool _isReactivated = false;
  String? _previousStatus;
  bool _reactivationChecked = false;

  @override
  void initState() {
    super.initState();
    _checkReactivation();
  }

  Future<void> _checkReactivation() async {
    const storage = FlutterSecureStorage();
    final reactivated = await storage.read(key: 'account_reactivated');
    final prevStatus = await storage.read(key: 'account_previous_status');
    if (mounted) {
      setState(() {
        _isReactivated = reactivated == 'true';
        _previousStatus = prevStatus;
        _reactivationChecked = true;
        if (_isReactivated) {
          _mode = _GateMode.restore;
        }
      });
    }
    // Clear the flag so it only shows once
    if (reactivated == 'true') {
      await storage.delete(key: 'account_reactivated');
      await storage.delete(key: 'account_previous_status');
    }
  }

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _backupKeyCtrl.dispose();
    super.dispose();
  }

  // ── Create ──────────────────────────────────────────────────────────

  Future<void> _create() async {
    final pw = _passwordCtrl.text.trim();
    final confirm = _confirmCtrl.text.trim();

    if (pw.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters');
      return;
    }
    if (pw != confirm) {
      setState(() => _error = 'Passwords do not match');
      return;
    }

    setState(() { _submitting = true; _error = null; });
    try {
      // Generate recovery key first so setupVault can encrypt a second backup with it
      final key = KeyVaultService.instance.generateRecoveryKey();
      final rawKey = key.replaceAll('-', '');
      await KeyVaultService.instance.setupVault(pw, recoveryKey: rawKey);
      if (mounted) setState(() { _submitting = false; _recoveryKey = key; });
    } catch (e) {
      if (mounted) setState(() { _error = 'Setup failed: $e'; _submitting = false; });
    }
  }

  // ── Restore ─────────────────────────────────────────────────────────

  Future<void> _restore() async {
    final pw = _passwordCtrl.text.trim();
    if (pw.isEmpty) {
      setState(() => _error = 'Enter your sync password');
      return;
    }

    setState(() { _submitting = true; _error = null; });
    try {
      await KeyVaultService.instance.restoreFromPassphrase(pw);
      ref.invalidate(vaultSetupProvider);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Wrong password or no backup found';
          _submitting = false;
        });
      }
    }
  }

  // ── Restore from Backup Key ──────────────────────────────────────────

  Future<void> _restoreFromBackupKey() async {
    final key = _backupKeyCtrl.text.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (key.length < 16) {
      setState(() => _error = 'Please enter your full backup key');
      return;
    }

    setState(() { _submitting = true; _error = null; });
    try {
      await KeyVaultService.instance.restoreFromRecoveryKey(key);
      ref.invalidate(vaultSetupProvider);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Invalid backup key or no backup found';
          _submitting = false;
        });
      }
    }
  }

  // ── Recovery key actions ────────────────────────────────────────────

  void _copyKey() {
    if (_recoveryKey == null) return;
    Clipboard.setData(ClipboardData(text: _recoveryKey!));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Recovery key copied'), backgroundColor: Color(0xFF4CAF50)));
    setState(() => _keyCopied = true);
  }

  Future<void> _downloadKey() async {
    if (_recoveryKey == null) return;
    final content = 'SOJORN RECOVERY KEY\n'
        '====================\n\n'
        '${_recoveryKey!}\n\n'
        'Created: ${DateTime.now().toIso8601String()}\n\n'
        'Keep this file safe. You will NOT be able to download\n'
        'this key again. If you lose both your sync password and\n'
        'this recovery key, your encrypted data is permanently lost.';

    try {
      if (kIsWeb) {
        // Trigger a browser file download via a data URI
        final bytes = utf8.encode(content);
        final base64Data = base64Encode(bytes);
        final anchor = universal_html.AnchorElement(
          href: 'data:text/plain;charset=utf-8;base64,$base64Data',
        )
          ..setAttribute('download', 'sojorn_recovery_key.txt')
          ..click();
        anchor.remove();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Recovery key downloaded'), backgroundColor: Color(0xFF4CAF50)));
        }
      } else {
        final result = await FilePicker.platform.saveFile(
          dialogTitle: 'Save Recovery Key',
          fileName: 'sojorn_recovery_key.txt',
        );
        if (result != null) {
          await File(result).writeAsString(content);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Recovery key saved'), backgroundColor: Color(0xFF4CAF50)));
          }
        }
      }
      setState(() => _keyCopied = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), backgroundColor: SojornColors.destructive));
      }
    }
  }

  void _finish() {
    ref.invalidate(vaultSetupProvider);
  }

  // ── Build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final vaultAsync = ref.watch(vaultSetupProvider);

    return vaultAsync.when(
      data: (isSetup) {
        if (isSetup) return widget.child;
        if (!_reactivationChecked) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (_recoveryKey != null) return _buildRecoveryScreen();
        return _buildPasswordScreen();
      },
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, __) => widget.child,
    );
  }

  // ── Password Screen (create or restore) ─────────────────────────────

  Widget _buildPasswordScreen() {
    final isCreate = _mode == _GateMode.create;
    final isBackupKey = _mode == _GateMode.backupKey;

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Welcome Back banner for reactivated users
                if (_isReactivated) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF4CAF50).withValues(alpha: 0.12),
                          const Color(0xFF4CAF50).withValues(alpha: 0.04),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF4CAF50).withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.waving_hand, size: 36, color: Color(0xFF4CAF50)),
                        const SizedBox(height: 12),
                        Text('Welcome Back!',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.literata(
                            fontWeight: FontWeight.w700, color: const Color(0xFF2E7D32), fontSize: 22)),
                        const SizedBox(height: 8),
                        Text(
                          _previousStatus == 'pending_deletion'
                            ? 'Your scheduled deletion has been cancelled and your account is fully restored.'
                            : 'Your account has been reactivated. All your data is intact.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 13, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.brightNavy.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isBackupKey ? Icons.vpn_key : Icons.shield,
                    size: 56, color: AppTheme.brightNavy),
                ),
                const SizedBox(height: 24),

                Text(
                  isCreate ? 'Create Sync Password'
                    : isBackupKey ? 'Restore with Backup Key'
                    : 'Restore Your Keys',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.literata(
                    fontWeight: FontWeight.w700, color: AppTheme.navyBlue, fontSize: 24)),
                const SizedBox(height: 12),

                Text(
                  isCreate
                    ? 'Choose a password to protect your encryption keys. '
                      'Your chats and groups will sync automatically.'
                    : isBackupKey
                      ? 'Enter the backup key you saved when you first set up your account.'
                      : 'Enter your sync password to restore your encryption keys.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 14, height: 1.5),
                ),
                const SizedBox(height: 32),

                if (isBackupKey) ...[
                  // Backup key input
                  TextField(
                    controller: _backupKeyCtrl,
                    textCapitalization: TextCapitalization.characters,
                    style: GoogleFonts.jetBrainsMono(
                      color: SojornColors.postContent, fontSize: 15, letterSpacing: 1.5),
                    decoration: InputDecoration(
                      labelText: 'Backup Key',
                      labelStyle: TextStyle(color: SojornColors.textDisabled),
                      hintText: 'XXXX-XXXX-XXXX-XXXX-...',
                      hintStyle: TextStyle(color: SojornColors.textDisabled),
                      prefixIcon: Icon(Icons.vpn_key, color: AppTheme.brightNavy),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppTheme.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppTheme.brightNavy, width: 2),
                      ),
                      filled: true,
                      fillColor: AppTheme.cardSurface,
                    ),
                  ),
                ] else ...[
                  // Password field
                  TextField(
                    controller: _passwordCtrl,
                    obscureText: _obscure,
                    style: TextStyle(color: SojornColors.postContent),
                    decoration: InputDecoration(
                      labelText: isCreate ? 'Sync Password' : 'Your Sync Password',
                      labelStyle: TextStyle(color: SojornColors.textDisabled),
                      hintText: isCreate ? 'At least 8 characters' : null,
                      hintStyle: TextStyle(color: SojornColors.textDisabled),
                      prefixIcon: Icon(Icons.key, color: AppTheme.brightNavy),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                          color: SojornColors.textDisabled, size: 20),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppTheme.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppTheme.brightNavy, width: 2),
                      ),
                      filled: true,
                      fillColor: AppTheme.cardSurface,
                    ),
                  ),
                ],

                if (isCreate) ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: _confirmCtrl,
                    obscureText: _obscure,
                    style: TextStyle(color: SojornColors.postContent),
                    decoration: InputDecoration(
                      labelText: 'Confirm Password',
                      labelStyle: TextStyle(color: SojornColors.textDisabled),
                      prefixIcon: Icon(Icons.lock, color: AppTheme.brightNavy),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppTheme.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppTheme.brightNavy, width: 2),
                      ),
                      filled: true,
                      fillColor: AppTheme.cardSurface,
                    ),
                  ),
                ],

                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: GoogleFonts.inter(color: SojornColors.destructive, fontSize: 13)),
                ],

                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _submitting ? null : (
                      isCreate ? _create
                        : isBackupKey ? _restoreFromBackupKey
                        : _restore
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.brightNavy,
                      foregroundColor: SojornColors.basicWhite,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: _submitting
                        ? const SizedBox(width: 22, height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(
                            isCreate ? 'Create & Sync'
                              : isBackupKey ? 'Restore with Backup Key'
                              : 'Restore Keys',
                            style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 16)),
                  ),
                ),

                const SizedBox(height: 16),

                // Mode switcher links
                if (isCreate) ...[
                  TextButton(
                    onPressed: _submitting ? null : () {
                      setState(() { _mode = _GateMode.restore; _error = null; _passwordCtrl.clear(); _confirmCtrl.clear(); });
                    },
                    child: Text('I already have a sync password',
                      style: GoogleFonts.inter(color: AppTheme.brightNavy, fontSize: 13)),
                  ),
                ] else if (isBackupKey) ...[
                  TextButton(
                    onPressed: _submitting ? null : () {
                      setState(() { _mode = _GateMode.restore; _error = null; _backupKeyCtrl.clear(); });
                    },
                    child: Text('Use sync password instead',
                      style: GoogleFonts.inter(color: AppTheme.brightNavy, fontSize: 13)),
                  ),
                  TextButton(
                    onPressed: _submitting ? null : () {
                      setState(() { _mode = _GateMode.create; _error = null; _backupKeyCtrl.clear(); });
                    },
                    child: Text('Create a new sync password',
                      style: GoogleFonts.inter(color: AppTheme.brightNavy, fontSize: 13)),
                  ),
                ] else ...[
                  TextButton(
                    onPressed: _submitting ? null : () {
                      setState(() { _mode = _GateMode.backupKey; _error = null; _passwordCtrl.clear(); });
                    },
                    child: Text('Use backup key instead',
                      style: GoogleFonts.inter(color: AppTheme.brightNavy, fontSize: 13)),
                  ),
                  TextButton(
                    onPressed: _submitting ? null : () {
                      setState(() { _mode = _GateMode.create; _error = null; _passwordCtrl.clear(); });
                    },
                    child: Text('Create a new sync password',
                      style: GoogleFonts.inter(color: AppTheme.brightNavy, fontSize: 13)),
                  ),
                ],

                const SizedBox(height: 24),

                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.navyBlue.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      _infoRow(Icons.sync, 'Keys sync automatically after setup'),
                      const SizedBox(height: 8),
                      _infoRow(Icons.visibility_off, 'We never see your password'),
                      const SizedBox(height: 8),
                      _infoRow(Icons.warning_amber, 'Lose your password = lose your keys'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── One-Time Recovery Key Screen ────────────────────────────────────

  Widget _buildRecoveryScreen() {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.vpn_key, size: 48, color: Color(0xFF4CAF50)),
                ),
                const SizedBox(height: 24),

                Text('Your Recovery Key',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.literata(
                    fontWeight: FontWeight.w700, color: AppTheme.navyBlue, fontSize: 22)),
                const SizedBox(height: 12),

                Text(
                  'This is your emergency backup key. Save it now — '
                  'you will never see it again.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 14, height: 1.5),
                ),
                const SizedBox(height: 28),

                // Recovery key display
                GestureDetector(
                  onTap: _copyKey,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppTheme.cardSurface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.brightNavy.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      children: [
                        Text(_recoveryKey ?? '',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.navyBlue,
                            letterSpacing: 1.2,
                            height: 1.8,
                          )),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.copy, size: 14, color: AppTheme.brightNavy),
                            const SizedBox(width: 6),
                            Text(_keyCopied ? 'Copied!' : 'Tap to copy',
                              style: GoogleFonts.inter(
                                color: _keyCopied ? const Color(0xFF4CAF50) : AppTheme.brightNavy,
                                fontSize: 12)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Download as .txt
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _downloadKey,
                    icon: const Icon(Icons.save_alt, size: 18),
                    label: const Text('Download as file'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.brightNavy,
                      side: BorderSide(color: AppTheme.brightNavy.withValues(alpha: 0.3)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Continue
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _keyCopied ? _finish : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _keyCopied ? const Color(0xFF4CAF50) : Colors.grey.shade300,
                      foregroundColor: SojornColors.basicWhite,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: Text('Continue to Sojorn',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 16)),
                  ),
                ),

                if (!_keyCopied) ...[
                  const SizedBox(height: 8),
                  Text('Copy or download your key to continue',
                    style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 12)),
                ],

                const SizedBox(height: 24),

                // Warning
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber, size: 20, color: Colors.orange),
                      const SizedBox(width: 10),
                      Expanded(child: Text(
                        'This key will not be shown again. If you lose both your '
                        'sync password and this key, your encrypted data is gone forever.',
                        style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 12, height: 1.4),
                      )),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppTheme.navyBlue.withValues(alpha: 0.5)),
        const SizedBox(width: 10),
        Expanded(child: Text(text,
          style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 12))),
      ],
    );
  }
}
