// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../../config/api_config.dart';
import '../../providers/api_provider.dart';
import '../../theme/app_theme.dart';

/// Result returned when the user picks an audio track.
class AudioTrack {
  final String path;   // local file path OR network URL (feed directly to ffmpeg)
  final String title;

  const AudioTrack({required this.path, required this.title});
}

/// Two-tab screen for picking background audio.
///
/// Tab 1 (Device): opens the file picker for local audio files.
/// Tab 2 (Library): browses the Freesound library via the Go proxy.
///
/// Navigator.push returns an [AudioTrack] when the user picks a track,
/// or null if they cancelled.
class AudioLibraryScreen extends ConsumerStatefulWidget {
  const AudioLibraryScreen({super.key});

  @override
  ConsumerState<AudioLibraryScreen> createState() => _AudioLibraryScreenState();
}

class _AudioLibraryScreenState extends ConsumerState<AudioLibraryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // Library tab state
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _tracks = [];
  bool _loading = false;
  bool _unavailable = false;
  String? _previewingId;
  VideoPlayerController? _previewController;
  String? _activeTag; // tag filter for browsing categories

  static const _popularTags = [
    'ambient', 'nature', 'electronic', 'percussion', 'piano',
    'guitar', 'bass', 'synth', 'vocal', 'cinematic', 'lofi',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchTracks('');
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _previewController?.dispose();
    super.dispose();
  }

  Future<void> _fetchTracks(String q, {String? tag}) async {
    setState(() { _loading = true; _unavailable = false; });
    try {
      final api = ref.read(apiServiceProvider);
      final params = <String, String>{'q': q};
      if (tag != null && tag.isNotEmpty) params['tags'] = tag;
      final data = await api.callGoApi('/audio/library', method: 'GET', queryParams: params);
      // Freesound proxy returns "tracks" array
      final results = (data['tracks'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      setState(() {
        _tracks = results;
        _unavailable = data['error'] != null && results.isEmpty;
      });
    } catch (_) {
      setState(() { _unavailable = true; _tracks = []; });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _togglePreview(Map<String, dynamic> track) async {
    final id = track['id']?.toString() ?? '';
    if (_previewingId == id) {
      // Stop preview
      await _previewController?.pause();
      await _previewController?.dispose();
      setState(() { _previewController = null; _previewingId = null; });
      return;
    }

    await _previewController?.dispose();
    setState(() { _previewingId = id; _previewController = null; });

    // Use the Go proxy listen URL — VideoPlayerController handles it as audio
    final listenUrl = '${ApiConfig.baseUrl}/audio/library/$id/listen';
    final controller = VideoPlayerController.networkUrl(Uri.parse(listenUrl));
    try {
      await controller.initialize();
      await controller.play();
      if (mounted) setState(() => _previewController = controller);
    } catch (_) {
      await controller.dispose();
      if (mounted) {
        setState(() { _previewingId = null; });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Preview unavailable for this track')),
        );
      }
    }
  }

  void _useTrack(Map<String, dynamic> track) {
    final id = track['id']?.toString() ?? '';
    final title = (track['title'] as String?) ?? 'Unknown Track';
    final artist = (track['artist'] as String?) ?? '';
    final displayTitle = artist.isNotEmpty ? '$title — $artist' : title;
    // Use listen_url from response if available, otherwise build it
    final listenUrl = (track['listen_url'] as String?) != null
        ? '${ApiConfig.baseUrl}${track['listen_url']}'
        : '${ApiConfig.baseUrl}/audio/library/$id/listen';
    Navigator.of(context).pop(AudioTrack(path: listenUrl, title: displayTitle));
  }

  Future<void> _pickDeviceAudio() async {
    // withData: true ensures bytes are available for Android content:// URIs
    // where file.path is null (modern Android scoped storage).
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty || !mounted) return;

    final file = result.files.first;
    var path = file.path;

    // On Android, path is null for content:// URIs — copy bytes to a temp file.
    if (path == null && file.bytes != null) {
      try {
        final dir = await getTemporaryDirectory();
        final tmp = File('${dir.path}/${file.name}');
        await tmp.writeAsBytes(file.bytes!);
        path = tmp.path;
      } catch (_) {
        return;
      }
    }

    if (path != null && mounted) {
      Navigator.of(context).pop(AudioTrack(path: path, title: file.name));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Music'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.smartphone), text: 'Device'),
            Tab(icon: Icon(Icons.library_music), text: 'Library'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _DeviceTab(onPick: _pickDeviceAudio),
          _libraryTab(),
        ],
      ),
    );
  }

  Widget _libraryTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search sounds...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _searchController.clear();
                  _activeTag = null;
                  _fetchTracks('');
                },
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            ),
            textInputAction: TextInputAction.search,
            onSubmitted: (q) => _fetchTracks(q, tag: _activeTag),
          ),
        ),
        // Tag chips for browsing categories
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _popularTags.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (context, i) {
              final tag = _popularTags[i];
              final isActive = _activeTag == tag;
              return FilterChip(
                label: Text(tag, style: TextStyle(fontSize: 12, fontWeight: isActive ? FontWeight.w700 : FontWeight.w500)),
                selected: isActive,
                onSelected: (selected) {
                  setState(() => _activeTag = selected ? tag : null);
                  _fetchTracks(_searchController.text, tag: selected ? tag : null);
                },
                visualDensity: VisualDensity.compact,
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Expanded(child: _libraryBody()),
      ],
    );
  }

  Widget _libraryBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_unavailable) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 48, color: AppTheme.textDisabled),
              const SizedBox(height: 16),
              const Text(
                'Sound library unavailable',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                'Use the Device tab to add your own audio, or try again later.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textDisabled),
              ),
            ],
          ),
        ),
      );
    }
    if (_tracks.isEmpty) {
      return const Center(child: Text('No tracks found'));
    }
    return ListView.separated(
      itemCount: _tracks.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final track = _tracks[i];
        final id = track['id']?.toString() ?? '';
        final title = (track['title'] as String?) ?? 'Unknown';
        final artist = (track['artist'] as String?) ?? '';
        final durationSec = ((track['duration'] as num?) ?? 0).toInt();
        final mins = (durationSec ~/ 60).toString().padLeft(2, '0');
        final secs = (durationSec % 60).toString().padLeft(2, '0');
        final license = (track['license'] as String?) ?? '';
        final isPreviewing = _previewingId == id;

        return ListTile(
          leading: const Icon(Icons.music_note),
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            [if (artist.isNotEmpty) artist, '$mins:$secs', if (license.isNotEmpty) license.split('/').last].join('  •  '),
            style: const TextStyle(fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(isPreviewing ? Icons.stop : Icons.play_arrow),
                tooltip: isPreviewing ? 'Stop' : 'Preview',
                onPressed: () => _togglePreview(track),
              ),
              TextButton(
                onPressed: () => _useTrack(track),
                child: const Text('Use'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DeviceTab extends StatelessWidget {
  final VoidCallback onPick;
  const _DeviceTab({required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_open, size: 64, color: AppTheme.textDisabled),
          const SizedBox(height: 16),
          const Text('Pick an audio file from your device',
              style: TextStyle(fontSize: 16)),
          const SizedBox(height: 8),
          Text('MP3, AAC, WAV, FLAC and more',
              style: TextStyle(color: AppTheme.textDisabled)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.audio_file),
            label: const Text('Browse Files'),
          ),
        ],
      ),
    );
  }
}
