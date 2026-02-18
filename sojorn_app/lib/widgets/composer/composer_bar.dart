import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../config/api_config.dart';
import '../../services/image_upload_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../gif/gif_picker.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ComposerConfig — controls which options are visible per context
// ─────────────────────────────────────────────────────────────────────────────

class ComposerConfig {
  final bool allowImages;
  final bool allowGifs;
  final String hintText;
  final int? maxLines;

  const ComposerConfig({
    this.allowImages = false,
    this.allowGifs = false,
    this.hintText = 'Write something…',
    this.maxLines,
  });

  bool get hasMedia => allowImages || allowGifs;

  // ── Presets ──────────────────────────────────────────────────────────────

  /// Public group post — images + GIFs allowed.
  static const publicPost = ComposerConfig(allowImages: true, allowGifs: true);

  /// Encrypted capsule post — text only.
  static const privatePost = ComposerConfig(hintText: 'Write an encrypted post…');

  /// Public comment / reply — GIF allowed, no image upload.
  static const comment = ComposerConfig(allowGifs: true, hintText: 'Add a comment…');

  /// Encrypted comment / reply or thread reply — text only.
  static const textOnly = ComposerConfig(hintText: 'Add a comment…');

  /// Thread detail reply — text only.
  static const threadReply = ComposerConfig(hintText: 'Add to this chain…');

  /// Public group chat message — GIF allowed.
  static const chat = ComposerConfig(allowGifs: true, hintText: 'Message…');
}

// ─────────────────────────────────────────────────────────────────────────────
// ComposerBar
// ─────────────────────────────────────────────────────────────────────────────

/// Unified text + media composer used throughout the app.
///
/// [onSend] receives the trimmed text and an optional resolved media URL.
/// Image upload and GIF picking are handled internally. On a successful
/// [onSend] the text and attachment are automatically cleared.
///
/// Pass [externalController] when the parent must access or clear the text
/// independently (e.g. reply state in quips sheet). Don't dispose it while
/// this widget is still mounted — ComposerBar will not dispose an external
/// controller.
class ComposerBar extends StatefulWidget {
  final ComposerConfig config;
  final Future<void> Function(String text, String? mediaUrl) onSend;
  final TextEditingController? externalController;
  final FocusNode? focusNode;

  const ComposerBar({
    required this.config,
    required this.onSend,
    this.externalController,
    this.focusNode,
    super.key,
  });

  @override
  State<ComposerBar> createState() => _ComposerBarState();
}

class _ComposerBarState extends State<ComposerBar> {
  late final TextEditingController _ctrl;
  File? _mediaFile;
  String? _mediaUrl;
  bool _uploading = false;
  bool _sending = false;

  bool get _hasAttachment => _mediaFile != null || _mediaUrl != null;

  @override
  void initState() {
    super.initState();
    _ctrl = widget.externalController ?? TextEditingController();
  }

  @override
  void dispose() {
    if (widget.externalController == null) _ctrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final xf = await picker.pickImage(source: ImageSource.gallery);
    if (xf == null || !mounted) return;
    setState(() {
      _mediaFile = File(xf.path);
      _mediaUrl = null;
    });
  }

  void _attachGif(String gifUrl) {
    setState(() {
      _mediaFile = null;
      _mediaUrl = gifUrl;
    });
  }

  void _clearAttachment() {
    setState(() {
      _mediaFile = null;
      _mediaUrl = null;
    });
  }

  Future<void> _submit() async {
    final text = _ctrl.text.trim();
    if ((text.isEmpty && !_hasAttachment) || _sending) return;

    setState(() => _sending = true);
    try {
      String? resolvedUrl = _mediaUrl;
      if (_mediaFile != null) {
        setState(() => _uploading = true);
        try {
          resolvedUrl = await ImageUploadService().uploadImage(_mediaFile!);
        } finally {
          if (mounted) setState(() => _uploading = false);
        }
      }
      await widget.onSend(text, resolvedUrl);
      if (mounted) {
        _ctrl.clear();
        _clearAttachment();
      }
    } catch (_) {
      // caller handles error display; don't clear on failure
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _sending || _uploading;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Text field + send button ─────────────────────────────────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                focusNode: widget.focusNode,
                style: TextStyle(color: SojornColors.postContent, fontSize: 14),
                maxLines: widget.config.maxLines,
                decoration: InputDecoration(
                  hintText: widget.config.hintText,
                  hintStyle: TextStyle(color: SojornColors.textDisabled),
                  filled: true,
                  fillColor: AppTheme.scaffoldBg,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (_) => _submit(),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: busy ? null : _submit,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: busy
                      ? AppTheme.brightNavy.withValues(alpha: 0.5)
                      : AppTheme.brightNavy,
                ),
                child: busy
                    ? const Padding(
                        padding: EdgeInsets.all(9),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: SojornColors.basicWhite,
                        ),
                      )
                    : const Icon(Icons.send,
                        color: SojornColors.basicWhite, size: 16),
              ),
            ),
          ],
        ),

        // ── Media action row ─────────────────────────────────────────────
        if (widget.config.hasMedia) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              if (widget.config.allowImages) ...[
                _MediaPill(
                  icon: Icons.image_outlined,
                  label: 'Photo',
                  onTap: _pickImage,
                ),
                if (widget.config.allowGifs) const SizedBox(width: 8),
              ],
              if (widget.config.allowGifs)
                _MediaPill(
                  icon: Icons.gif_outlined,
                  label: 'GIF',
                  onTap: () =>
                      showGifPicker(context, onSelected: _attachGif),
                ),
              if (_hasAttachment) ...[
                const Spacer(),
                GestureDetector(
                  onTap: _clearAttachment,
                  child: Icon(Icons.cancel_outlined,
                      size: 18, color: AppTheme.textSecondary),
                ),
              ],
            ],
          ),
          // ── Attachment preview ───────────────────────────────────────
          if (_mediaFile != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.file(_mediaFile!, height: 120, fit: BoxFit.cover),
              ),
            ),
          if (_mediaUrl != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  ApiConfig.needsProxy(_mediaUrl!)
                      ? ApiConfig.proxyImageUrl(_mediaUrl!)
                      : _mediaUrl!,
                  height: 120,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _MediaPill — small rounded pill button for Photo / GIF
// ─────────────────────────────────────────────────────────────────────────────

class _MediaPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _MediaPill({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppTheme.navyBlue.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppTheme.textSecondary),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
