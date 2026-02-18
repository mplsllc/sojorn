import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../services/image_upload_service.dart';
import '../gif/gif_picker.dart';

class ComposerWidget extends StatefulWidget {
  const ComposerWidget({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSend,
    this.isSending = false,
    this.replyingLabel,
    this.replyingSnippet,
    this.onCancelReply,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final bool isSending;
  final String? replyingLabel;
  final String? replyingSnippet;
  final VoidCallback? onCancelReply;

  @override
  State<ComposerWidget> createState() => _ComposerWidgetState();
}

class _ComposerWidgetState extends State<ComposerWidget>
    with TickerProviderStateMixin {
  int _lineCount = 1;
  final ImagePicker _picker = ImagePicker();
  bool _isUploadingAttachment = false;
  bool _drawerOpen = false;

  bool get _isDesktop {
    final platform = Theme.of(context).platform;
    return kIsWeb ||
        platform == TargetPlatform.windows ||
        platform == TargetPlatform.macOS ||
        platform == TargetPlatform.linux;
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleTextChanged);
  }

  @override
  void didUpdateWidget(covariant ComposerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleTextChanged);
      widget.controller.addListener(_handleTextChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleTextChanged);
    super.dispose();
  }

  void _handleTextChanged() {
    final lines = widget.controller.text.split('\n').length;
    final clamped = lines.clamp(1, 6).toInt();
    if (clamped != _lineCount) {
      setState(() => _lineCount = clamped);
    }
  }

  bool _canSend(String text) => text.trim().isNotEmpty;

  void _handleSend() {
    if (!_canSend(widget.controller.text) || widget.isSending) return;
    widget.onSend();
  }

  void _toggleDrawer() {
    setState(() => _drawerOpen = !_drawerOpen);
    if (_drawerOpen) widget.focusNode.unfocus();
  }

  Future<void> _pickFromGallery() async {
    setState(() => _drawerOpen = false);
    await _pickAndUpload('photo_gallery');
  }

  Future<void> _takePhoto() async {
    setState(() => _drawerOpen = false);
    await _pickAndUpload('photo_camera');
  }

  Future<void> _pickGif() async {
    setState(() => _drawerOpen = false);
    showGifPicker(context, onSelected: (url) {
      final existing = widget.controller.text.trim();
      final tag = '[img]$url';
      final nextText = existing.isEmpty ? tag : '$existing\n$tag';
      widget.controller.text = nextText;
      widget.controller.selection = TextSelection.fromPosition(
        TextPosition(offset: widget.controller.text.length),
      );
      widget.focusNode.requestFocus();
    });
  }

  Future<void> _pickAndUpload(String choice) async {
    if (widget.isSending || _isUploadingAttachment) return;
    try {
      XFile? file;
      if (choice == 'photo_gallery') {
        file = await _picker.pickImage(source: ImageSource.gallery);
      } else if (choice == 'video_gallery') {
        file = await _picker.pickVideo(source: ImageSource.gallery);
      } else if (choice == 'photo_camera') {
        file = await _picker.pickImage(source: ImageSource.camera);
      } else if (choice == 'video_camera') {
        file = await _picker.pickVideo(
            source: ImageSource.camera,
            maxDuration: const Duration(seconds: 30));
      }
      if (file != null) {
        setState(() => _isUploadingAttachment = true);
        final isVideo = choice.contains('video');
        final url = await _uploadAttachment(File(file.path), isVideo: isVideo);
        if (url != null && mounted) {
          final existing = widget.controller.text.trim();
          final tag = isVideo ? '[video]$url' : '[img]$url';
          final nextText = existing.isEmpty ? tag : '$existing\n$tag';
          widget.controller.text = nextText;
          widget.controller.selection = TextSelection.fromPosition(
            TextPosition(offset: widget.controller.text.length),
          );
          widget.focusNode.requestFocus();
        }
      }
    } catch (_) {
      // Ignore picker errors; UI remains usable.
    } finally {
      if (mounted) setState(() => _isUploadingAttachment = false);
    }
  }

