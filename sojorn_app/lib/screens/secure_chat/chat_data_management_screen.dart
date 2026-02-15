import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/chat_backup_manager.dart';
import '../../services/local_key_backup_service.dart';
import '../../services/simple_e2ee_service.dart';
import '../../services/local_message_store.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../security/encryption_hub_screen.dart';

class ChatDataManagementScreen extends StatefulWidget {
  const ChatDataManagementScreen({super.key});

  @override
  State<ChatDataManagementScreen> createState() => _ChatDataManagementScreenState();
}

class _ChatDataManagementScreenState extends State<ChatDataManagementScreen> {
  final ChatBackupManager _backupManager = ChatBackupManager.instance;
  final SimpleE2EEService _e2ee = SimpleE2EEService();

  bool _isLoading = true;
  bool _isBackupEnabled = false;
  bool _hasPassword = false;
  DateTime? _lastBackupAt;
  int _localMessageCount = 0;
  int _lastBackupMsgCount = 0;

  bool _isBackingUp = false;
  bool _isRestoring = false;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final enabled = await _backupManager.isEnabled;
    final hasPw = await _backupManager.hasPassword;
    final lastAt = await _backupManager.lastBackupAt;
    final msgCount = await _backupManager.getLocalMessageCount();
    final lastCount = await _backupManager.lastBackupMessageCount;

