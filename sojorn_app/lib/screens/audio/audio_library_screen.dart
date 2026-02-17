import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../config/api_config.dart';
import '../../providers/api_provider.dart';

/// Result returned when the user picks an audio track.
class AudioTrack {
  final String path;   // local file path OR network URL (feed directly to ffmpeg)
  final String title;

  const AudioTrack({required this.path, required this.title});
}

/// Two-tab screen for picking background audio.
///
/// Tab 1 (Device): opens the file picker for local audio files.
/// Tab 2 (Library): browses the Funkwhale library via the Go proxy.
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

  Future<void> _fetchTracks(String q) async {
    setState(() { _loading = true; _unavailable = false; });
    try {
      final api = ref.read(apiServiceProvider);
      final data = await api.callGoApi('/audio/library', method: 'GET', queryParams: {'q': q});
      final results = (data['results'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      setState(() {
        _tracks = results;
        // 503 is returned as an empty list with an "error" key
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
    final artist = (track['artist']?['name'] as String?) ?? '';
    final displayTitle = artist.isNotEmpty ? '$title — $artist' : title;
    final listenUrl = '${ApiConfig.baseUrl}/audio/library/$id/listen';
    Navigator.of(context).pop(AudioTrack(path: listenUrl, title: displayTitle));
  }

  Future<void> _pickDeviceAudio() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: false,
    );
    if (result != null && result.files.isNotEmpty && mounted) {
      final file = result.files.first;
      final path = file.path;
      if (path != null) {
        Navigator.of(context).pop(AudioTrack(
          path: path,
          title: file.name,
        ));
      }
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
              hintText: 'Search tracks...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _searchController.clear();
                  _fetchTracks('');
                },
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            ),
            textInputAction: TextInputAction.search,
            onSubmitted: _fetchTracks,
          ),
        ),
        Expanded(child: _libraryBody()),
      ],
    );
  }

  Widget _libraryBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_unavailable) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 48, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'Music library coming soon',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 8),
              Text(
                'Use the Device tab to add your own audio, or check back after the library is deployed.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
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
        final artist = (track['artist']?['name'] as String?) ?? '';
        final duration = track['duration'] as int? ?? 0;
        final mins = (duration ~/ 60).toString().padLeft(2, '0');
        final secs = (duration % 60).toString().padLeft(2, '0');
        final isPreviewing = _previewingId == id;

        return ListTile(
          leading: const Icon(Icons.music_note),
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('$artist  •  $mins:$secs', style: const TextStyle(fontSize: 12)),
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
          const Icon(Icons.folder_open, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text('Pick an audio file from your device',
              style: TextStyle(fontSize: 16)),
          const SizedBox(height: 8),
          const Text('MP3, AAC, WAV, FLAC and more',
              style: TextStyle(color: Colors.grey)),
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
