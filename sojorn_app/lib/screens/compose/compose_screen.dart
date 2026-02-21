// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:async';
import '../../models/image_filter.dart';
import '../../models/post.dart';
import '../../models/sojorn_media_result.dart';
import '../../models/tone_analysis.dart';
import '../../providers/api_provider.dart';
import '../../providers/feed_refresh_provider.dart';
import '../../services/api_service.dart';
import '../../services/image_upload_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../config/api_config.dart';
import '../../widgets/composer/composer_toolbar.dart';
import '../../widgets/gif/gif_picker.dart';
import '../../services/content_filter.dart';
import '../../widgets/sojorn_snackbar.dart';
import 'image_editor_screen.dart';
import '../quips/create/quip_studio_screen.dart';
import '../quips/create/quip_editor_screen.dart';
import '../audio/audio_library_screen.dart';

class ComposeScreen extends ConsumerStatefulWidget {
  final Post? chainParentPost;

  const ComposeScreen({super.key, this.chainParentPost});

  @override
  ConsumerState<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends ConsumerState<ComposeScreen> {
  final _bodyController = TextEditingController();
  final _charCountNotifier = ValueNotifier<int>(0);
  final _bodyFocusNode = FocusNode();
  final ImageUploadService _imageUploadService = ImageUploadService();

  bool _isLoading = false;
  bool _isUploadingImage = false;
  bool _popped = false;
  String? _errorMessage;
  String? _blockedMessage;
  final int _maxCharacters = 500;
  bool _allowChain = true;
  bool _isNsfw = false;
  bool _isBold = false;
  bool _isItalic = false;
  int? _ttlHoursOverride;

  // Link preview state
  String? _detectedUrl;
  Map<String, dynamic>? _linkPreview;
  bool _isFetchingPreview = false;
  Timer? _urlDebounce;
  bool _isTyping = false;

  File? _selectedImageFile;
  Uint8List? _selectedImageBytes;
  String? _selectedImageName;
  ImageFilter? _selectedFilter;
  String? _selectedGifUrl;
  AudioTrack? _selectedAudioTrack;
  String _visibility = 'public';
  final ImagePicker _imagePicker = ImagePicker();
  static const double _editorFontSize = 22;
  List<String> _tagSuggestions = [];
  Timer? _hashtagDebounce;
  static const Map<int?, String> _ttlOptions = {
    null: 'Use default',
    0: 'Forever',
    12: '12 Hours',
    24: '24 Hours',
    72: '3 Days',
    168: '1 Week',
  };

  @override
  void initState() {
    super.initState();
    _allowChain = true;
    _bodyController.addListener(() {
      _charCountNotifier.value = _bodyController.text.length;
      _handleHashtagSuggestions();
      _handleUrlDetection();
      // Clear blocked banner when user edits their text
      if (_blockedMessage != null) {
        setState(() => _blockedMessage = null);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _bodyFocusNode.requestFocus();
    });
  }

  /// Detect URLs in text and fetch a preview after a pause in typing.
  void _handleUrlDetection() {
    setState(() => _isTyping = true);
    _urlDebounce?.cancel();
    _urlDebounce = Timer(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      setState(() => _isTyping = false);
      final urlMatch = RegExp(r'https?://\S+').firstMatch(_bodyController.text);
      final url = urlMatch?.group(0);
      if (url != null && url != _detectedUrl && url.length > 10) {
        _detectedUrl = url;
        _fetchLinkPreview(url);
      } else if (url == null) {
        setState(() {
          _detectedUrl = null;
          _linkPreview = null;
        });
      }
    });
  }

  Future<void> _fetchLinkPreview(String url) async {
    if (_isFetchingPreview) return;
    setState(() => _isFetchingPreview = true);
    try {
      final data = await ApiService.instance.callGoApi(
        '/safe-domains/check',
        method: 'GET',
        queryParams: {'url': url},
      );
      if (!mounted) return;
      // Now fetch the OG preview from a lightweight endpoint
      // For now, just show the URL + safety status as a card
      setState(() {
        _linkPreview = {
          'url': url,
          'domain': data['domain'] ?? '',
          'safe': data['safe'] ?? false,
          'status': data['status'] ?? 'unknown',
        };
      });
    } catch (_) {
      // Silently fail - preview is optional
    }
    if (mounted) setState(() => _isFetchingPreview = false);
  }

  @override
  void dispose() {
    _urlDebounce?.cancel();
    _hashtagDebounce?.cancel();
    _charCountNotifier.dispose();
    _bodyFocusNode.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  // Refactored _pickMedia to support Video > QuipEditorScreen flow
  Future<void> _pickMedia() async {
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
              leading: Icon(Icons.image, color: AppTheme.navyBlue),
              title: const Text('Image'),
              onTap: () => Navigator.pop(context, 'image'),
            ),
            ListTile(
              leading: Icon(Icons.videocam, color: AppTheme.navyBlue),
              title: const Text('Video'),
              onTap: () => Navigator.pop(context, 'video'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || choice == null) return;

    if (choice == 'image') {
      await _pickImage();
    } else if (choice == 'video') {
      // Direct Record-to-Edit flow: Route immediately to QuipEditorScreen
      if (kIsWeb) {
        sojornSnackbar.showError(
          context: context,
          message: 'Video editing is not supported on web yet',
        );
        return;
      }

      try {
        final XFile? pickedFile = await _imagePicker.pickVideo(
          source: ImageSource.gallery,
        );

        if (pickedFile != null && mounted) {
          // Navigate directly to QuipStudioScreen (ProVideoEditor)
          // Note: using QuipStudioScreen as defined in quip_studio_screen.dart
          final result = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (context) => QuipStudioScreen(
                videoFile: File(pickedFile.path),
              ),
            ),
          );

          // If video was posted successfully (returned true), close compose screen
          if (result == true && mounted) {
            Navigator.of(context).pop(true);
          }
        }
      } catch (e) {
        sojornSnackbar.showError(
          context: context,
          message: 'Failed to select video: ${e.toString()}',
        );
      }
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 85,
      );

      if (pickedFile != null && mounted) {
        final pickedBytes = kIsWeb ? await pickedFile.readAsBytes() : null;
        if (kIsWeb && (pickedBytes == null || pickedBytes.isEmpty)) {
          sojornSnackbar.showError(
            context: context,
            message: 'Failed to load image bytes for web',
          );
          return;
        }
        final editorResult = await Navigator.push<SojornMediaResult>(
          context,
          MaterialPageRoute(
            builder: (context) => sojornImageEditor(
              imagePath: kIsWeb ? null : pickedFile.path,
              imageBytes: pickedBytes,
              imageName: pickedFile.name,
            ),
          ),
        );

        if (editorResult != null && mounted) {
          setState(() {
            _selectedImageFile = editorResult.filePath != null
                ? File(editorResult.filePath!)
                : null;
            _selectedImageBytes = editorResult.bytes;
            _selectedImageName = editorResult.name ?? pickedFile.name;
          });
        }
      }
    } catch (e) {
      sojornSnackbar.showError(
        context: context,
        message: 'Failed to select image: ${e.toString()}',
      );
    }
  }

  void _removeImage() {
    setState(() {
      _selectedImageFile = null;
      _selectedImageBytes = null;
      _selectedImageName = null;
      _selectedFilter = null;
      _selectedGifUrl = null;
    });
  }

  static const _visibilityOptions = [
    ('public', Icons.public, 'Public', 'Visible to everyone'),
    ('followers', Icons.people_outline, 'Followers', 'Only your followers'),
    ('neighborhood', Icons.location_city_outlined, 'Neighborhood', 'Your home neighborhood'),
    ('only_me', Icons.lock_outline, 'Only Me', 'Private, just for you'),
  ];

  Future<void> _openVisibilitySelector() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text('Who can see this?',
                  style: AppTheme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ),
            ..._visibilityOptions.map((opt) {
              final (value, icon, label, description) = opt;
              final isSelected = _visibility == value;
              return ListTile(
                leading: Icon(icon,
                    color: isSelected ? AppTheme.brightNavy : AppTheme.navyText.withValues(alpha: 0.6)),
                title: Text(label,
                    style: TextStyle(
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                        color: isSelected ? AppTheme.brightNavy : AppTheme.navyText)),
                subtitle: Text(description,
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                trailing: isSelected
                    ? Icon(Icons.check_circle, color: AppTheme.brightNavy, size: 20)
                    : null,
                onTap: () {
                  setState(() => _visibility = value);
                  Navigator.pop(ctx);
                },
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _openMusicPicker() async {
    final track = await Navigator.of(context, rootNavigator: true).push<AudioTrack>(
      MaterialPageRoute(builder: (_) => const AudioLibraryScreen()),
    );
    if (track != null && mounted) {
      setState(() => _selectedAudioTrack = track);
    }
  }

  void _openGifPicker() {
    showGifPicker(context, onSelected: (url) {
      setState(() {
        _selectedGifUrl = url;
        _selectedImageFile = null;
        _selectedImageBytes = null;
        _selectedImageName = null;
        _selectedFilter = null;
      });
    });
  }

  void _toggleBold() {
    setState(() {
      _isBold = !_isBold;
    });
  }

  void _toggleItalic() {
    setState(() {
      _isItalic = !_isItalic;
    });
  }

  void _toggleChain() {
    setState(() {
      _allowChain = !_allowChain;
    });
  }

  Future<void> _openTtlSelector() async {
    final choice = await showModalBottomSheet<_TtlChoice>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: _ttlOptions.entries.map((entry) {
              final isSelected = entry.key == _ttlHoursOverride;
              return ListTile(
                title: Text(entry.value),
                trailing: isSelected
                    ? Icon(Icons.check, color: AppTheme.brightNavy)
                    : null,
                onTap: () => Navigator.pop(context, _TtlChoice(entry.key)),
              );
            }).toList(),
          ),
        );
      },
    );

    if (choice == null) return;
    setState(() => _ttlHoursOverride = choice.hours);
  }

  String? _activeHashtag() {
    final cursor = _bodyController.selection.baseOffset;
    if (cursor < 0 || cursor > _bodyController.text.length) return null;
    final prefix = _bodyController.text.substring(0, cursor);
    final match = RegExp(r'#([A-Za-z0-9_]{1,50})$').firstMatch(prefix);
    if (match != null) {
      return match.group(1)?.toLowerCase();
    }
    return null;
  }

  void _handleHashtagSuggestions() {
    final tag = _activeHashtag();
    _hashtagDebounce?.cancel();
    if (tag == null || tag.isEmpty) {
      setState(() => _tagSuggestions = []);
      return;
    }
    _hashtagDebounce = Timer(const Duration(milliseconds: 200), () async {
      try {
        final apiService = ref.read(apiServiceProvider);
        final results = await apiService.search(tag);
        final suggestions = results.tags
            .map((t) => t.tag.toLowerCase())
            .where((t) => t.startsWith(tag))
            .toSet()
            .toList();
        if (mounted) {
          setState(() {
            _tagSuggestions = suggestions;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _tagSuggestions = []);
      }
    });
  }

  void _insertHashtag(String tag) {
    final cursor = _bodyController.selection.baseOffset;
    if (cursor < 0) return;
    final text = _bodyController.text;
    final prefix = text.substring(0, cursor);
    final suffix = text.substring(cursor);
    final match = RegExp(r'#([A-Za-z0-9_]{1,50})$').firstMatch(prefix);
    if (match == null) return;
    final start = match.start;
    final newText = prefix.substring(0, start) + '#$tag ' + suffix;
    _bodyController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + tag.length + 2),
    );
    setState(() {
      _tagSuggestions = [];
    });
  }

  Future<void> _publish() async {
    if (_bodyController.text.trim().isEmpty) {
      sojornSnackbar.showError(
        context: context,
        message: 'Post cannot be empty',
      );
      return;
    }

    // Layer 0: Client-side hard blocklist — never even send to server
    final blockMessage = ContentFilter.instance.check(_bodyController.text.trim());
    if (blockMessage != null) {
      setState(() => _blockedMessage = blockMessage);
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      String? imageUrl = _selectedGifUrl;

      if (_selectedImageFile != null || _selectedImageBytes != null) {
        setState(() {
          _isUploadingImage = true;
        });

        try {
          if (_selectedImageBytes != null) {
            imageUrl = await _imageUploadService.uploadImageBytes(
              _selectedImageBytes!,
              fileName: _selectedImageName,
              filter: _selectedFilter,
            );
          } else if (_selectedImageFile != null) {
            imageUrl = await _imageUploadService.uploadImage(
              _selectedImageFile!,
              filter: _selectedFilter,
            );
          }
        } catch (e) {
          throw Exception(
              'Image upload failed: ${e.toString().replaceAll('Exception: ', '')}');
        } finally {
          setState(() {
            _isUploadingImage = false;
          });
        }
      }

      final apiService = ref.read(apiServiceProvider);

      debugPrint('[Compose] publish — visibility=$_visibility chain=${widget.chainParentPost?.id} hasImage=${imageUrl != null} ttl=$_ttlHoursOverride');
      await apiService.publishPost(
        body: _bodyController.text.trim(),
        bodyFormat: 'plain',
        allowChain: _allowChain,
        chainParentId: widget.chainParentPost?.id,
        imageUrl: imageUrl,
        ttlHours: _ttlHoursOverride,
        isNsfw: _isNsfw,
        visibility: _visibility,
        audioOverlayUrl: _selectedAudioTrack?.path,
      );
      debugPrint('[Compose] ✓ published');

      if (mounted && !_popped) {
        _popped = true;
        ref.read(feedRefreshProvider.notifier).increment();
        Navigator.of(context).pop(true);
        return; // Skip finally setState — widget is being disposed
      }
    } catch (e) {
      debugPrint('[Compose] ✗ publish failed: $e');
      if (!mounted || _popped) return;
      final msg = e.toString().replaceAll('Exception: ', '');
      // Server-side blocklist catch (422 with blocked content message)
      if (msg.contains("isn't allowed on Sojorn") || msg.contains('not allowed')) {
        setState(() => _blockedMessage = msg);
      } else {
        setState(() {
          _errorMessage = msg;
        });
      }
    } finally {
      if (mounted && !_popped) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<bool> _showWarningDialog(ToneCheckResult analysis) async {
    final categoryLabel = analysis.categoryLabel;
    final message =
        'Hold on. Our system detected this may contain $categoryLabel content. '
        'If you post this and it violates our guidelines, you will receive a Strike.';

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Hold on'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Edit'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Post Anyway'),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  Widget _buildBlockedBanner() {
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      child: _blockedMessage != null
          ? Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingMd,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                border: Border(
                  bottom: BorderSide(
                    color: AppTheme.error.withValues(alpha: 0.2),
                  ),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: AppTheme.error, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _blockedMessage!,
                          style: AppTheme.textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF991B1B),
                            fontWeight: FontWeight.w500,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _blockedMessage = null),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Icon(
                        Icons.close,
                        size: 16,
                        color: AppTheme.error.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  bool get _canPublish {
    return _bodyController.text.trim().isNotEmpty &&
        _bodyController.text.trim().length <= _maxCharacters &&
        !_isLoading &&
        !_isUploadingImage;
  }

  @override
  Widget build(BuildContext context) {
    final bool isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(52),
        child: ValueListenableBuilder<int>(
          valueListenable: _charCountNotifier,
          builder: (_, __, ___) => ComposeAppBar(
            isLoading: _isLoading,
            canPublish: _canPublish,
            postAction: _publish,
            replyTitle: widget.chainParentPost != null 
                ? 'Reply to ${widget.chainParentPost!.author?.displayName ?? 'Anonymous'}'
                : null,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildVisibilityRow(),
            _buildBlockedBanner(),
            if (_errorMessage != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacingMd,
                  vertical: AppTheme.spacingSm,
                ),
                color: AppTheme.error.withValues(alpha: 0.08),
                child: Text(
                  _errorMessage!,
                  style: AppTheme.textTheme.labelSmall?.copyWith(
                    color: AppTheme.error,
                  ),
                ),
              ),
            // Reply context indicator
            if (widget.chainParentPost != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacingMd,
                  vertical: AppTheme.spacingSm,
                ),
                margin: const EdgeInsets.only(bottom: AppTheme.spacingSm),
                decoration: BoxDecoration(
                  color: AppTheme.navyBlue.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppTheme.navyBlue.withValues(alpha: 0.2),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.reply,
                      size: 16,
                      color: AppTheme.navyBlue,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Replying to ${widget.chainParentPost!.author?.displayName ?? 'Anonymous'}',
                        style: AppTheme.labelSmall?.copyWith(
                          color: AppTheme.navyBlue,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: ComposeBody(
                controller: _bodyController,
                focusNode: _bodyFocusNode,
                isBold: _isBold,
                isItalic: _isItalic,
                suggestions: _tagSuggestions,
                onSelectSuggestion: _insertHashtag,
                imageWidget: (_selectedImageFile != null ||
                            _selectedImageBytes != null) &&
                        !isKeyboardOpen
                    ? _buildImagePreview()
                    : null,
                gifPreviewWidget: _selectedGifUrl != null && !isKeyboardOpen
                    ? _buildGifPreview()
                    : null,
                linkPreviewWidget: !_isTyping && _linkPreview != null && !isKeyboardOpen
                    ? _buildComposeLinkPreview()
                    : null,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: ValueListenableBuilder<int>(
        valueListenable: _charCountNotifier,
        builder: (_, count, __) {
          final remaining = _maxCharacters - count;
          return AnimatedPadding(
            duration: const Duration(milliseconds: 150),
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom),
            child: ComposeBottomBar(
              onAddMedia: _pickMedia,
              onAddGif: _openGifPicker,
              onAddMusic: _openMusicPicker,
              onToggleBold: _toggleBold,
              onToggleItalic: _toggleItalic,
              onToggleChain: _toggleChain,
              onToggleNsfw: () => setState(() => _isNsfw = !_isNsfw),
              onSelectTtl: _openTtlSelector,
              ttlOverrideActive: _ttlHoursOverride != null,
              ttlLabel: _ttlOptions[_ttlHoursOverride] ?? 'Use default',
              isBold: _isBold,
              isItalic: _isItalic,
              allowChain: _allowChain,
              isNsfw: _isNsfw,
              characterCount: count,
              maxCharacters: _maxCharacters,
              isUploadingImage: _isUploadingImage,
              remainingChars: remaining,
              selectedAudioTitle: _selectedAudioTrack?.title,
              onClearAudio: _selectedAudioTrack != null
                  ? () => setState(() => _selectedAudioTrack = null)
                  : null,
            ),
          );
        },
      ),
    );
  }

  Widget _buildVisibilityRow() {
    final opt = _visibilityOptions.firstWhere((o) => o.$1 == _visibility,
        orElse: () => _visibilityOptions.first);
    return Container(
      color: AppTheme.scaffoldBg,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          GestureDetector(
            onTap: widget.chainParentPost == null ? _openVisibilitySelector : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.brightNavy.withValues(alpha: 0.35)),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(opt.$2, size: 14, color: AppTheme.brightNavy),
                  const SizedBox(width: 5),
                  Text(opt.$3,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.brightNavy)),
                  if (widget.chainParentPost == null) ...[
                    const SizedBox(width: 3),
                    Icon(Icons.arrow_drop_down, size: 16, color: AppTheme.brightNavy),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePreview() {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingLg, vertical: AppTheme.spacingSm),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            AspectRatio(
              aspectRatio: 4 / 3,
              child: _selectedImageBytes != null
                  ? Image.memory(
                      _selectedImageBytes!,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    )
                  : Image.file(
                      _selectedImageFile!,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Material(
                color: SojornColors.overlayDark,
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: _removeImage,
                  customBorder: const CircleBorder(),
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.close, color: SojornColors.basicWhite, size: 18),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGifPreview() {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingLg, vertical: AppTheme.spacingSm),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            Image.network(
              ApiConfig.needsProxy(_selectedGifUrl!)
                  ? ApiConfig.proxyImageUrl(_selectedGifUrl!)
                  : _selectedGifUrl!,
              height: 150,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
            Positioned(
              top: 8, right: 8,
              child: Material(
                color: SojornColors.overlayDark,
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: _removeImage,
                  customBorder: const CircleBorder(),
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.close, color: SojornColors.basicWhite, size: 18),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComposeLinkPreview() {
    final preview = _linkPreview!;
    final domain = preview['domain'] as String? ?? '';
    final url = preview['url'] as String? ?? '';
    final isSafe = preview['safe'] as bool? ?? false;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppTheme.spacingLg, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isSafe
            ? AppTheme.navyBlue.withValues(alpha: 0.05)
            : SojornColors.nsfwWarningBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSafe
              ? AppTheme.navyBlue.withValues(alpha: 0.15)
              : SojornColors.nsfwWarningBorder,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isSafe ? Icons.link_rounded : Icons.warning_amber_rounded,
            size: 20,
            color: isSafe ? AppTheme.navyBlue : AppTheme.nsfwWarningIcon,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  domain.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: AppTheme.textTertiary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  url.length > 60 ? '${url.substring(0, 57)}...' : url,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (_isFetchingPreview)
            const SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            GestureDetector(
              onTap: () => setState(() {
                _linkPreview = null;
                _detectedUrl = null;
              }),
              child: Icon(Icons.close, size: 18, color: AppTheme.textTertiary),
            ),
        ],
      ),
    );
  }
}

/// Minimal top bar with Cancel + Post pill
class ComposeAppBar extends StatelessWidget {
  final bool isLoading;
  final bool canPublish;
  final VoidCallback postAction;
  final String? replyTitle;

  const ComposeAppBar({
    super.key,
    required this.isLoading,
    required this.canPublish,
    required this.postAction,
    this.replyTitle,
  });

  @override
  Widget build(BuildContext context) {
    final bool disabled = !canPublish || isLoading;
    return AppBar(
      elevation: 0,
      backgroundColor: AppTheme.scaffoldBg,
      leadingWidth: 80,
      leading: TextButton(
        onPressed: isLoading ? null : () => Navigator.of(context).pop(),
        child: Text(
          'Cancel',
          style: TextStyle(
            color: AppTheme.egyptianBlue,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      title: replyTitle != null 
        ? Text(
            replyTitle!,
            style: AppTheme.labelSmall?.copyWith(
              color: AppTheme.navyText,
              fontSize: 14,
            ),
          )
        : const SizedBox.shrink(),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: AppTheme.spacingMd),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: disabled ? 0.5 : 1.0,
            child: ElevatedButton(
              onPressed: disabled ? null : postAction,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.brightNavy,
                foregroundColor: AppTheme.white,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                shape: const StadiumBorder(),
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.white,
                      ),
                    )
                  : const Text(
                      'Post',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Body with immersive canvas and optional media preview
class ComposeBody extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isBold;
  final bool isItalic;
  final Widget? imageWidget;
  final Widget? gifPreviewWidget;
  final Widget? linkPreviewWidget;
  final List<String> suggestions;
  final ValueChanged<String> onSelectSuggestion;

  const ComposeBody({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.isBold,
    required this.isItalic,
    required this.suggestions,
    required this.onSelectSuggestion,
    this.imageWidget,
    this.gifPreviewWidget,
    this.linkPreviewWidget,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spacingLg,
              vertical: AppTheme.spacingMd,
            ),
            child: Column(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    autofocus: true,
                    maxLines: null,
                    minLines: null,
                    expands: true,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    textAlignVertical: TextAlignVertical.top,
                    style: AppTheme.textTheme.bodyLarge?.copyWith(
                      fontSize: _ComposeScreenState._editorFontSize,
                      height: 1.5,
                      fontWeight: isBold ? FontWeight.w700 : FontWeight.w400,
                      fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
                    ),
                    decoration: const InputDecoration(
                      hintText: "What's happening?",
                      border: InputBorder.none,
                      isCollapsed: true,
                    ),
                    cursorColor: AppTheme.brightNavy,
                  ),
                ),
                if (suggestions.isNotEmpty)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.cardSurface,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: SojornColors.overlayScrim,
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: suggestions.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final tag = suggestions[index];
                        return ListTile(
                          title: Text('#$tag', style: AppTheme.bodyMedium),
                          onTap: () => onSelectSuggestion(tag),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (linkPreviewWidget != null) linkPreviewWidget!,
        if (imageWidget != null) imageWidget!,
        if (gifPreviewWidget != null) gifPreviewWidget!,
      ],
    );
  }
}

/// Bottom bar pinned above the keyboard with formatting + counter
class ComposeBottomBar extends StatelessWidget {
  final VoidCallback onAddMedia;
  final VoidCallback? onAddGif;
  final VoidCallback? onAddMusic;
  final VoidCallback onToggleBold;
  final VoidCallback onToggleItalic;
  final VoidCallback onToggleChain;
  final VoidCallback? onToggleNsfw;
  final VoidCallback onSelectTtl;
  final bool isBold;
  final bool isItalic;
  final bool allowChain;
  final bool isNsfw;
  final bool ttlOverrideActive;
  final String ttlLabel;
  final int characterCount;
  final int maxCharacters;
  final bool isUploadingImage;
  final int remainingChars;
  final String? selectedAudioTitle;
  final VoidCallback? onClearAudio;

  const ComposeBottomBar({
    super.key,
    required this.onAddMedia,
    this.onAddGif,
    this.onAddMusic,
    required this.onToggleBold,
    required this.onToggleItalic,
    required this.onToggleChain,
    this.onToggleNsfw,
    required this.onSelectTtl,
    required this.ttlOverrideActive,
    required this.ttlLabel,
    required this.isBold,
    required this.isItalic,
    required this.allowChain,
    this.isNsfw = false,
    required this.characterCount,
    required this.maxCharacters,
    required this.isUploadingImage,
    required this.remainingChars,
    this.selectedAudioTitle,
    this.onClearAudio,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        border: Border(
          top: BorderSide(
            color: AppTheme.egyptianBlue.withValues(alpha: 0.12),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selectedAudioTitle != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  children: [
                    const Icon(Icons.music_note, size: 14, color: Colors.purple),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        selectedAudioTitle!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.purple,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    GestureDetector(
                      onTap: onClearAudio,
                      child: const Icon(Icons.close, size: 16, color: Colors.purple),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingMd,
                vertical: AppTheme.spacingSm,
              ),
              child: ComposerToolbar(
                onAddMedia: onAddMedia,
                onAddGif: onAddGif,
                onAddMusic: onAddMusic,
                onToggleBold: onToggleBold,
                onToggleItalic: onToggleItalic,
                onToggleChain: onToggleChain,
                onToggleNsfw: onToggleNsfw,
                onSelectTtl: onSelectTtl,
                ttlOverrideActive: ttlOverrideActive,
                ttlLabel: ttlLabel,
                isBold: isBold,
                isItalic: isItalic,
                allowChain: allowChain,
                isNsfw: isNsfw,
                characterCount: characterCount,
                maxCharacters: maxCharacters,
                isUploadingImage: isUploadingImage,
                remainingChars: remainingChars,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TtlChoice {
  final int? hours;
  const _TtlChoice(this.hours);
}
