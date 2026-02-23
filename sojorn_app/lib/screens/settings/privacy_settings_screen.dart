// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_scaffold.dart';
import '../../providers/api_provider.dart';
import '../../models/profile_privacy_settings.dart';

/// Comprehensive privacy settings screen for managing account privacy
class PrivacySettingsScreen extends ConsumerStatefulWidget {
  final ProfilePrivacySettings? initialSettings;

  const PrivacySettingsScreen({
    super.key,
    this.initialSettings,
  });

  @override
  ConsumerState<PrivacySettingsScreen> createState() =>
      _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState
    extends ConsumerState<PrivacySettingsScreen> {
  late ProfilePrivacySettings _settings;
  bool _isLoading = false;
  bool _isSaving = false;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _settings = widget.initialSettings ?? ProfilePrivacySettings();
    if (widget.initialSettings == null) {
      _loadSettings();
    }
  }

  void _setStateIfMounted(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  Future<void> _loadSettings() async {
    _setStateIfMounted(() => _isLoading = true);

    try {
      final api = ref.read(apiServiceProvider);
      final data = await api.callGoApi('/settings/privacy');
      
      _setStateIfMounted(() {
        _settings = ProfilePrivacySettings.fromJson(data);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load settings: $e')),
        );
      }
    } finally {
      _setStateIfMounted(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    _setStateIfMounted(() => _isSaving = true);

    try {
      final api = ref.read(apiServiceProvider);
      await api.callGoApi(
        '/settings/privacy',
        method: 'PATCH',
        body: _settings.toJson(),
      );

      _setStateIfMounted(() => _hasChanges = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Privacy settings saved'),
            backgroundColor: const Color(0xFF4CAF50),
          ),
        );
        Navigator.of(context).pop(_settings);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    } finally {
      _setStateIfMounted(() => _isSaving = false);
    }
  }

  void _updateSetting(void Function() update) {
    setState(() {
      update();
      _hasChanges = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_hasChanges) {
          final shouldLeave = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Unsaved Changes'),
              content: const Text('You have unsaved changes. Discard them?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Discard'),
                ),
              ],
            ),
          );
          return shouldLeave ?? false;
        }
        return true;
      },
      child: AppScaffold(
        title: 'Privacy Settings',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (_hasChanges)
            TextButton(
              onPressed: _isSaving ? null : _saveSettings,
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save', style: TextStyle(color: SojornColors.basicWhite)),
            ),
        ],
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSection(
                      title: 'Account Privacy',
                      icon: Icons.lock_outline,
                      children: [
                        _buildPrivateAccountTile(),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _buildSection(
                      title: 'Post Visibility',
                      icon: Icons.visibility_outlined,
                      children: [
                        _buildDefaultVisibilityTile(),
                        _buildAllowChainsTile(),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _buildSection(
                      title: 'Interactions',
                      icon: Icons.chat_bubble_outline,
                      children: [
                        _buildWhoCanMessageTile(),
                        _buildWhoCanCommentTile(),
                        _buildShowActivityStatusTile(),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _buildSection(
                      title: 'Discovery',
                      icon: Icons.search,
                      children: [
                        _buildShowInSearchTile(),
                        _buildShowSuggestedTile(),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _buildSection(
                      title: 'Circle (Close Friends)',
                      icon: Icons.favorite_outline,
                      children: [
                        _buildCircleInfoTile(),
                        _buildManageCircleTile(),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _buildSection(
                      title: 'Data & Privacy',
                      icon: Icons.shield_outlined,
                      children: [
                        _buildExportDataTile(),
                        _buildBlockedUsersTile(),
                      ],
                    ),
                    const SizedBox(height: 48),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: AppTheme.brightNavy),
            const SizedBox(width: 8),
            Text(
              title,
              style: AppTheme.headlineSmall.copyWith(
                color: AppTheme.brightNavy,
                fontSize: 16,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.cardSurface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _buildPrivateAccountTile() {
    return SwitchListTile(
      title: const Text('Private Account'),
      subtitle: const Text('Only approved followers can see your posts'),
      value: _settings.isPrivate,
      onChanged: (value) => _updateSetting(() => _settings.isPrivate = value),
      activeColor: AppTheme.brightNavy,
    );
  }

  Widget _buildDefaultVisibilityTile() {
    return ListTile(
      title: const Text('Default Post Visibility'),
      subtitle: Text(_getVisibilityLabel(_settings.defaultVisibility)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showVisibilityPicker(),
    );
  }

  Widget _buildAllowChainsTile() {
    return SwitchListTile(
      title: const Text('Allow Chains'),
      subtitle: const Text('Let others add to your posts'),
      value: _settings.allowChains,
      onChanged: (value) => _updateSetting(() => _settings.allowChains = value),
      activeColor: AppTheme.brightNavy,
    );
  }

  Widget _buildWhoCanMessageTile() {
    return ListTile(
      title: const Text('Who Can Message Me'),
      subtitle: Text(_getAudienceLabel(_settings.whoCanMessage)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showAudiencePicker(
        title: 'Who Can Message You',
        currentValue: _settings.whoCanMessage,
        onChanged: (value) => _updateSetting(() => _settings.whoCanMessage = value),
      ),
    );
  }

  Widget _buildWhoCanCommentTile() {
    return ListTile(
      title: const Text('Who Can Comment'),
      subtitle: Text(_getAudienceLabel(_settings.whoCanComment)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showAudiencePicker(
        title: 'Who Can Comment',
        currentValue: _settings.whoCanComment,
        onChanged: (value) => _updateSetting(() => _settings.whoCanComment = value),
      ),
    );
  }

  Widget _buildShowActivityStatusTile() {
    return SwitchListTile(
      title: const Text('Show Activity Status'),
      subtitle: const Text('Let others see when you\'re online'),
      value: _settings.showActivityStatus,
      onChanged: (value) =>
          _updateSetting(() => _settings.showActivityStatus = value),
      activeColor: AppTheme.brightNavy,
    );
  }

  Widget _buildShowInSearchTile() {
    return SwitchListTile(
      title: const Text('Show in Search'),
      subtitle: const Text('Allow others to find you in search'),
      value: _settings.showInSearch,
      onChanged: (value) =>
          _updateSetting(() => _settings.showInSearch = value),
      activeColor: AppTheme.brightNavy,
    );
  }

  Widget _buildShowSuggestedTile() {
    return SwitchListTile(
      title: const Text('Show in Suggestions'),
      subtitle: const Text('Appear in "Suggested for You"'),
      value: _settings.showInSuggestions,
      onChanged: (value) =>
          _updateSetting(() => _settings.showInSuggestions = value),
      activeColor: AppTheme.brightNavy,
    );
  }

  Widget _buildCircleInfoTile() {
    return ListTile(
      leading: Icon(Icons.info_outline, color: AppTheme.textSecondary),
      title: const Text('About Circle'),
      subtitle: const Text(
        'Share posts with only your closest friends. '
        'Circle members see posts marked "Circle" visibility.',
      ),
    );
  }

  Widget _buildManageCircleTile() {
    return ListTile(
      title: const Text('Manage Circle Members'),
      subtitle: const Text('Add or remove close friends'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        // TODO: Navigate to circle management screen
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Circle management coming soon')),
        );
      },
    );
  }

  Widget _buildExportDataTile() {
    return ListTile(
      title: const Text('Export My Data'),
      subtitle: const Text('Download your profile, posts, and connections'),
      trailing: const Icon(Icons.download_outlined),
      onTap: () => _exportData(),
    );
  }

  Widget _buildBlockedUsersTile() {
    return ListTile(
      title: const Text('Blocked Users'),
      subtitle: const Text('Manage users you\'ve blocked'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        // TODO: Navigate to blocked users screen
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Blocked users screen coming soon')),
        );
      },
    );
  }

  String _getVisibilityLabel(String visibility) {
    switch (visibility) {
      case 'public':
        return 'Public - Anyone can see';
      case 'followers':
        return 'Followers Only';
      case 'circle':
        return 'Circle Only';
      default:
        return visibility;
    }
  }

  String _getAudienceLabel(String audience) {
    switch (audience) {
      case 'everyone':
        return 'Everyone';
      case 'followers':
        return 'Followers Only';
      case 'mutuals':
        return 'Mutual Follows Only';
      case 'nobody':
        return 'Nobody';
      default:
        return audience;
    }
  }

  void _showVisibilityPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            Text('Default Post Visibility', style: AppTheme.headlineSmall),
            const SizedBox(height: 16),
            _buildVisibilityOption('public', 'Public', Icons.public),
            _buildVisibilityOption('followers', 'Followers Only', Icons.people),
            _buildVisibilityOption('circle', 'Circle Only', Icons.favorite),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildVisibilityOption(String value, String label, IconData icon) {
    final isSelected = _settings.defaultVisibility == value;
    return ListTile(
      leading: Icon(icon, color: isSelected ? AppTheme.brightNavy : null),
      title: Text(label),
      trailing: isSelected ? Icon(Icons.check, color: AppTheme.brightNavy) : null,
      onTap: () {
        _updateSetting(() => _settings.defaultVisibility = value);
        Navigator.pop(context);
      },
    );
  }

  void _showAudiencePicker({
    required String title,
    required String currentValue,
    required void Function(String) onChanged,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            Text(title, style: AppTheme.headlineSmall),
            const SizedBox(height: 16),
            _buildAudienceOption('everyone', 'Everyone', Icons.public, currentValue, onChanged),
            _buildAudienceOption('followers', 'Followers Only', Icons.people, currentValue, onChanged),
            _buildAudienceOption('mutuals', 'Mutual Follows', Icons.sync_alt, currentValue, onChanged),
            _buildAudienceOption('nobody', 'Nobody', Icons.block, currentValue, onChanged),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildAudienceOption(
    String value,
    String label,
    IconData icon,
    String currentValue,
    void Function(String) onChanged,
  ) {
    final isSelected = currentValue == value;
    return ListTile(
      leading: Icon(icon, color: isSelected ? AppTheme.brightNavy : null),
      title: Text(label),
      trailing: isSelected ? Icon(Icons.check, color: AppTheme.brightNavy) : null,
      onTap: () {
        onChanged(value);
        Navigator.pop(context);
      },
    );
  }

  Future<void> _exportData() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('Preparing your data...'),
          ],
        ),
      ),
    );

    try {
      final api = ref.read(apiServiceProvider);
      final data = await api.callGoApi('/users/me/export');

      Navigator.pop(context); // Close loading dialog

      // Show success and maybe allow saving
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Export Ready'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Your data export includes:'),
                const SizedBox(height: 12),
                Text('• Profile information', style: AppTheme.bodyMedium),
                Text('• ${data['posts']?.length ?? 0} posts', style: AppTheme.bodyMedium),
                Text('• ${data['following']?.length ?? 0} connections', style: AppTheme.bodyMedium),
                const SizedBox(height: 12),
                Text(
                  'The data has been prepared. In a production app, '
                  'this would be saved to your device.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      Navigator.pop(context); // Close loading dialog
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }
}
