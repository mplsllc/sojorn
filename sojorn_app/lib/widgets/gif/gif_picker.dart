// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'dart:async';
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../config/api_config.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Public entry point
// ─────────────────────────────────────────────────────────────────────────────

/// Shows the GIF picker as a modal bottom sheet.
/// Calls [onSelected] with the chosen GIF URL and closes the sheet.
Future<void> showGifPicker(
  BuildContext context, {
  required void Function(String gifUrl) onSelected,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _GifPickerSheet(onSelected: onSelected),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _GifPickerSheet extends StatefulWidget {
  final void Function(String gifUrl) onSelected;
  const _GifPickerSheet({required this.onSelected});

  @override
  State<_GifPickerSheet> createState() => _GifPickerSheetState();
}

class _GifPickerSheetState extends State<_GifPickerSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _klipySearch = TextEditingController();
  final _retroSearch = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _klipySearch.dispose();
    _retroSearch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.87,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (ctx, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: AppTheme.cardSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.navyBlue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            // Tabs
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: AppTheme.navyBlue.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller: _tabs,
                indicator: BoxDecoration(
                  color: AppTheme.brightNavy,
                  borderRadius: BorderRadius.circular(10),
                ),
                labelColor: SojornColors.basicWhite,
                unselectedLabelColor: AppTheme.textSecondary,
                labelStyle: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600),
                indicatorSize: TabBarIndicatorSize.tab,
                tabs: const [
                  Tab(text: 'KLIPY'),
                  Tab(text: 'RETRO'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _KlipyTab(
                    searchCtrl: _klipySearch,
                    onSelected: (url) {
                      Navigator.of(context).pop();
                      widget.onSelected(url);
                    },
                  ),
                  _RetroTab(
                    searchCtrl: _retroSearch,
                    onSelected: (url) {
                      Navigator.of(context).pop();
                      widget.onSelected(url);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// KLIPY tab — modern GIFs via KLIPY API
// ─────────────────────────────────────────────────────────────────────────────

class _KlipyTab extends StatefulWidget {
  final TextEditingController searchCtrl;
  final void Function(String url) onSelected;
  const _KlipyTab({required this.searchCtrl, required this.onSelected});

  @override
  State<_KlipyTab> createState() => _KlipyTabState();
}

class _KlipyTabState extends State<_KlipyTab>
    with AutomaticKeepAliveClientMixin {
  List<_GifItem> _gifs = [];
  List<_KlipyCategory> _categories = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasError = false;
  bool _hasNext = false;
  int _page = 1;
  String _loadedQuery = '';
  bool _showCategories = true; // show categories by default
  final _scrollCtrl = ScrollController();
  Timer? _debounce;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _fetchCategories();
    _fetch('', page: 1);
    widget.searchCtrl.addListener(_onSearchChanged);
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.searchCtrl.removeListener(_onSearchChanged);
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchCategories() async {
    final key = ApiConfig.klipyApiKey;
    if (key.isEmpty) return;
    try {
      final uri = Uri.parse(
          'https://api.klipy.com/api/v1/$key/gifs/categories?per_page=50');
      final resp = await http.get(uri).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return;
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final cats = (json['data']?['categories'] as List?) ?? [];
      if (mounted) {
        setState(() {
          _categories = cats.map((c) => _KlipyCategory(
            name: c['category'] as String? ?? '',
            query: c['query'] as String? ?? '',
            previewUrl: c['preview_url'] as String? ?? '',
          )).where((c) => c.name.isNotEmpty).toList();
        });
      }
    } catch (_) {}
  }

  void _selectCategory(String query) {
    widget.searchCtrl.text = query;
    setState(() => _showCategories = false);
    _fetch(query, page: 1);
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      final q = widget.searchCtrl.text.trim();
      if (q.isEmpty && _loadedQuery.isNotEmpty) {
        // Cleared search — show categories again
        setState(() => _showCategories = true);
        _fetch('', page: 1);
        return;
      }
      if (q != _loadedQuery) {
        setState(() => _showCategories = false);
        _fetch(q, page: 1);
      }
    });
  }

  void _onScroll() {
    if (_loadingMore || !_hasNext) return;
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 200) {
      _fetch(_loadedQuery, page: _page + 1, append: true);
    }
  }

  Future<void> _fetch(String query, {required int page, bool append = false}) async {
    if (!mounted) return;
    final key = ApiConfig.klipyApiKey;
    debugPrint('[GIF] KLIPY key length=${key.length}, empty=${key.isEmpty}');
    if (key.isEmpty) {
      debugPrint('[GIF] KLIPY API key not set — check --dart-define=KLIPY_API_KEY');
      if (mounted) setState(() { _loading = false; _hasError = true; });
      return;
    }

    if (!append) {
      setState(() { _loading = true; _hasError = false; });
    } else {
      setState(() { _loadingMore = true; });
    }
    _loadedQuery = query;

    try {
      final base = 'https://api.klipy.com/api/v1/$key/gifs';
      final Uri uri;
      if (query.isEmpty) {
        uri = Uri.parse('$base/trending?per_page=24&page=$page&rating=pg');
      } else {
        uri = Uri.parse(
            '$base/search?q=${Uri.encodeComponent(query)}&per_page=24&page=$page&rating=pg');
      }

      debugPrint('[GIF] KLIPY → $uri');
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      debugPrint('[GIF] KLIPY ← ${resp.statusCode} (${resp.body.length} bytes)');
      if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');

      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final envelope = json['data'] as Map<String, dynamic>? ?? {};
      final items = (envelope['data'] as List?) ?? [];
      debugPrint('[GIF] KLIPY parsed ${items.length} items');

      final parsed = <_GifItem>[];
      for (final item in items) {
        if (item is! Map<String, dynamic>) continue;
        // KLIPY uses file.{hd,md,sm}.{gif,webp}.url
        final file = item['file'] as Map<String, dynamic>? ?? {};
        final hd = file['hd'] as Map<String, dynamic>?;
        final sm = file['sm'] as Map<String, dynamic>?;
        final md = file['md'] as Map<String, dynamic>?;

        final fullUrl = hd?['gif']?['url'] as String? ??
            md?['gif']?['url'] as String? ?? '';
        final thumbUrl = sm?['gif']?['url'] as String? ??
            sm?['webp']?['url'] as String? ??
            md?['webp']?['url'] as String? ??
            fullUrl;

        if (fullUrl.isEmpty) continue;
        parsed.add(_GifItem(
          url: fullUrl,
          thumbUrl: thumbUrl,
          title: item['title'] as String? ?? '',
          slug: item['slug'] as String?,
        ));
      }

      if (mounted) {
        setState(() {
          if (append) {
            _gifs.addAll(parsed);
          } else {
            _gifs = parsed;
          }
          _page = page;
          _hasNext = envelope['has_next'] == true;
          _loading = false;
          _loadingMore = false;
        });
      }
    } catch (e) {
      debugPrint('[GIF] KLIPY error: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
          if (!append) _hasError = true;
        });
      }
    }
  }

  void _onGifSelected(String url, String? slug) {
    widget.onSelected(url);
    // Fire-and-forget share trigger for KLIPY analytics
    if (slug != null && slug.isNotEmpty) {
      final key = ApiConfig.klipyApiKey;
      if (key.isNotEmpty) {
        http.post(
          Uri.parse('https://api.klipy.com/api/v1/$key/gifs/share-trigger'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'slug': slug}),
        ).catchError((_) => http.Response('', 200));
      }
    }
  }

  Widget _buildCategoryGrid() {
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
        childAspectRatio: 1.3,
      ),
      itemCount: _categories.length,
      itemBuilder: (_, i) {
        final cat = _categories[i];
        return GestureDetector(
          onTap: () => _selectCategory(cat.query),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              fit: StackFit.expand,
              children: [
                CachedNetworkImage(
                  imageUrl: cat.previewUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                    color: AppTheme.navyBlue.withValues(alpha: 0.08),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    color: AppTheme.navyBlue.withValues(alpha: 0.08),
                    child: Icon(Icons.gif_outlined,
                        color: AppTheme.textSecondary, size: 24),
                  ),
                ),
                // Gradient overlay for text readability
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.6),
                        ],
                        stops: const [0.4, 1.0],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 6,
                  right: 6,
                  bottom: 6,
                  child: Text(
                    cat.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        _SearchBar(
          ctrl: widget.searchCtrl,
          hint: 'Search KLIPY',
        ),
        Expanded(
          child: _showCategories && _categories.isNotEmpty
              ? _buildCategoryGrid()
              : _GifGrid(
                  gifs: _gifs,
                  loading: _loading,
                  hasError: _hasError,
                  emptyMessage: _loadedQuery.isEmpty
                      ? 'No GIFs found'
                      : 'No GIFs found for "${widget.searchCtrl.text.trim()}"',
                  onSelected: (item) => _onGifSelected(item.url, item.slug),
                  onRetry: () => _fetch(_loadedQuery, page: 1),
                  scrollController: _scrollCtrl,
                  loadingMore: _loadingMore,
                ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text('Powered by KLIPY',
              style: TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Retro tab — GifCities (archive.org GeoCities GIFs)
// ─────────────────────────────────────────────────────────────────────────────

class _RetroTab extends StatefulWidget {
  final TextEditingController searchCtrl;
  final void Function(String url) onSelected;
  const _RetroTab({required this.searchCtrl, required this.onSelected});

  @override
  State<_RetroTab> createState() => _RetroTabState();
}

class _RetroTabState extends State<_RetroTab>
    with AutomaticKeepAliveClientMixin {
  List<_GifItem> _gifs = [];
  bool _loading = true;
  bool _hasError = false;
  String _loadedQuery = '';
  Timer? _debounce;
  bool _showSuggestions = true;

  static const _defaultQuery = 'space';

  /// Curated search suggestions — themes that return great results from
  /// GifCities' semantic search over archived GeoCities GIFs.
  static const _suggestions = [
    ('Under Construction', 'under construction'),
    ('Welcome', 'welcome to my page'),
    ('Fire', 'fire flames'),
    ('Stars', 'stars sparkle'),
    ('Dancing', 'dancing animation'),
    ('Cats', 'cats kittens'),
    ('Skulls', 'skull goth'),
    ('Rainbow', 'rainbow colorful'),
    ('Email', 'email mailbox'),
    ('Angels', 'angel wings'),
    ('Smiley', 'smiley face happy'),
    ('Hearts', 'hearts love'),
    ('Space', 'space planets'),
    ('Guestbook', 'guestbook sign'),
    ('Dividers', 'horizontal divider bar'),
    ('Dolphins', 'dolphins ocean'),
    ('Dragons', 'dragon fantasy'),
    ('Music', 'music notes'),
    ('Christmas', 'christmas snow'),
    ('Flowers', 'flowers garden'),
  ];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _fetch(_defaultQuery);
    widget.searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.searchCtrl.removeListener(_onSearchChanged);
    super.dispose();
  }

  void _selectSuggestion(String query) {
    widget.searchCtrl.text = query;
    setState(() => _showSuggestions = false);
    _fetch(query);
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      final q = widget.searchCtrl.text.trim();
      if (q.isEmpty && !_showSuggestions) {
        setState(() => _showSuggestions = true);
        _fetch(_defaultQuery);
        return;
      }
      final effective = q.isEmpty ? _defaultQuery : q;
      if (effective != _loadedQuery) {
        setState(() => _showSuggestions = false);
        _fetch(effective);
      }
    });
  }

  Future<void> _fetch(String query) async {
    if (!mounted) return;
    setState(() { _loading = true; _hasError = false; });
    _loadedQuery = query;

    try {
      final uri = Uri.parse(
          'https://gifcities.archive.org/api/v1/gifsearch?q=${Uri.encodeComponent(query)}');
      debugPrint('[GIF] Retro → $uri');
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      debugPrint('[GIF] Retro ← ${resp.statusCode} (${resp.body.length} bytes)');
      if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');

      final decoded = jsonDecode(resp.body);
      final items = decoded is List ? decoded : <dynamic>[];
      debugPrint('[GIF] Retro parsed ${items.length} items');

      final gifs = <_GifItem>[];
      for (final item in items) {
        if (item is! Map<String, dynamic>) continue;
        final gifPath = item['gif'] as String? ?? '';
        if (gifPath.isEmpty) continue;

        // Filter out junk: spacers, bullets, thin bars
        final w = (item['width'] as num?)?.toInt() ?? 0;
        final h = (item['height'] as num?)?.toInt() ?? 0;
        if (w < 30 || h < 30) continue; // too small (spacers, bullets)
        if (w > 10 * h || h > 10 * w) continue; // extreme aspect ratio (bars)

        // Insert 'if_' after timestamp to get raw image (skip Wayback toolbar)
        final slash = gifPath.indexOf('/');
        final rawPath = slash > 0
            ? '${gifPath.substring(0, slash)}if_${gifPath.substring(slash)}'
            : gifPath;
        final fullUrl = 'https://web.archive.org/web/$rawPath';
        gifs.add(_GifItem(url: fullUrl, thumbUrl: fullUrl, title: ''));
      }

      if (mounted) setState(() { _gifs = gifs.take(60).toList(); _loading = false; });
    } catch (e) {
      debugPrint('[GIF] Retro error: $e');
      if (mounted) setState(() { _loading = false; _hasError = true; });
    }
  }

  Widget _buildSuggestionChips() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: _suggestions.map((s) {
          final (label, query) = s;
          return GestureDetector(
            onTap: () => _selectSuggestion(query),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.isDark
                    ? SojornColors.darkSurfaceElevated
                    : AppTheme.navyBlue.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppTheme.isDark
                      ? SojornColors.darkBorder.withValues(alpha: 0.4)
                      : AppTheme.navyBlue.withValues(alpha: 0.12),
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.isDark
                      ? SojornColors.darkPostContent
                      : AppTheme.navyBlue,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        _SearchBar(
          ctrl: widget.searchCtrl,
          hint: 'Search retro gifs from the Internet Archive',
        ),
        if (_showSuggestions) _buildSuggestionChips(),
        Expanded(child: _GifGrid(
          gifs: _gifs,
          loading: _loading,
          hasError: _hasError,
          emptyMessage: 'No retro GIFs found for "${widget.searchCtrl.text.trim().isEmpty ? _defaultQuery : widget.searchCtrl.text.trim()}"',
          onSelected: (item) => widget.onSelected(item.url),
          onRetry: () => _fetch(_loadedQuery),
          crossAxisCount: 3,
          childAspectRatio: 1.0,
        )),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  final TextEditingController ctrl;
  final String hint;
  const _SearchBar({required this.ctrl, required this.hint});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: TextField(
        controller: ctrl,
        style: TextStyle(color: AppTheme.navyBlue, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle:
              TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          prefixIcon: Icon(Icons.search,
              color: AppTheme.textSecondary, size: 20),
          suffixIcon: ValueListenableBuilder(
            valueListenable: ctrl,
            builder: (_, val, __) => val.text.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.clear,
                        color: AppTheme.textSecondary, size: 18),
                    onPressed: ctrl.clear,
                  )
                : const SizedBox.shrink(),
          ),
          filled: true,
          fillColor: AppTheme.navyBlue.withValues(alpha: 0.05),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

class _KlipyCategory {
  final String name;
  final String query;
  final String previewUrl;
  const _KlipyCategory({
    required this.name,
    required this.query,
    required this.previewUrl,
  });
}

class _GifItem {
  final String url;
  final String thumbUrl;
  final String title;
  final String? slug;
  const _GifItem({
    required this.url,
    required this.thumbUrl,
    required this.title,
    this.slug,
  });
}

class _GifGrid extends StatelessWidget {
  final List<_GifItem> gifs;
  final bool loading;
  final bool hasError;
  final String emptyMessage;
  final void Function(_GifItem item) onSelected;
  final VoidCallback onRetry;
  final ScrollController? scrollController;
  final bool loadingMore;
  final int crossAxisCount;
  final double childAspectRatio;

  const _GifGrid({
    required this.gifs,
    required this.loading,
    required this.hasError,
    required this.emptyMessage,
    required this.onSelected,
    required this.onRetry,
    this.scrollController,
    this.loadingMore = false,
    this.crossAxisCount = 2,
    this.childAspectRatio = 1.4,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (hasError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off, size: 36, color: AppTheme.textSecondary),
            const SizedBox(height: 8),
            Text('Could not load GIFs',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (gifs.isEmpty) {
      return Center(
        child: Text(emptyMessage,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            textAlign: TextAlign.center),
      );
    }
    final itemCount = gifs.length + (loadingMore ? 1 : 0);
    return GridView.builder(
      controller: scrollController,
      padding: const EdgeInsets.all(8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
        childAspectRatio: childAspectRatio,
      ),
      itemCount: itemCount,
      itemBuilder: (_, i) {
        if (i >= gifs.length) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 24, height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final gif = gifs[i];
        final displayUrl = ApiConfig.needsProxy(gif.thumbUrl)
            ? ApiConfig.proxyImageUrl(gif.thumbUrl)
            : gif.thumbUrl;
        return GestureDetector(
          onTap: () => onSelected(gif),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: displayUrl,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(
                color: AppTheme.navyBlue.withValues(alpha: 0.05),
                child: Center(
                  child: Icon(Icons.gif_outlined,
                      color: AppTheme.textSecondary, size: 28),
                ),
              ),
              errorWidget: (_, __, ___) => Container(
                color: AppTheme.navyBlue.withValues(alpha: 0.05),
                child: Icon(Icons.broken_image_outlined,
                    color: AppTheme.textSecondary),
              ),
            ),
          ),
        );
      },
    );
  }
}
