import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/api_service.dart';
import '../../services/key_vault_service.dart';
import '../../services/simple_e2ee_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';

/// Simplified Encryption Hub.
///
/// Shows vault health, key status, manual sync button, and danger zone.
/// All backup/restore complexity is handled by the VaultSetupGate at
/// first launch and auto-sync in the background. The user should never
/// need to think about keys unless something is wrong.
class EncryptionHubScreen extends StatefulWidget {
  const EncryptionHubScreen({super.key});

  @override
  State<EncryptionHubScreen> createState() => _EncryptionHubScreenState();
}

class _EncryptionHubScreenState extends State<EncryptionHubScreen> {
  VaultStatus? _status;
  bool _loading = true;
  bool _syncing = false;
  int _encryptedConvCount = 0;
  int _encryptedCapsuleCount = 0;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait<dynamic>([
        KeyVaultService.instance.getVaultStatus(),
        ApiService.instance.getConversations(),
        ApiService.instance.fetchMyGroups(),
      ]);
      final status = results[0] as VaultStatus;
      final convs = results[1] as List<dynamic>;
      final groups = results[2] as List<Map<String, dynamic>>;
      final encryptedCapsules = groups.where((g) => g['is_encrypted'] == true).length;
      if (mounted) {
        setState(() {
          _status = status;
          _encryptedConvCount = convs.length;
          _encryptedCapsuleCount = encryptedCapsules;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    try {
      await KeyVaultService.instance.autoSync();
      await _loadStatus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Keys synced'), backgroundColor: Color(0xFF4CAF50)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed: $e'), backgroundColor: SojornColors.destructive));
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _confirmResetKeys() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardSurface,
        title: Text('Reset Encryption Keys?', style: GoogleFonts.literata(
          fontWeight: FontWeight.w600, color: AppTheme.navyBlue)),
        content: Text(
          'This generates a new encryption identity. All existing conversations '
          'will break and cannot be decrypted. Only do this if you cannot restore from a backup.',
          style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: AppTheme.brightNavy)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('Reset Keys'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final e2ee = SimpleE2EEService();
    await e2ee.resetIdentityKeys();
    await _loadStatus();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Encryption keys reset. New identity generated.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg,
      appBar: AppBar(
        backgroundColor: AppTheme.scaffoldBg,
        elevation: 0,
        surfaceTintColor: SojornColors.transparent,
        title: Text('Encryption',
          style: GoogleFonts.literata(fontWeight: FontWeight.w600, color: AppTheme.navyBlue, fontSize: 20)),
        leading: Navigator.of(context).canPop()
            ? IconButton(icon: Icon(Icons.arrow_back, color: AppTheme.navyBlue), onPressed: () => Navigator.pop(context))
            : null,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadStatus,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildStatusCard(),
                  const SizedBox(height: 16),
                  _buildStatsCard(),
                  const SizedBox(height: 16),
                  _buildKeysCard(),
                  const SizedBox(height: 16),
                  _buildSyncCard(),
                  const SizedBox(height: 16),
                  _buildSecurityInfoCard(),
                  const SizedBox(height: 16),
                  _buildDangerZone(),
                ],
              ),
            ),
    );
  }

  // ── Status Card ────────────────────────────────────────────────────

  Widget _buildStatusCard() {
    final isHealthy = _status?.isHealthy ?? false;
    final color = isHealthy ? const Color(0xFF4CAF50) : Colors.orange;
    final icon = isHealthy ? Icons.shield : Icons.warning_amber;
    final label = isHealthy ? 'Vault Secured' : 'Setup Required';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.15), color.withValues(alpha: 0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: GoogleFonts.literata(
                  fontWeight: FontWeight.w700, color: color, fontSize: 18)),
                const SizedBox(height: 4),
                Text(
                  isHealthy
                      ? 'All encryption keys are backed up and synced.'
                      : 'Your vault needs to be set up to protect your keys.',
                  style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 13, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Stats Card ─────────────────────────────────────────────────────

  Widget _buildStatsCard() {
    const accent = Color(0xFF4CAF50);
    return Card(
      color: AppTheme.cardSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.lock, color: accent, size: 20),
              const SizedBox(width: 10),
              Text('What\'s Protected', style: GoogleFonts.literata(
                fontWeight: FontWeight.w600, color: AppTheme.navyBlue, fontSize: 16)),
            ]),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _statTile(
                  icon: Icons.chat_bubble_outline,
                  value: '$_encryptedConvCount',
                  label: 'Encrypted\nConversations',
                  color: AppTheme.brightNavy,
                )),
                const SizedBox(width: 12),
                Expanded(child: _statTile(
                  icon: Icons.lock_outline,
                  value: '$_encryptedCapsuleCount',
                  label: 'Encrypted\nCapsules',
                  color: const Color(0xFF7B52AB),
                )),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statTile({required IconData icon, required String value, required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(value, style: GoogleFonts.literata(
            fontSize: 26, fontWeight: FontWeight.w700, color: color)),
          const SizedBox(height: 2),
          Text(label, style: GoogleFonts.inter(
            fontSize: 11, color: AppTheme.textSecondary, height: 1.3)),
        ],
      ),
    );
  }

  // ── Keys Status Card ───────────────────────────────────────────────

  Widget _buildKeysCard() {
    return Card(
      color: AppTheme.cardSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.vpn_key, color: AppTheme.brightNavy),
              const SizedBox(width: 10),
              Text('Your Keys', style: GoogleFonts.literata(
                fontWeight: FontWeight.w600, color: AppTheme.navyBlue, fontSize: 16)),
            ]),
            const SizedBox(height: 16),
            _keyStatusRow('Chat Identity Keys', _status?.chatKeysReady ?? false),
            const SizedBox(height: 8),
            _keyStatusRow('Capsule Keys', _status?.capsuleKeysExist ?? false),
            const SizedBox(height: 8),
            _keyStatusRow('Cloud Backup', _status?.serverBackupExists ?? false),
          ],
        ),
      ),
    );
  }

  Widget _keyStatusRow(String label, bool ok) {
    return Row(
      children: [
        Icon(ok ? Icons.check_circle : Icons.cancel,
          size: 18, color: ok ? const Color(0xFF4CAF50) : SojornColors.destructive),
        const SizedBox(width: 10),
        Text(label, style: GoogleFonts.inter(color: AppTheme.navyBlue, fontSize: 14)),
        const Spacer(),
        Text(ok ? 'Active' : 'Missing',
          style: GoogleFonts.inter(color: ok ? const Color(0xFF4CAF50) : SojornColors.destructive,
            fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }

  // ── Sync Card ──────────────────────────────────────────────────────

  Widget _buildSyncCard() {
    return Card(
      color: AppTheme.cardSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.sync, color: AppTheme.brightNavy),
              const SizedBox(width: 10),
              Text('Manual Sync', style: GoogleFonts.literata(
                fontWeight: FontWeight.w600, color: AppTheme.navyBlue, fontSize: 16)),
            ]),
            const SizedBox(height: 12),
            Text('Keys sync automatically. Use this if you want to force an immediate sync.',
              style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 13, height: 1.4)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _syncing ? null : _syncNow,
                icon: _syncing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.sync, size: 18),
                label: Text(_syncing ? 'Syncing...' : 'Sync Now'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.brightNavy,
                  side: BorderSide(color: AppTheme.brightNavy),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Security Info ──────────────────────────────────────────────────

  Widget _buildSecurityInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.navyBlue.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.security, size: 16, color: AppTheme.navyBlue.withValues(alpha: 0.6)),
            const SizedBox(width: 8),
            Text('How it works', style: GoogleFonts.inter(
              fontWeight: FontWeight.w600, color: AppTheme.navyBlue.withValues(alpha: 0.7), fontSize: 13)),
          ]),
          const SizedBox(height: 10),
          _infoLine('Your sync password never leaves this device'),
          _infoLine('Keys are encrypted with AES-256-GCM before upload'),
          _infoLine('The server stores only an opaque encrypted blob'),
          _infoLine('We cannot read your keys — zero knowledge'),
          _infoLine('Recovery key is shown once at setup and cannot be retrieved'),
        ],
      ),
    );
  }

  Widget _infoLine(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check, size: 14, color: Color(0xFF4CAF50)),
          const SizedBox(width: 8),
          Expanded(child: Text(text,
            style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 12, height: 1.4))),
        ],
      ),
    );
  }

  // ── Danger Zone ────────────────────────────────────────────────────

  Widget _buildDangerZone() {
    return Card(
      color: AppTheme.cardSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.warning_amber, color: AppTheme.error),
              const SizedBox(width: 10),
              Text('Danger Zone', style: GoogleFonts.literata(
                fontWeight: FontWeight.w600, color: AppTheme.error, fontSize: 16)),
            ]),
            const SizedBox(height: 12),
            Text('Reset your encryption identity. This will break all existing '
              'encrypted conversations permanently.',
              style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 13, height: 1.4)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _confirmResetKeys,
                icon: const Icon(Icons.vpn_key_rounded, size: 18),
                label: const Text('Reset Encryption Keys'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.error,
                  side: BorderSide(color: AppTheme.error.withValues(alpha: 0.4)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
