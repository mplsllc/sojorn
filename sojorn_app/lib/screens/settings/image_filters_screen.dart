import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/image_filter.dart';
import '../../providers/image_filter_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_scaffold.dart';

class ImageFiltersScreen extends ConsumerStatefulWidget {
  const ImageFiltersScreen({super.key});

  @override
  ConsumerState<ImageFiltersScreen> createState() => _ImageFiltersScreenState();
}

class _ImageFiltersScreenState extends ConsumerState<ImageFiltersScreen> {
  final TextEditingController _filterNameController = TextEditingController();
  String? _creatingFilterId;

  @override
  void dispose() {
    _filterNameController.dispose();
    super.dispose();
  }

  void _startCreatingFilter(String sourceFilterId) {
    setState(() {
      _creatingFilterId = sourceFilterId;
      _filterNameController.clear();
    });
  }

  void _cancelCreatingFilter() {
    setState(() {
      _creatingFilterId = null;
      _filterNameController.clear();
    });
  }

  Future<void> _saveCustomFilter(ImageFilter sourceFilter) async {
    final name = _filterNameController.text.trim();
    if (name.isEmpty) return;

    await ref.read(imageFilterProvider.notifier).createCustomFilter(name, sourceFilter);
    _cancelCreatingFilter();
  }

  void _showDeleteDialog(ImageFilter filter) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Filter'),
        content: Text('Are you sure you want to delete "${filter.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await ref.read(imageFilterProvider.notifier).deleteFilter(filter.id);
            },
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showResetDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Filters'),
        content: const Text('This will delete all custom filters. Preset filters will remain.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await ref.read(imageFilterProvider.notifier).resetFilters();
            },
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filterState = ref.watch(imageFilterProvider);

    return AppScaffold(
      title: 'Image Filters',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _showResetDialog,
          tooltip: 'Reset to defaults',
        ),
      ],
      body: filterState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(AppTheme.spacingLg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionHeader('Preset Filters'),
                  ...ImageFilter.presets.map((filter) => _buildFilterTile(filter, isCustom: false)),
                  if (filterState.customFilters.isNotEmpty) ...[
                    const SizedBox(height: AppTheme.spacingLg),
                    _buildSectionHeader('Custom Filters'),
                    ...filterState.customFilters.map((filter) => _buildFilterTile(filter, isCustom: true)),
                  ],
                  const SizedBox(height: AppTheme.spacingLg * 1.5),
                  _buildInfoCard(),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spacingMd),
      child: Text(
        title,
        style: AppTheme.headlineSmall,
      ),
    );
  }

  Widget _buildFilterTile(ImageFilter filter, {required bool isCustom}) {
    final filterState = ref.watch(imageFilterProvider);
    final isCreating = _creatingFilterId == filter.id;
    final isSelected = filterState.selectedFilterId == filter.id;

    return Card(
      margin: const EdgeInsets.only(bottom: AppTheme.spacingMd),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        filter.name,
                        style: AppTheme.textTheme.titleMedium?.copyWith(
                          color: isSelected ? AppTheme.royalPurple : null,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        ),
                      ),
                      if (filter.id != 'none') ...[
                        const SizedBox(height: 4),
                        _buildFilterDetails(filter),
                      ],
                    ],
                  ),
                ),
                if (isCreating)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.check),
                        onPressed: () => _saveCustomFilter(filter),
                        color: AppTheme.success,
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: _cancelCreatingFilter,
                      ),
                    ],
                  )
                else
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!isCustom && filter.id != 'none')
                        IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: () => _startCreatingFilter(filter.id),
                          tooltip: 'Create custom filter from this',
                        ),
                      if (isCustom)
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _showDeleteDialog(filter),
                          color: AppTheme.error,
                        ),
                      if (filter.id != 'none')
                        IconButton(
                          icon: Icon(
                            isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                            color: isSelected ? AppTheme.royalPurple : null,
                          ),
                          onPressed: () {
                            ref.read(imageFilterProvider.notifier).selectFilter(filter.id);
                          },
                        ),
                    ],
                  ),
              ],
            ),
            if (isCreating) ...[
              const SizedBox(height: AppTheme.spacingMd),
              TextField(
                controller: _filterNameController,
                decoration: const InputDecoration(
                  labelText: 'Filter Name',
                  hintText: 'Enter a name for your custom filter',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _saveCustomFilter(filter),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFilterDetails(ImageFilter filter) {
    final details = <String>[];
    
    if (filter.brightness != 1.0) {
      details.add('Brightness: ${(filter.brightness * 100).toStringAsFixed(0)}%');
    }
    if (filter.contrast != 1.0) {
      details.add('Contrast: ${(filter.contrast * 100).toStringAsFixed(0)}%');
    }
    if (filter.saturation != 1.0) {
      details.add('Saturation: ${(filter.saturation * 100).toStringAsFixed(0)}%');
    }
    if (filter.warmth != 1.0) {
      details.add('Warmth: ${(filter.warmth * 100).toStringAsFixed(0)}%');
    }
    if (filter.vignette > 0) {
      details.add('Vignette: ${(filter.vignette * 100).toStringAsFixed(0)}%');
    }
    if (filter.fade > 0) {
      details.add('Fade: ${(filter.fade * 100).toStringAsFixed(0)}%');
    }

    if (details.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: details.map((detail) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: AppTheme.egyptianBlue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            detail,
            style: AppTheme.textTheme.labelSmall?.copyWith(
              color: AppTheme.egyptianBlue,
              fontSize: 10,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      decoration: BoxDecoration(
        color: AppTheme.royalPurple.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.royalPurple.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: AppTheme.royalPurple),
              const SizedBox(width: AppTheme.spacingSm),
              Text(
                'About Filters',
                style: AppTheme.textTheme.titleMedium?.copyWith(
                  color: AppTheme.royalPurple,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingMd),
          Text(
            'Filters are applied to images before upload. Custom filters can be created from presets. '
            'The original image is preserved - filters only affect the uploaded version.',
            style: AppTheme.textTheme.bodySmall?.copyWith(
              color: AppTheme.navyText.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: AppTheme.spacingMd),
          _buildTip('Tap the radio button to select a default filter'),
          _buildTip('Tap + on any filter to create a custom version'),
          _buildTip('Custom filters are saved to your device'),
        ],
      ),
    );
  }

  Widget _buildTip(String tip) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('• ', style: AppTheme.textTheme.bodySmall?.copyWith(color: AppTheme.royalPurple)),
          Expanded(
            child: Text(
              tip,
              style: AppTheme.textTheme.bodySmall?.copyWith(
                color: AppTheme.navyText.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