    if (!mounted) return;
    setState(() {
      _isBackupEnabled = enabled;
      _hasPassword = hasPw;
      _lastBackupAt = lastAt;
      _localMessageCount = msgCount;
      _lastBackupMsgCount = lastCount;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg,
      appBar: AppBar(
        backgroundColor: AppTheme.scaffoldBg,
        elevation: 0,
        surfaceTintColor: SojornColors.transparent,
        title: Text(
          'Chat Data & Backup',
          style: GoogleFonts.literata(
            fontWeight: FontWeight.w600,
            color: AppTheme.navyBlue,
            fontSize: 20,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadStatus,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildStatusCard(),
                  const SizedBox(height: 20),
                  if (!_isBackupEnabled) _buildSetupCard(),
                  if (_isBackupEnabled) ...[
                    _buildBackupActions(),
                    const SizedBox(height: 20),
                  ],
                  _buildRestoreCard(),
                  const SizedBox(height: 20),
                  _buildLocalFileSection(),
                  const SizedBox(height: 20),
                  _buildDataManagement(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  // ── Status Card ──────────────────────────────────────

  Widget _buildStatusCard() {
    final isHealthy = _isBackupEnabled && _hasPassword;
    final icon = isHealthy ? Icons.cloud_done_rounded : Icons.cloud_off_rounded;
    final color = isHealthy ? const Color(0xFF4CAF50) : AppTheme.textDisabled;
    final label = isHealthy ? 'Auto-Backup Active' : 'Backup Not Set Up';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isHealthy
              ? [AppTheme.brightNavy.withValues(alpha: 0.08), AppTheme.brightNavy.withValues(alpha: 0.03)]
              : [AppTheme.cardSurface, AppTheme.cardSurface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isHealthy ? AppTheme.brightNavy.withValues(alpha: 0.2) : AppTheme.border,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        color: AppTheme.navyBlue,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isHealthy
                          ? 'Messages and private group keys are encrypted and backed up.'
                          : 'Set up backup to protect your messages and keys.',
                      style: GoogleFonts.inter(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (isHealthy) ...[
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildStat(
                  Icons.message_rounded,
                  '$_localMessageCount',
                  'Local Messages',
                ),
                _buildStat(
                  Icons.access_time_rounded,
                  _lastBackupAt != null ? _formatTimeAgo(_lastBackupAt!) : 'Never',
                  'Last Backup',
                ),
                _buildStat(
                  Icons.cloud_upload_rounded,
                  '$_lastBackupMsgCount',
                  'Backed Up',
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStat(IconData icon, String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 18, color: AppTheme.brightNavy.withValues(alpha: 0.6)),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w700,
              color: AppTheme.navyBlue,
              fontSize: 14,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.inter(
              color: AppTheme.textSecondary,
              fontSize: 11,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ── Setup Card (shown when backup is not enabled) ────

  Widget _buildSetupCard() {
    return _card(
      icon: Icons.shield_rounded,
      iconColor: AppTheme.brightNavy,
      title: 'Enable Cloud Backup',
      subtitle: _hasPassword
          ? 'Your vault passphrase encrypts messages and private group keys. '
              'No extra password needed.'
          : 'Set up the Encryption Hub first — your vault passphrase will encrypt '
              'messages, chat keys, and private group keys automatically.',
      child: Column(
        children: [
          const SizedBox(height: 16),
          if (_hasPassword)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _enableBackup,
                icon: const Icon(Icons.cloud_upload_rounded),
                label: const Text('Enable Auto-Backup'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.brightNavy,
                  foregroundColor: SojornColors.basicWhite,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const EncryptionHubScreen()),
                  );
                  // Refresh status after returning from Encryption Hub
                  _loadStatus();
                },
                icon: const Icon(Icons.lock_outline),
                label: const Text('Open Encryption Hub'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.royalPurple,
                  foregroundColor: SojornColors.basicWhite,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Backup Actions (shown when backup is enabled) ────

  Widget _buildBackupActions() {
    return _card(
      icon: Icons.cloud_sync_rounded,
      iconColor: AppTheme.brightNavy,
      title: 'Backup Controls',
      subtitle: null,
      child: Column(
        children: [
          const SizedBox(height: 8),
          _actionTile(
            icon: Icons.cloud_upload_rounded,
            title: 'Backup Now',
            subtitle: 'Force an immediate encrypted backup',
            trailing: _isBackingUp
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Icons.chevron_right, color: AppTheme.textDisabled),
            onTap: _isBackingUp ? null : _forceBackup,
          ),
          const Divider(height: 1),
          _actionTile(
            icon: Icons.cloud_off_rounded,
            title: 'Disable Auto-Backup',
            subtitle: 'Stop automatic cloud backups',
            trailing: Icon(Icons.chevron_right, color: AppTheme.error),
            onTap: _confirmDisableBackup,
            isDestructive: true,
          ),
        ],
      ),
    );
  }

  // ── Restore Card ─────────────────────────────────────

  Widget _buildRestoreCard() {
    return _card(
      icon: Icons.restore_rounded,
      iconColor: AppTheme.royalPurple,
      title: 'Restore from Cloud',
      subtitle: 'Recover your encrypted messages from a previous backup. '
          'You\'ll need your vault passphrase (or the original backup password).',
      child: Column(
        children: [
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isRestoring ? null : _showRestoreDialog,
              icon: _isRestoring
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_download_rounded),
              label: Text(_isRestoring ? 'Restoring...' : 'Restore Backup'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.royalPurple,
                side: BorderSide(color: AppTheme.royalPurple.withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Local File Section ───────────────────────────────

  Widget _buildLocalFileSection() {
    return _card(
      icon: Icons.save_alt_rounded,
      iconColor: AppTheme.navyBlue,
      title: 'Local File Backup',
      subtitle: 'Export chat keys, private group keys, and messages to a password-protected file.',
      child: Column(
        children: [
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _exportToFile,
                  icon: const Icon(Icons.file_download, size: 18),
                  label: const Text('Export'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.navyBlue,
                    side: BorderSide(color: AppTheme.border),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _importFromFile,
                  icon: const Icon(Icons.file_upload, size: 18),
                  label: const Text('Import'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.navyBlue,
                    side: BorderSide(color: AppTheme.border),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Data Management ──────────────────────────────────

  Widget _buildDataManagement() {
    return _card(
      icon: Icons.storage_rounded,
      iconColor: AppTheme.error,
      title: 'Data Management',
      subtitle: null,
      child: Column(
        children: [
          const SizedBox(height: 8),
          _actionTile(
            icon: Icons.delete_sweep_rounded,
            title: 'Clear Local Messages',
            subtitle: '$_localMessageCount messages stored locally',
            trailing: Icon(Icons.chevron_right, color: AppTheme.error),
            onTap: _confirmClearMessages,
            isDestructive: true,
          ),
          const Divider(height: 1),
          _actionTile(
            icon: Icons.vpn_key_rounded,
            title: 'Reset Encryption Keys',
            subtitle: 'Generate new identity (breaks existing chats)',
            trailing: Icon(Icons.chevron_right, color: AppTheme.error),
            onTap: _confirmResetKeys,
            isDestructive: true,
          ),
        ],
      ),
    );
  }

  // ── Shared Widgets ───────────────────────────────────

  Widget _card({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.literata(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.navyBlue,
                    fontSize: 17,
                  ),
                ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: GoogleFonts.inter(
                color: AppTheme.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
          child,
        ],
      ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget trailing,
    VoidCallback? onTap,
    bool isDestructive = false,
  }) {
    final color = isDestructive ? AppTheme.error : AppTheme.navyBlue;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: color.withValues(alpha: 0.7), size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w500,
                      color: color,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      color: AppTheme.textDisabled,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }

  // ── Dialogs & Actions ────────────────────────────────

  Future<void> _enableBackup() async {
    setState(() => _isBackingUp = true);
    try {
      await _backupManager.enable();
      await _loadStatus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Auto-backup enabled! Using your vault passphrase.'),
            backgroundColor: Color(0xFF4CAF50),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Setup failed: $e'), backgroundColor: SojornColors.destructive),
        );
      }
    } finally {
      if (mounted) setState(() => _isBackingUp = false);
    }
  }

  Future<void> _forceBackup() async {
    setState(() => _isBackingUp = true);
    try {
      await _backupManager.forceBackup();
      await _loadStatus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup complete!'), backgroundColor: Color(0xFF4CAF50)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup failed: $e'), backgroundColor: SojornColors.destructive),
        );
      }
    } finally {
      if (mounted) setState(() => _isBackingUp = false);
    }
  }

  // Password is now managed by the Encryption Hub (KeyVaultService).
  // No separate change password dialog needed.

  Future<void> _confirmDisableBackup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disable Auto-Backup?'),
        content: const Text(
          'Your existing cloud backups will remain but no new backups will be made.'
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('Disable'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await _backupManager.disable();
    await _loadStatus();
  }

  Future<void> _showRestoreDialog() async {
    final controller = TextEditingController();

    final password = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore from Cloud'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Enter your vault passphrase (or the original backup password if you set one separately).',
              style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Vault Passphrase',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.royalPurple,
              foregroundColor: SojornColors.basicWhite,
            ),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (password == null || password.isEmpty) return;
    setState(() => _isRestoring = true);
    try {
      final result = await _backupManager.restoreFromCloud(password);
      await _loadStatus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Restored ${result['restored_keys']} chat keys, '
              '${result['restored_messages']} messages'
              '${result['restored_capsule_keys'] == true ? ', and private group keys' : ''}!',
            ),
            backgroundColor: const Color(0xFF4CAF50),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restore failed: $e'), backgroundColor: SojornColors.destructive),
        );
      }
    } finally {
      if (mounted) setState(() => _isRestoring = false);
    }
  }

  Future<void> _exportToFile() async {
    final controller = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Export Backup File'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Choose a password to protect the exported file. '
              'Includes chat keys, private group keys, and messages.',
              style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'File Password',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Export')),
        ],
      ),
    );

    if (password == null || password.isEmpty) return;
    try {
      final backup = await LocalKeyBackupService.createEncryptedBackup(
        password: password,
        e2eeService: _e2ee,
        includeMessages: true,
        includeKeys: true,
      );
      final path = await LocalKeyBackupService.saveBackupToDevice(backup);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exported to: $path'), backgroundColor: const Color(0xFF4CAF50)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'), backgroundColor: SojornColors.destructive),
        );
      }
    }
  }

  Future<void> _importFromFile() async {
    try {
      final backup = await LocalKeyBackupService.loadBackupFromDevice();

      if (!mounted) return;
      final controller = TextEditingController();
      final password = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Enter File Password'),
          content: TextField(
            controller: controller,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Password',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Import')),
          ],
        ),
      );

      if (password == null || password.isEmpty) return;
      final result = await LocalKeyBackupService.restoreFromBackup(
        backup: backup,
        password: password,
        e2eeService: _e2ee,
      );
      await _loadStatus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Imported ${result['restored_keys']} chat keys, '
              '${result['restored_messages']} messages'
              '${result['restored_capsule_keys'] == true ? ', and private group keys' : ''}!',
            ),
            backgroundColor: const Color(0xFF4CAF50),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e'), backgroundColor: SojornColors.destructive),
        );
      }
    }
  }

  Future<void> _confirmClearMessages() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Local Messages?'),
        content: Text(
          'This will delete $_localMessageCount messages from this device. '
          'Cloud backups will not be affected.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await _backupManager.clearLocalMessages();
    await _loadStatus();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Local messages cleared.')),
      );
    }
  }

  Future<void> _confirmResetKeys() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Encryption Keys?'),
        content: const Text(
          'This generates a new encryption identity. All existing conversations will break '
          'and cannot be decrypted. Only do this if you cannot restore from a backup.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('Reset Keys'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await _e2ee.forceResetBrokenKeys();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Encryption keys reset. New identity generated.')),
      );
    }
  }

  // ── Helpers ──────────────────────────────────────────

  String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
