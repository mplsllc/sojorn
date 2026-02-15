import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';

class ReactionPicker extends StatefulWidget {
  final Function(String) onReactionSelected;
  final VoidCallback? onClosed;
  final List<String>? reactions;
  final Map<String, int>? reactionCounts;
  final Set<String>? myReactions;

  const ReactionPicker({
    super.key,
    required this.onReactionSelected,
    this.onClosed,
    this.reactions,
    this.reactionCounts,
    this.myReactions,
  });

  @override
  State<ReactionPicker> createState() => _ReactionPickerState();
}

class _ReactionPickerState extends State<ReactionPicker> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _currentTabIndex = 0;
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  List<String> _filteredReactions = [];
  
  // Dynamic reaction sets
  Map<String, List<String>> _reactionSets = {};
  Map<String, String> _folderCredits = {};
  List<String> _tabOrder = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadReactionSets();
  }



  Future<void> _loadReactionSets() async {
    try {
      final reactionSets = <String, List<String>>{
        'emoji': [
          '❤️', '👍', '😂', '😮', '😢', '😡',
          '🎉', '🔥', '👏', '🙏', '💯', '🤔',
          '😍', '🤣', '😊', '👌', '🙌', '💪',
          '🎯', '⭐', '✨', '🌟', '💫', '☀️',
        ],
      };
      
      final folderCredits = <String, String>{};
      final tabOrder = ['emoji'];

      // Load the manifest to discover assets
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final assetPaths = manifest.listAssets();
      
      // Filter for reaction assets
      final reactionAssets = assetPaths.where((path) {
        final lowerPath = path.toLowerCase();
        return lowerPath.startsWith('assets/reactions/') && 
        (lowerPath.endsWith('.png') || 
         lowerPath.endsWith('.svg') || 
         lowerPath.endsWith('.webp') || 
         lowerPath.endsWith('.jpg') || 
         lowerPath.endsWith('.jpeg') ||
         lowerPath.endsWith('.gif'));
      }).toList();

      for (final path in reactionAssets) {
        // Path format: assets/reactions/FOLDER_NAME/FILE_NAME.ext
        final parts = path.split('/');
        if (parts.length >= 4) {
          final folderName = parts[2];
          
          if (!reactionSets.containsKey(folderName)) {
            reactionSets[folderName] = [];
            tabOrder.add(folderName);
            
            // Try to load credit file if it's the first time we see this folder
            try {
              final creditPath = 'assets/reactions/$folderName/credit.md';
              // Check if credit file exists in manifest too
              if (assetPaths.contains(creditPath)) {
                final creditData = await rootBundle.loadString(creditPath);
                folderCredits[folderName] = creditData;
              }
            } catch (e) {
              // Ignore missing credit files
            }
          }
          
          reactionSets[folderName]!.add(path);
        }
      }

      // Sort reactions within each set by file name
      for (final key in reactionSets.keys) {
        if (key != 'emoji') {
          reactionSets[key]!.sort((a, b) => a.split('/').last.compareTo(b.split('/').last));
        }
      }

      if (mounted) {
        setState(() {
          _reactionSets = reactionSets;
          _folderCredits = folderCredits;
          _tabOrder = tabOrder;
          _isLoading = false;
          
          _tabController = TabController(length: _tabOrder.length, vsync: this);
          _tabController.addListener(() {
            if (mounted) {
              setState(() {
                _currentTabIndex = _tabController.index;
                _clearSearch();
              });
            }
          });
        });
      }
    } catch (e) {
      // Fallback
      if (mounted) {
        setState(() {
          _reactionSets = {
            'emoji': ['❤️', '👍', '😂', '😮', '😢', '😡']
          };
          _tabOrder = ['emoji'];
          _isLoading = false;
          _tabController = TabController(length: 1, vsync: this);
        });
      }
    }
  }


  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _isSearching = false;
      _filteredReactions = [];
    });
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) {
      setState(() {
        _isSearching = false;
        _filteredReactions = [];
      });
    } else {
      setState(() {
        _isSearching = true;
        _filteredReactions = _filterReactions(query);
      });
    }
  }

  List<String> _filterReactions(String query) {
    final reactions = _currentReactions;
    return reactions.where((reaction) {
      // For image reactions, search by filename
      if (reaction.startsWith('assets/reactions/')) {
        final fileName = reaction.split('/').last.toLowerCase();
        return fileName.contains(query);
      }
      // For emoji, search by description (you could add a mapping)
      return reaction.toLowerCase().contains(query);
    }).toList();
  }

  List<String> get _currentReactions {
    if (_tabOrder.isEmpty || _currentTabIndex >= _tabOrder.length) {
      return [];
    }
    final currentTab = _tabOrder[_currentTabIndex];
    return _reactionSets[currentTab] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Dialog(
        backgroundColor: SojornColors.transparent,
        child: Container(
          width: 400,
          height: 300,
          decoration: BoxDecoration(
            color: AppTheme.cardSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.navyBlue.withValues(alpha: 0.1)),
          ),
          child: const Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }
    
    final reactions = widget.reactions ?? (_isSearching ? _filteredReactions : _currentReactions);
    final reactionCounts = widget.reactionCounts ?? {};
    final myReactions = widget.myReactions ?? {};

    return Dialog(
      backgroundColor: SojornColors.transparent,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.cardSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppTheme.navyBlue.withValues(alpha: 0.2),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: SojornColors.overlayScrim,
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with search
            Column(
              children: [
                Row(
                  children: [
                    Text(
                      _isSearching ? 'Search Reactions' : 'Add Reaction',
                      style: GoogleFonts.inter(
                        color: AppTheme.navyBlue,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        widget.onClosed?.call();
                      },
                      icon: Icon(
                        Icons.close,
                        color: AppTheme.textSecondary,
                        size: 20,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                
                // Search bar
                Container(
                  decoration: BoxDecoration(
                    color: AppTheme.navyBlue.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.navyBlue.withValues(alpha: 0.1),
                    ),
                  ),
                  child: TextField(
                    controller: _searchController,
                    style: GoogleFonts.inter(
                      color: AppTheme.navyBlue,
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search reactions...',
                      hintStyle: GoogleFonts.inter(
                        color: AppTheme.textSecondary,
                        fontSize: 14,
                      ),
                      prefixIcon: Icon(
                        Icons.search,
                        color: AppTheme.textSecondary,
                        size: 20,
                      ),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: Icon(
                                Icons.clear,
                                color: AppTheme.textSecondary,
                                size: 18,
                              ),
                              onPressed: () {
                                _searchController.clear();
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Tabs
            Container(
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.navyBlue.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller: _tabController,
                onTap: (index) {
                  setState(() {
                    _currentTabIndex = index;
                    _isSearching = false;
                    _searchController.clear();
                    _filteredReactions = [];
                  });
                },
                indicator: BoxDecoration(
                  color: AppTheme.brightNavy,
                  borderRadius: BorderRadius.circular(10),
                ),
                labelColor: AppTheme.textSecondary,
                unselectedLabelColor: AppTheme.textSecondary,
                labelStyle: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                tabs: _tabOrder.map((tabName) {
                  return Tab(
                    text: tabName.toUpperCase(),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
            
            // Search results info
            if (_isSearching && _filteredReactions.isEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.navyBlue.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'No reactions found for "${_searchController.text}"',
                  style: GoogleFonts.inter(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            
            // Reaction grid
            SizedBox(
              height: 420, // Increased height to show more rows at once
              child: TabBarView(
                controller: _tabController,
                children: _tabOrder.map((tabName) {
                  final reactions = _reactionSets[tabName] ?? [];
                  final isEmoji = tabName == 'emoji';
                  final credit = _folderCredits[tabName];
                  
                  return Column(
                    children: [
                      // Reaction grid
                      Expanded(
                        child: _buildReactionGrid(reactions, widget.reactionCounts ?? {}, widget.myReactions ?? {}, !isEmoji),
                      ),
                      
                      // Credit section (only for non-emoji tabs)
                      if (credit != null && credit.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Divider(color: SojornColors.textDisabled),
                              const SizedBox(height: 8),
                              Text(
                                'Credits:',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              // Parse and display credit markdown
                              _buildCreditDisplay(credit),
                            ],
                          ),
                        ),
                    ],
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildCreditDisplay(String credit) {
    return MarkdownBody(
      data: credit,
      selectable: true,
      onTapLink: (text, href, title) {
        if (href != null) {
          launchUrl(Uri.parse(href));
        }
      },
      styleSheet: MarkdownStyleSheet(
        p: GoogleFonts.inter(fontSize: 10, color: AppTheme.textPrimary),
        h1: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        h2: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        listBullet: GoogleFonts.inter(fontSize: 10, color: AppTheme.textPrimary),
        strong: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        em: GoogleFonts.inter(fontSize: 10, fontStyle: FontStyle.italic, color: AppTheme.textPrimary),
        a: GoogleFonts.inter(fontSize: 10, color: AppTheme.brightNavy, decoration: TextDecoration.underline),
      ),
    );
  }

  Widget _buildReactionGrid(
    List<String> reactions,
    Map<String, int> reactionCounts,
    Set<String> myReactions,
    bool useImages,
  ) {
    return GridView.builder(
      padding: const EdgeInsets.all(4),
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemCount: reactions.length,
      itemBuilder: (context, index) {
        final reaction = reactions[index];
        final count = reactionCounts[reaction] ?? 0;
        final isSelected = myReactions.contains(reaction);
        
        return Material(
          color: SojornColors.transparent,
          child: InkWell(
            onTap: () {
              Navigator.of(context).pop();
              final result = reaction.startsWith('assets/') 
                  ? 'asset:$reaction' 
                  : reaction;
              widget.onReactionSelected(result);
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              decoration: BoxDecoration(
                color: isSelected 
                    ? AppTheme.brightNavy.withValues(alpha: 0.2)
                    : AppTheme.navyBlue.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected 
                      ? AppTheme.brightNavy
                      : AppTheme.navyBlue.withValues(alpha: 0.1),
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Stack(
                children: [
                  Center(
                    child: useImages
                        ? _buildImageReaction(reaction)
                        : _buildEmojiReaction(reaction),
                  ),
                  if (count > 0)
                    Positioned(
                      right: 2,
                      bottom: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppTheme.brightNavy,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          count > 99 ? '99+' : '$count',
                          style: GoogleFonts.inter(
                            color: SojornColors.basicWhite,
                            fontSize: 8,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmojiReaction(String emoji) {
    return Text(
      emoji,
      style: const TextStyle(fontSize: 24),
    );
  }

  Widget _buildImageReaction(String reaction) {
    final imagePath = reaction.startsWith('asset:')
        ? reaction.replaceFirst('asset:', '')
        : reaction;

    if (imagePath.endsWith('.svg')) {
      return SvgPicture.asset(
        imagePath,
        width: 32,
        height: 32,
        placeholderBuilder: (context) => Container(
          width: 32,
          height: 32,
          padding: const EdgeInsets.all(8),
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppTheme.textSecondary,
          ),
        ),
        errorBuilder: (context, error, stackTrace) {
          return Icon(
            Icons.image_not_supported,
            size: 24,
            color: AppTheme.textSecondary,
          );
        },
      );
    }
    
    return Image.asset(
      imagePath,
      width: 32,
      height: 32,
      errorBuilder: (context, error, stackTrace) {
        return Icon(
          Icons.image_not_supported,
          size: 24,
          color: AppTheme.textSecondary,
        );
      },
    );
  }
}
