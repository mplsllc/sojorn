import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../services/auth_service.dart';
import '../../services/image_upload_service.dart';

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
      setState(() {
        _lineCount = clamped;
      });
    }
  }

  bool _canSend(String text) => text.trim().isNotEmpty;

  void _handleSend() {
    if (!_canSend(widget.controller.text) || widget.isSending) return;
    widget.onSend();
  }

  Future<void> _handleAddAttachment() async {
    if (widget.isSending || _isUploadingAttachment) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.photo_outlined, color: AppTheme.navyBlue),
              title: const Text('Photo from gallery'),
              onTap: () => Navigator.pop(context, 'photo_gallery'),
            ),
            ListTile(
              leading: Icon(Icons.videocam_outlined, color: AppTheme.navyBlue),
              title: const Text('Video from gallery'),
              onTap: () => Navigator.pop(context, 'video_gallery'),
            ),
            ListTile(
              leading: Icon(Icons.photo_camera_outlined, color: AppTheme.navyBlue),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, 'photo_camera'),
            ),
            ListTile(
              leading: Icon(Icons.videocam, color: AppTheme.navyBlue),
              title: const Text('Record a video'),
              onTap: () => Navigator.pop(context, 'video_camera'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || choice == null) return;

    try {
      XFile? file;
      if (choice == 'photo_gallery') {
        file = await _picker.pickImage(source: ImageSource.gallery);
      } else if (choice == 'video_gallery') {
        file = await _picker.pickVideo(source: ImageSource.gallery);
      } else if (choice == 'photo_camera') {
        file = await _picker.pickImage(source: ImageSource.camera);
      } else if (choice == 'video_camera') {
        file = await _picker.pickVideo(source: ImageSource.camera, maxDuration: const Duration(seconds: 30));
      }
      if (file != null) {
        setState(() => _isUploadingAttachment = true);
        final url = await _uploadAttachment(File(file.path), isVideo: choice?.contains('video') ?? false);
        if (url != null && mounted) {
          final existing = widget.controller.text.trim();
          final tag = (choice?.contains('video') ?? false) ? '[video]$url' : '[img]$url';
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
      if (mounted) {
        setState(() => _isUploadingAttachment = false);
      }
    }
  }

  Future<String?> _uploadAttachment(File file, {required bool isVideo}) async {
    try {
      final service = ImageUploadService();
      if (isVideo) {
        return await service.uploadVideo(file);
      } else {
        return await service.uploadImage(file);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Attachment upload failed: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
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
            const SingleActivator(LogicalKeyboardKey.enter):
                const _SendIntent(),
          }
        : const <ShortcutActivator, Intent>{};

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.cardSurface,
          border: Border(
            top: BorderSide(
              color: AppTheme.navyBlue.withValues(alpha: 0.1),
            ),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.replyingLabel != null &&
                  widget.replyingSnippet != null)
                _ReplyPreviewBar(
                  label: widget.replyingLabel!,
                  snippet: widget.replyingSnippet!,
                  onCancel: widget.onCancelReply,
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed: _handleAddAttachment,
                    icon: Icon(Icons.add, color: AppTheme.brightNavy),
                  ),
                  Expanded(
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOut,
                      alignment: Alignment.bottomCenter,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: 44,
                          maxHeight: maxHeight,
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 6),
                          decoration: BoxDecoration(
                            color: SojornColors.basicWhite.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(18),
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
                                textCapitalization:
                                    TextCapitalization.sentences,
                                style: GoogleFonts.inter(
                                  color: AppTheme.navyText,
                                ),
                                decoration: InputDecoration(
                                  isCollapsed: true,
                                  hintText: 'Message',
                                  hintStyle: GoogleFonts.inter(
                                    color: AppTheme.textDisabled,
                                  ),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  disabledBorder: InputBorder.none,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                onSubmitted:
                                    _isDesktop ? null : (_) => _handleSend(),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: widget.controller,
                    builder: (context, value, _) {
                      final canSend = _canSend(value.text);
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        curve: Curves.easeOut,
                        decoration: BoxDecoration(
                          color: canSend
                              ? AppTheme.brightNavy
                              : AppTheme.queenPink,
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          onPressed:
                              canSend && !widget.isSending && !_isUploadingAttachment
                                  ? _handleSend
                                  : null,
                          icon: (widget.isSending || _isUploadingAttachment)
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: SojornColors.basicWhite,
                                  ),
                                )
                              : const Icon(Icons.send,
                                  color: SojornColors.basicWhite, size: 18),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
                  style: GoogleFonts.inter(
                    color: AppTheme.textDisabled,
                  ),
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
