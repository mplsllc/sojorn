import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/board_entry.dart';
import '../../providers/api_provider.dart';
import '../../services/image_upload_service.dart';
import '../../theme/tokens.dart';
import '../../theme/app_theme.dart';

/// Compose sheet for the standalone neighborhood board.
/// Creates board_entries — completely separate from posts/beacons.
class CreateBoardPostSheet extends ConsumerStatefulWidget {
  final double centerLat;
  final double centerLong;
  final Function(BoardEntry entry) onEntryCreated;

  const CreateBoardPostSheet({
    super.key,
    required this.centerLat,
    required this.centerLong,
    required this.onEntryCreated,
  });

  @override
  ConsumerState<CreateBoardPostSheet> createState() => _CreateBoardPostSheetState();
}

class _CreateBoardPostSheetState extends ConsumerState<CreateBoardPostSheet> {
  final ImageUploadService _imageUploadService = ImageUploadService();
  final _bodyController = TextEditingController();

  BoardTopic _selectedTopic = BoardTopic.community;
  bool _isSubmitting = false;
  bool _isUploadingImage = false;
  File? _selectedImage;
  String? _uploadedImageUrl;

  static const _topics = BoardTopic.values;

  @override
  void dispose() {
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    setState(() => _isUploadingImage = true);
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      if (image == null) {
        setState(() => _isUploadingImage = false);
        return;
      }
      final file = File(image.path);
      setState(() => _selectedImage = file);
      final imageUrl = await _imageUploadService.uploadImage(file);
      if (mounted) setState(() { _uploadedImageUrl = imageUrl; _isUploadingImage = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _isUploadingImage = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not upload photo: $e')));
      }
    }
  }

  void _removeImage() {
    setState(() { _selectedImage = null; _uploadedImageUrl = null; });
  }

  Future<void> _submit() async {
    final body = _bodyController.text.trim();
    if (body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Write something to share with your neighbors.')));
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final apiService = ref.read(apiServiceProvider);
      final data = await apiService.createBoardEntry(
        body: body,
        imageUrl: _uploadedImageUrl,
        topic: _selectedTopic.value,
        lat: widget.centerLat,
        long: widget.centerLong,
      );
      if (mounted) {
        final entry = BoardEntry.fromJson(data['entry'] as Map<String, dynamic>);
        widget.onEntryCreated(entry);
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not create post: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        left: 20, right: 20, top: 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: AppTheme.navyBlue.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(2)),
            )),
            const SizedBox(height: 16),

            // Header
            Row(
              children: [
                Icon(Icons.forum, color: AppTheme.brightNavy, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Post to Board', style: TextStyle(color: AppTheme.navyBlue, fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close, color: SojornColors.textDisabled),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Topic chips — horizontal scroll
            Text('Topic', style: TextStyle(color: AppTheme.navyBlue.withValues(alpha: 0.6), fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _topics.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final topic = _topics[i];
                  final isSelected = topic == _selectedTopic;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedTopic = topic),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: isSelected ? topic.color.withValues(alpha: 0.12) : AppTheme.scaffoldBg,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: isSelected ? topic.color : AppTheme.navyBlue.withValues(alpha: 0.1),
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(topic.icon, size: 14, color: isSelected ? topic.color : SojornColors.postContentLight),
                          const SizedBox(width: 5),
                          Text(topic.displayName, style: TextStyle(
                            color: isSelected ? topic.color : SojornColors.postContentLight,
                            fontSize: 12, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                          )),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            // Body
            TextFormField(
              controller: _bodyController,
              style: TextStyle(color: SojornColors.postContent, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Share with your neighborhood…',
                hintStyle: TextStyle(color: SojornColors.textDisabled),
                filled: true,
                fillColor: AppTheme.scaffoldBg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppTheme.navyBlue.withValues(alpha: 0.1))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppTheme.navyBlue.withValues(alpha: 0.1))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppTheme.brightNavy, width: 1)),
                counterStyle: TextStyle(color: SojornColors.textDisabled),
              ),
              maxLines: 4,
              maxLength: 500,
            ),
            const SizedBox(height: 10),

            // Photo
            if (_selectedImage != null) ...[
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(_selectedImage!, height: 120, width: double.infinity, fit: BoxFit.cover),
                  ),
                  Positioned(
                    top: 6, right: 6,
                    child: IconButton(
                      onPressed: _removeImage,
                      icon: const Icon(Icons.close, color: SojornColors.basicWhite, size: 18),
                      style: IconButton.styleFrom(backgroundColor: SojornColors.overlayDark, padding: const EdgeInsets.all(4)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ] else ...[
              GestureDetector(
                onTap: _isUploadingImage ? null : _pickImage,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.scaffoldBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.navyBlue.withValues(alpha: 0.1)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isUploadingImage)
                        SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.brightNavy))
                      else
                        Icon(Icons.add_photo_alternate, size: 18, color: SojornColors.textDisabled),
                      const SizedBox(width: 8),
                      Text(_isUploadingImage ? 'Uploading…' : 'Add photo',
                        style: TextStyle(color: SojornColors.textDisabled, fontSize: 13)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],

            // Submit
            SizedBox(
              width: double.infinity, height: 48,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.brightNavy,
                  foregroundColor: SojornColors.basicWhite,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  disabledBackgroundColor: AppTheme.brightNavy.withValues(alpha: 0.3),
                ),
                child: _isSubmitting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: SojornColors.basicWhite))
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.send, size: 16),
                          SizedBox(width: 8),
                          Text('Post', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
