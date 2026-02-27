// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import '../../config/api_config.dart';
import '../../providers/api_provider.dart';

class SignedMediaImage extends ConsumerStatefulWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final Alignment alignment;
  final WidgetBuilder? loadingBuilder;
  final Widget Function(BuildContext, Object, StackTrace?)? errorBuilder;

  const SignedMediaImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit,
    this.alignment = Alignment.center,
    this.loadingBuilder,
    this.errorBuilder,
  });

  @override
  ConsumerState<SignedMediaImage> createState() => _SignedMediaImageState();
}

class _SignedMediaImageState extends ConsumerState<SignedMediaImage> {
  String? _resolvedUrl;
  bool _refreshing = false;
  bool _hasRefreshed = false;
  bool _shouldSign = false;

  @override
  void initState() {
    super.initState();
    _configureForUrl(widget.url);
  }

  @override
  void didUpdateWidget(covariant SignedMediaImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _configureForUrl(widget.url);
    }
  }

  void _configureForUrl(String url) {
    _shouldSign = _needsSigning(url);
    _refreshing = false;
    _hasRefreshed = false;

    // On web, external URLs (archive.org, imgur, giphy) need CORS proxying
    if (kIsWeb && ApiConfig.needsProxy(url)) {
      _resolvedUrl = ApiConfig.proxyImageUrl(url);
    } else {
      _resolvedUrl = _shouldSign ? null : url;
    }

    if (_shouldSign && _resolvedUrl == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _refreshSignedUrl();
      });
    }
  }

  bool _needsSigning(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return false;

    // On web platform, prefer direct URLs without signing for better performance
    if (kIsWeb) {
      return false;
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null || (!uri.hasScheme && !uri.hasAuthority)) {
      return true;
    }

    final host = uri.host.toLowerCase();
    
    // Custom domain URLs are public and directly accessible - no signing needed
    if (host == 'img.sojorn.net' || host == 'quips.sojorn.net' ||
        host == 'img.gosojorn.com' || host == 'quips.gosojorn.com') {
      return false;
    }

    // Legacy: media.sojorn.net might need signing depending on setup
    if (host == 'media.sojorn.net') {
      return true;
    }

    if (host.endsWith('.r2.cloudflarestorage.com')) {
      return !uri.queryParameters.containsKey('X-Amz-Signature');
    }

    if (uri.queryParameters.containsKey('X-Amz-Signature') ||
        uri.queryParameters.containsKey('X-Amz-Algorithm')) {
      return false;
    }

    return false;
  }

  Future<void> _refreshSignedUrl() async {
    if (!mounted) return;
    if (_refreshing || _hasRefreshed) return;
    setState(() {
      _refreshing = true;
    });

    try {
      final apiService =
          ProviderScope.containerOf(context, listen: false)
              .read(apiServiceProvider);
      final signedUrl = await apiService.getSignedMediaUrl(widget.url);
      if (!mounted) return;
      if (signedUrl != null && signedUrl.isNotEmpty) {
        setState(() {
          _resolvedUrl = signedUrl;
          _hasRefreshed = true;
        });
      } else {
        setState(() {
          _hasRefreshed = true;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasRefreshed = true;
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _refreshing = false;
      });
    }
  }

  Widget _buildLoading(BuildContext context) {
    return widget.loadingBuilder?.call(context) ?? const SizedBox.shrink();
  }

  static bool _isVideoUrl(String url) {
    final lower = url.toLowerCase().split('?').first;
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.m4v') ||
        lower.endsWith('.avi');
  }

  @override
  Widget build(BuildContext context) {
    if (_resolvedUrl == null) {
      return _buildLoading(context);
    }

    // Video files cannot be decoded by Image.network — return a neutral placeholder.
    // The call site (PostMedia) already overlays a play button, so we just need a
    // dark background to fill the slot without spamming ImageCodecException errors.
    if (_isVideoUrl(_resolvedUrl!)) {
      return Container(
        width: widget.width,
        height: widget.height,
        color: const Color(0xFF1A1A2E),
      );
    }

    return Image.network(
      _resolvedUrl!,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      alignment: widget.alignment,
      filterQuality: FilterQuality.medium,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          child: child,
        );
      },
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) {
          return child;
        }
        return _buildLoading(context);
      },
      errorBuilder: (context, error, stackTrace) {
        // Debug: log the error and URL info
        if (kDebugMode) {
          print('SignedMediaImage error: $error');
          print('Original URL: ${widget.url}');
          print('Resolved URL: $_resolvedUrl');
          print('Needs signing: $_shouldSign');
          print('Platform: ${kIsWeb ? "web" : "native"}');
        }

        if (_shouldSign && !_refreshing && !_hasRefreshed) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _refreshSignedUrl();
          });
          return _buildLoading(context);
        }

        if (widget.errorBuilder != null) {
          return widget.errorBuilder!(context, error, stackTrace);
        }

        // On web, try fallback to direct URL if signing failed
        if (kIsWeb && _shouldSign && _resolvedUrl == null) {
          return Image.network(
            widget.url,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            errorBuilder: widget.errorBuilder,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return _buildLoading(context);
            },
          );
        }

        return const SizedBox.shrink();
      },
    );
  }
}
