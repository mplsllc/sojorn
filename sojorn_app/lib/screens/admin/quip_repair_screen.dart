import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/media/ffmpeg.dart';
import 'package:path_provider/path_provider.dart';
import '../../services/image_upload_service.dart';
import '../../providers/api_provider.dart';

class QuipRepairScreen extends ConsumerStatefulWidget {
  const QuipRepairScreen({super.key});

  @override
  ConsumerState<QuipRepairScreen> createState() => _QuipRepairScreenState();
}

class _QuipRepairScreenState extends ConsumerState<QuipRepairScreen> {
  final ImageUploadService _uploadService = ImageUploadService();
  
  List<Map<String, dynamic>> _brokenQuips = [];
  bool _isLoading = false;
  bool _isRepairing = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _fetchBrokenQuips();
  }

  Future<void> _fetchBrokenQuips() async {
    setState(() => _isLoading = true);
    try {
      if (mounted) {
        setState(() {
          _brokenQuips = [];
          _statusMessage =
              'Quip repair is unavailable (Go API migration pending).';
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _repairQuip(Map<String, dynamic> quip) async {
    setState(() {
      _isRepairing = false;
      _statusMessage =
          'Quip repair is unavailable (Go API migration pending).';
    });
    return;

    try {
      final videoUrl = quip['video_url'] as String;
      if (videoUrl.isEmpty) throw "No Video URL";

      // Get signed URL for the video if needed (assuming public/signed handling elsewhere)
      // FFmpeg typically handles public URLs. If private R2, we need a signed URL.
      final api = ref.read(apiServiceProvider);
      final signedVideoUrl = await api.getSignedMediaUrl(videoUrl);
      if (signedVideoUrl == null) throw "Could not sign video URL";

      // Generate thumbnail
      final tempDir = await getTemporaryDirectory();
      final thumbPath = '${tempDir.path}/repair_thumb_${quip['id']}.jpg';
      
      // Use executeWithArguments to handle URLs with special characters safely.
      // Added reconnect flags for better handling of network streams.
      final session = await FFmpegKit.executeWithArguments([
        '-y',
        '-user_agent', 'SojornApp/1.0',
        '-reconnect', '1',
        '-reconnect_at_eof', '1',
        '-reconnect_streamed', '1',
        '-reconnect_delay_max', '4294',
        '-i', signedVideoUrl,
        '-ss', '00:00:01',
        '-vframes', '1',
        '-q:v', '5',
        thumbPath
      ]);
      
      final returnCode = await session.getReturnCode();
      if (!ReturnCode.isSuccess(returnCode)) {
         final logs = await session.getAllLogsAsString();
         // Print in chunks if it's too long for some logcats
         
         // Extract the last error message from logs if possible
         String errorDetail = "FFmpeg failed (Code: $returnCode)";
         if (logs != null && logs.contains('Error')) {
           errorDetail = logs.substring(logs.lastIndexOf('Error')).split('\n').first;
         }
         
         throw errorDetail;
      }

      final thumbFile = File(thumbPath);
      if (!await thumbFile.exists()) throw "Thumbnail file creation failed";

      // Upload
      final thumbUrl = await _uploadService.uploadImage(thumbFile);

      // Update Post (TODO: migrate to Go API)

      if (mounted) {
        setState(() {
          _brokenQuips.removeWhere((q) => q['id'] == quip['id']);
          _statusMessage = "Fixed ${quip['id']}";
        });
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Repair Failed: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRepairing = false;
        });
      }
    }
  }

  Future<void> _repairAll() async {
    // Clone list to avoid modification issues
    final list = List<Map<String, dynamic>>.from(_brokenQuips);
    for (final quip in list) {
      if (!mounted) break;
      await _repairQuip(quip);
    }
    if (mounted) {
      setState(() => _statusMessage = "Repair All Complete");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Repair Thumbnails"),
        actions: [
          if (_brokenQuips.isNotEmpty && !_isRepairing)
            IconButton(
              icon: const Icon(Icons.build),
              onPressed: _repairAll,
              tooltip: "Repair All",
            )
        ],
      ),
      body: Column(
        children: [
          if (_statusMessage != null)
            Container(
              padding: const EdgeInsets.all(8),
              width: double.infinity,
              color: const Color(0xFFFFC107).withValues(alpha: 0.2),
              child: Text(_statusMessage!, textAlign: TextAlign.center),
            ),
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator())
              : _brokenQuips.isEmpty 
                  ? const Center(child: Text("No missing thumbnails found."))
                  : ListView.builder(
                      itemCount: _brokenQuips.length,
                      itemBuilder: (context, index) {
                        final item = _brokenQuips[index];
                        return ListTile(
                          title: Text(item['body'] ?? "No Caption"),
                          subtitle: Text(item['created_at'].toString()),
                          trailing: _isRepairing 
                            ? null 
                            : IconButton(
                                icon: const Icon(Icons.refresh),
                                onPressed: () => _repairQuip(item),
                              ),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }
}