  Future<String?> _uploadAttachment(File file, {required bool isVideo}) async {
    try {
      final service = ImageUploadService();
      return isVideo
          ? await service.uploadVideo(file)
          : await service.uploadImage(file);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Attachment upload failed: $e'),
          backgroundColor: AppTheme.error,
        ));
      }
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    final maxHeight = (52 + (_lineCount - 1) * 22).clamp(52, 140).toDouble();
    final shortcuts = _isDesktop
        ? <ShortcutActivator, Intent>{
            const SingleActivator(LogicalKeyboardKey.enter): const _SendIntent(),
          }
        : const <ShortcutActivator, Intent>{};

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.cardSurface,
          border: Border(
            top: BorderSide(color: AppTheme.navyBlue.withValues(alpha: 0.1)),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Reply preview ──────────────────────────────────────────
              if (widget.replyingLabel != null && widget.replyingSnippet != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: _ReplyPreviewBar(
                    label: widget.replyingLabel!,
                    snippet: widget.replyingSnippet!,
                    onCancel: widget.onCancelReply,
                  ),
                ),

              // ── Horizontal tool drawer ─────────────────────────────────
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                height: _drawerOpen ? 52 : 0,
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  maxHeight: 52,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        _DrawerPill(
                          icon: Icons.photo_library_outlined,
                          label: 'Gallery',
                          onTap: _pickFromGallery,
                        ),
                        const SizedBox(width: 8),
                        _DrawerPill(
                          icon: Icons.camera_alt_outlined,
                          label: 'Camera',
                          onTap: _takePhoto,
                        ),
                        const SizedBox(width: 8),
                        _DrawerPill(
                          icon: Icons.gif_outlined,
                          label: 'GIF',
                          onTap: _pickGif,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Input row ──────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // + toggle button
                    AnimatedRotation(
                      turns: _drawerOpen ? 0.125 : 0, // 45° when open → X
                      duration: const Duration(milliseconds: 200),
                      child: IconButton(
                        onPressed: _toggleDrawer,
                        icon: Icon(
                          Icons.add_circle_outline,
                          color: _drawerOpen
                              ? AppTheme.brightNavy
                              : AppTheme.navyText.withValues(alpha: 0.6),
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      ),
                    ),
                    const SizedBox(width: 4),

                    // Text field
                    Expanded(
                      child: AnimatedSize(
                        duration: const Duration(milliseconds: 160),
                        curve: Curves.easeOut,
                        alignment: Alignment.bottomCenter,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: 40,
                            maxHeight: maxHeight,
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppTheme.scaffoldBg,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: AppTheme.navyBlue.withValues(alpha: 0.08),
                              ),
                            ),
                            child: Shortcuts(
                              shortcuts: shortcuts,
                              child: Actions(
                                actions: {
                                  _SendIntent: CallbackAction<_SendIntent>(
                                    onInvoke: (_) {
                                      _handleSend();
                                      return null;
                                    },
                                  ),
                                },
                                child: TextField(
                                  controller: widget.controller,
                                  focusNode: widget.focusNode,
                                  keyboardType: TextInputType.multiline,
                                  textInputAction: TextInputAction.send,
                                  maxLines: 6,
                                  minLines: 1,
                                  textCapitalization: TextCapitalization.sentences,
                                  style: GoogleFonts.inter(
                                      color: AppTheme.navyText, fontSize: 14),
                                  decoration: InputDecoration(
                                    isCollapsed: true,
                                    hintText: 'Message',
                                    hintStyle: GoogleFonts.inter(
                                        color: AppTheme.textDisabled,
                                        fontSize: 14),
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    disabledBorder: InputBorder.none,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                  onSubmitted: _isDesktop ? null : (_) => _handleSend(),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),

                    // Voice / Send toggle
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: widget.controller,
                      builder: (context, value, _) {
                        final canSend = _canSend(value.text);
                        final busy = widget.isSending || _isUploadingAttachment;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          curve: Curves.easeOut,
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: canSend
                                ? AppTheme.brightNavy
                                : AppTheme.navyBlue.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: busy
                              ? const Padding(
                                  padding: EdgeInsets.all(10),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: SojornColors.basicWhite,
                                  ),
                                )
                              : GestureDetector(
                                  onTap: canSend ? _handleSend : null,
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 150),
                                    child: canSend
                                        ? const Icon(Icons.send,
                                            key: ValueKey('send'),
                                            color: SojornColors.basicWhite,
                                            size: 17)
                                        : Icon(Icons.mic_none_outlined,
                                            key: const ValueKey('mic'),
                                            color: AppTheme.navyBlue
                                                .withValues(alpha: 0.5),
                                            size: 19),
                                  ),
                                ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Horizontal drawer pill button
// ─────────────────────────────────────────────────────────────────────────────

class _DrawerPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _DrawerPill({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.navyBlue.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.navyBlue.withValues(alpha: 0.1)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppTheme.brightNavy),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: AppTheme.navyBlue,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reply preview bar
// ─────────────────────────────────────────────────────────────────────────────

class _ReplyPreviewBar extends StatelessWidget {
  const _ReplyPreviewBar({
    required this.label,
    required this.snippet,
    this.onCancel,
  });

  final String label;
  final String snippet;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.reply, size: 18, color: AppTheme.brightNavy),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    color: AppTheme.navyBlue,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  snippet,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(color: AppTheme.textDisabled),
                ),
              ],
            ),
          ),
          if (onCancel != null)
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: Icon(Icons.close, size: 18, color: AppTheme.textDisabled),
              onPressed: onCancel,
            ),
        ],
      ),
    );
  }
}

class _SendIntent extends Intent {
  const _SendIntent();
}
