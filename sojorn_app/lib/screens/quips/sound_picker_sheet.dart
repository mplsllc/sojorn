// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/sounds_provider.dart';
import '../../screens/audio/audio_library_screen.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';

/// Show the sound picker as a modal bottom sheet.
/// Returns the selected [AudioTrack] or null if dismissed.
Future<AudioTrack?> showSoundPicker(BuildContext context) {
  return showModalBottomSheet<AudioTrack>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _SoundPickerSheet(),
  );
}

class _SoundPickerSheet extends ConsumerStatefulWidget {
  const _SoundPickerSheet();

  @override
  ConsumerState<_SoundPickerSheet> createState() => _SoundPickerSheetState();
}

class _SoundPickerSheetState extends ConsumerState<_SoundPickerSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(soundsProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _select(SoundItem sound) {
    ref.read(soundsProvider.notifier).recordUse(sound.id);
    Navigator.pop(
      context,
      AudioTrack(id: sound.id, path: sound.audioUrl, title: sound.title),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(soundsProvider);

    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(SojornRadii.modal)),
      ),
      child: Column(
        children: [
          // Drag handle
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Text('Add Sound', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Tab bar
          TabBar(
            controller: _tabs,
            labelColor: AppTheme.brightNavy,
            unselectedLabelColor: Colors.grey,
            indicatorColor: AppTheme.brightNavy,
            tabs: const [
              Tab(text: 'Trending'),
              Tab(text: 'Library'),
            ],
          ),

          // Content
          Expanded(
            child: state.loading
                ? const Center(child: CircularProgressIndicator())
                : state.error != null
                    ? _ErrorView(
                        message: state.error!,
                        onRetry: () => ref.read(soundsProvider.notifier).load(),
                      )
                    : TabBarView(
                        controller: _tabs,
                        children: [
                          _SoundList(sounds: state.trending, onSelect: _select, emptyLabel: 'No trending sounds yet.'),
                          _SoundList(sounds: state.library, onSelect: _select, emptyLabel: 'No library tracks yet.'),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}

class _SoundList extends StatelessWidget {
  final List<SoundItem> sounds;
  final void Function(SoundItem) onSelect;
  final String emptyLabel;

  const _SoundList({required this.sounds, required this.onSelect, required this.emptyLabel});

  @override
  Widget build(BuildContext context) {
    if (sounds.isEmpty) {
      return Center(child: Text(emptyLabel, style: TextStyle(color: Colors.grey[500], fontSize: 14)));
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: sounds.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
      itemBuilder: (_, i) => _SoundRow(sound: sounds[i], onSelect: onSelect),
    );
  }
}

class _SoundRow extends StatelessWidget {
  final SoundItem sound;
  final void Function(SoundItem) onSelect;

  const _SoundRow({required this.sound, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final isLibrary = sound.bucket == 'library';
    return ListTile(
      onTap: () => onSelect(sound),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: isLibrary ? const Color(0xFFF3E8FF) : const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(SojornRadii.sm),
        ),
        child: Icon(
          isLibrary ? Icons.library_music_rounded : Icons.music_note_rounded,
          color: isLibrary ? const Color(0xFF9333EA) : AppTheme.brightNavy,
          size: 22,
        ),
      ),
      title: Text(
        sound.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        isLibrary ? 'Sojorn Library' : '${sound.useCount} uses',
        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
      ),
      trailing: sound.formattedDuration.isNotEmpty
          ? Text(
              sound.formattedDuration,
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            )
          : null,
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 40, color: Colors.grey),
            const SizedBox(height: 12),
            Text('Could not load sounds', style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Text(message, style: TextStyle(color: Colors.grey[400], fontSize: 12), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
