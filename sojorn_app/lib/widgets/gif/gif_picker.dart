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
  final _memesSearch = TextEditingController();
  final _retroSearch = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _memesSearch.dispose();
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
            const SizedBox(height: 12),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text('GIFs',
                      style: TextStyle(
                          color: AppTheme.navyBlue,
                          fontSize: 17,
                          fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.close,
                        color: AppTheme.textSecondary, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
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
                  Tab(text: 'MEMES'),
                  Tab(text: 'RETRO'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _MemeTab(
                    searchCtrl: _memesSearch,
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
// Memes tab — Reddit meme_api (r/gifs, r/reactiongifs, r/HighQualityGifs)
// ─────────────────────────────────────────────────────────────────────────────

class _MemeTab extends StatefulWidget {
  final TextEditingController searchCtrl;
  final void Function(String url) onSelected;
  const _MemeTab({required this.searchCtrl, required this.onSelected});

  @override
  State<_MemeTab> createState() => _MemeTabState();
}

class _MemeTabState extends State<_MemeTab>
    with AutomaticKeepAliveClientMixin {
  List<_GifItem> _gifs = [];
  bool _loading = true;
  bool _hasError = false;
  String _loadedQuery = '';

  static const _defaultSubreddits = ['gifs', 'reactiongifs', 'HighQualityGifs'];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _fetch('');
    widget.searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    widget.searchCtrl.removeListener(_onSearchChanged);
    super.dispose();
  }

  void _onSearchChanged() {
    final q = widget.searchCtrl.text.trim();
    if (q != _loadedQuery) {
      _fetch(q);
    }
  }

  Future<void> _fetch(String query) async {
    if (!mounted) return;
    setState(() { _loading = true; _hasError = false; });
    _loadedQuery = query;

    try {
      final results = <_GifItem>[];
      if (query.isEmpty) {
        // Load from three gif-centric subreddits in parallel
        final futures = _defaultSubreddits.map(_fetchSubreddit);
        final lists = await Future.wait(futures);
        for (final list in lists) {
          results.addAll(list);
        }
        results.shuffle();
      } else {
        // Keyword search across gif-centric subreddits (not treating query as subreddit)
        results.addAll(await _searchGifSubreddits(query));
      }

      if (mounted) {
        setState(() {
          _gifs = results.take(60).toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _loading = false; _hasError = true; });
    }
  }

  /// Searches Reddit's search API across gif-centric subreddits for the given keyword.
  Future<List<_GifItem>> _searchGifSubreddits(String query) async {
    final subreddit = _defaultSubreddits.join('+');
    final uri = Uri.parse(
        'https://www.reddit.com/r/$subreddit/search.json'
        '?q=${Uri.encodeComponent(query)}&sort=top&restrict_sr=1&limit=25&type=link');
    final resp = await http
        .get(uri, headers: {'User-Agent': 'SojornApp/1.0'})
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return [];
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final children =
        ((data['data'] as Map<String, dynamic>)['children'] as List?) ?? [];
    return children
        .cast<Map<String, dynamic>>()
        .map((c) => c['data'] as Map<String, dynamic>)
        .where((post) {
          final url = post['url'] as String? ?? '';
          return !url.startsWith('https://v.redd.it/') &&
              !url.endsWith('.mp4') &&
              (url.endsWith('.gif') ||
                  url.startsWith('https://i.redd.it/') ||
                  url.startsWith('https://preview.redd.it/') ||
                  url.startsWith('https://i.imgur.com/') ||
                  url.startsWith('https://media.giphy.com/')) &&
              post['over_18'] != true;
        })
        .map((post) => _GifItem(
              url: post['url'] as String,
              title: post['title'] as String? ?? '',
            ))
        .toList();
  }

  Future<List<_GifItem>> _fetchSubreddit(String subreddit) async {
    final uri = Uri.parse(
        'https://meme-api.com/gimme/$subreddit/20');
    final resp = await http.get(uri).timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) return [];
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final memes = (data['memes'] as List?) ?? [];
    return memes
        .cast<Map<String, dynamic>>()
        .where((m) {
          final url = m['url'] as String? ?? '';
          // Accept GIF-capable image URLs; reject video-only hosts and .mp4
          final isImage = !url.startsWith('https://v.redd.it/') &&
              !url.endsWith('.mp4') &&
              (url.endsWith('.gif') ||
                  url.startsWith('https://i.redd.it/') ||
                  url.startsWith('https://preview.redd.it/') ||
                  url.startsWith('https://i.imgur.com/') ||
                  url.startsWith('https://media.giphy.com/'));
          return isImage && m['nsfw'] != true;
        })
        .map((m) => _GifItem(
              url: m['url'] as String,
              title: m['title'] as String? ?? '',
            ))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        _SearchBar(
          ctrl: widget.searchCtrl,
          hint: 'Search reactions (e.g. happy, facepalm)…',
        ),
        Expanded(child: _GifGrid(
          gifs: _gifs,
          loading: _loading,
          hasError: _hasError,
          emptyMessage: _loadedQuery.isEmpty
              ? 'No GIFs found'
              : 'No GIFs found for "${widget.searchCtrl.text.trim()}"',
          onSelected: widget.onSelected,
          onRetry: () => _fetch(_loadedQuery),
        )),
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

  static const _defaultQuery = 'space';
  static final _gifUrlRegex = RegExp(
      r'https://blob\.gifcities\.org/gifcities/[A-Za-z0-9_\-]+\.gif',
      caseSensitive: false);

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
    widget.searchCtrl.removeListener(_onSearchChanged);
    super.dispose();
  }

  void _onSearchChanged() {
    final q = widget.searchCtrl.text.trim();
    final effective = q.isEmpty ? _defaultQuery : q;
    if (effective != _loadedQuery) {
      _fetch(effective);
    }
  }

  Future<void> _fetch(String query) async {
    if (!mounted) return;
    setState(() { _loading = true; _hasError = false; });
    _loadedQuery = query;

    try {
      final gifs = await _fetchGifCities(query);
      if (mounted) setState(() { _gifs = gifs; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _hasError = true; });
    }
  }

  /// Fetches retro GIFs from GifCities. Tries the JSON API first, falls back
  /// to HTML scraping with the blob URL regex.
  Future<List<_GifItem>> _fetchGifCities(String query) async {
    // ── 1. JSON API ──────────────────────────────────────────────────────────
    try {
      final jsonUri = Uri.parse(
          'https://gifcities.org/api/gifs?q=${Uri.encodeComponent(query)}&limit=60');
      final jsonResp = await http
          .get(jsonUri, headers: {
            'Accept': 'application/json',
            'User-Agent': 'SojornApp/1.0',
          })
          .timeout(const Duration(seconds: 8));

      if (jsonResp.statusCode == 200) {
        final decoded = jsonDecode(jsonResp.body);
        List? items;
        if (decoded is List) {
          items = decoded;
        } else if (decoded is Map) {
          items = decoded['items'] as List? ??
              decoded['results'] as List? ??
              decoded['data'] as List? ??
              decoded['gifs'] as List?;
        }
        if (items != null && items.isNotEmpty) {
          final unique = <String>{};
          final result = <_GifItem>[];
          for (final item in items) {
            if (item is! Map) continue;
            final url = item['url'] as String? ??
                item['image_url'] as String? ??
                item['src'] as String? ?? '';
            if (url.isNotEmpty && unique.add(url)) {
              result.add(_GifItem(url: url, title: ''));
            }
          }
          if (result.isNotEmpty) return result;
        }
      }
    } catch (_) {}

    // ── 2. HTML scraping fallback ─────────────────────────────────────────
    for (final pageUrl in [
      'https://gifcities.org/?q=${Uri.encodeComponent(query)}',
      'https://gifcities.org/search?q=${Uri.encodeComponent(query)}&page_size=60&offset=0',
    ]) {
      try {
        final resp = await http
            .get(Uri.parse(pageUrl), headers: {
              'Accept': 'text/html,*/*',
              'User-Agent': 'Mozilla/5.0 (compatible; SojornApp/1.0)',
            })
            .timeout(const Duration(seconds: 10));
        final matches = _gifUrlRegex.allMatches(resp.body);
        if (matches.isNotEmpty) {
          final unique = <String>{};
          final result = <_GifItem>[];
          for (final m in matches) {
            final url = m.group(0)!;
            if (unique.add(url)) result.add(_GifItem(url: url, title: ''));
          }
          if (result.isNotEmpty) return result;
        }
      } catch (_) {}
    }

    return [];
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        _SearchBar(
          ctrl: widget.searchCtrl,
          hint: 'Search retro GIFs (e.g. dancing, stars)…',
        ),
        Expanded(child: _GifGrid(
          gifs: _gifs,
          loading: _loading,
          hasError: _hasError,
          emptyMessage: 'No retro GIFs found for "${widget.searchCtrl.text.trim().isEmpty ? _defaultQuery : widget.searchCtrl.text.trim()}"',
          onSelected: widget.onSelected,
          onRetry: () => _fetch(_loadedQuery),
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

class _GifItem {
  final String url;
  final String title;
  const _GifItem({required this.url, required this.title});
}

class _GifGrid extends StatelessWidget {
  final List<_GifItem> gifs;
  final bool loading;
  final bool hasError;
  final String emptyMessage;
  final void Function(String url) onSelected;
  final VoidCallback onRetry;

  const _GifGrid({
    required this.gifs,
    required this.loading,
    required this.hasError,
    required this.emptyMessage,
    required this.onSelected,
    required this.onRetry,
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
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
        childAspectRatio: 1.4,
      ),
      itemCount: gifs.length,
      itemBuilder: (_, i) {
        final gif = gifs[i];
        final displayUrl = ApiConfig.needsProxy(gif.url)
            ? ApiConfig.proxyImageUrl(gif.url)
            : gif.url;
        return GestureDetector(
          onTap: () => onSelected(gif.url), // store original URL, proxy at display
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
