// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'package:flutter/material.dart';
import '../../models/dashboard_widgets.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../utils/snackbar_ext.dart';

/// Bottom sheet editor for customizing dashboard widget layout.
/// Users can toggle widgets on/off and reorder them per sidebar.
class DashboardEditorSheet extends StatefulWidget {
  final DashboardLayout layout;
  final ValueChanged<DashboardLayout> onSaved;

  const DashboardEditorSheet({
    super.key,
    required this.layout,
    required this.onSaved,
  });

  /// Show the editor as a modal bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required DashboardLayout layout,
    required ValueChanged<DashboardLayout> onSaved,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(SojornRadii.modal)),
      ),
      builder: (_) => DashboardEditorSheet(layout: layout, onSaved: onSaved),
    );
  }

  @override
  State<DashboardEditorSheet> createState() => _DashboardEditorSheetState();
}

class _DashboardEditorSheetState extends State<DashboardEditorSheet> {
  late List<DashboardWidget> _left;
  late List<DashboardWidget> _right;
  bool _saving = false;

  /// Widget types available in the catalog (ones not already placed).
  static const _allTypes = DashboardWidgetType.values;

  @override
  void initState() {
    super.initState();
    _left = List.of(widget.layout.leftSidebar);
    _right = List.of(widget.layout.rightSidebar);
  }

  Set<DashboardWidgetType> get _usedTypes => {
        ..._left.map((w) => w.type),
        ..._right.map((w) => w.type),
      };

  Future<void> _save() async {
    setState(() => _saving = true);
    // Reindex orders
    for (int i = 0; i < _left.length; i++) {
      _left[i] = _left[i].copyWith(order: i);
    }
    for (int i = 0; i < _right.length; i++) {
      _right[i] = _right[i].copyWith(order: i);
    }

    final layout = DashboardLayout(
      leftSidebar: _left,
      rightSidebar: _right,
    );

    try {
      await ApiService.instance.saveDashboardLayout(layout.toJson());
      if (mounted) {
        widget.onSaved(layout);
        Navigator.pop(context);
        context.showSuccess('Dashboard saved');
      }
    } catch (e) {
      if (mounted) context.showError('Failed to save');
    }
    if (mounted) setState(() => _saving = false);
  }

  void _addWidget(DashboardWidgetType type, bool toLeft) {
    setState(() {
      final list = toLeft ? _left : _right;
      list.add(DashboardWidget(type: type, order: list.length));
    });
  }

  void _removeWidget(DashboardWidgetType type) {
    setState(() {
      _left.removeWhere((w) => w.type == type);
      _right.removeWhere((w) => w.type == type);
    });
  }

  @override
  Widget build(BuildContext context) {
    final used = _usedTypes;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.9,
      minChildSize: 0.5,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.all(SojornSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Customize Dashboard',
                    style: TextStyle(
                      color: AppTheme.navyText,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    )),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Save'),
                ),
              ],
            ),
            const SizedBox(height: SojornSpacing.md),

            Expanded(
              child: ListView(
                controller: scrollController,
                children: [
                  // Left sidebar section
                  _buildSectionHeader('Left Sidebar'),
                  _buildWidgetList(_left, true),
                  const SizedBox(height: SojornSpacing.md),

                  // Right sidebar section
                  _buildSectionHeader('Right Sidebar'),
                  _buildWidgetList(_right, false),
                  const SizedBox(height: SojornSpacing.lg),

                  // Available widgets catalog
                  _buildSectionHeader('Add Widgets'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _allTypes
                        .where((t) => !used.contains(t))
                        .map((t) => _buildCatalogChip(t))
                        .toList(),
                  ),
                  if (used.length == _allTypes.length)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('All widgets placed',
                          style: TextStyle(color: AppTheme.navyText.withValues(alpha: 0.4), fontSize: 12)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title,
          style: TextStyle(
            color: AppTheme.navyText,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          )),
    );
  }

  Widget _buildWidgetList(List<DashboardWidget> widgets, bool isLeft) {
    if (widgets.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text('No widgets — add from catalog below',
            style: TextStyle(color: AppTheme.navyText.withValues(alpha: 0.4), fontSize: 12)),
      );
    }

    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: widgets.length,
      onReorder: (oldIndex, newIndex) {
        setState(() {
          if (newIndex > oldIndex) newIndex--;
          final item = widgets.removeAt(oldIndex);
          widgets.insert(newIndex, item);
        });
      },
      itemBuilder: (context, index) {
        final w = widgets[index];
        return ListTile(
          key: ValueKey('${isLeft ? "L" : "R"}_${w.type.value}'),
          dense: true,
          leading: Icon(w.type.icon, size: 20, color: AppTheme.royalPurple),
          title: Text(w.type.displayName,
              style: TextStyle(color: AppTheme.navyText, fontSize: 13, fontWeight: FontWeight.w600)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Toggle enabled
              Switch(
                value: w.isEnabled,
                activeThumbColor: AppTheme.royalPurple,
                onChanged: (val) {
                  setState(() {
                    widgets[index] = w.copyWith(isEnabled: val);
                  });
                },
              ),
              // Remove
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                onPressed: () => _removeWidget(w.type),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCatalogChip(DashboardWidgetType type) {
    return PopupMenuButton<bool>(
      onSelected: (toLeft) => _addWidget(type, toLeft),
      itemBuilder: (_) => [
        const PopupMenuItem(value: true, child: Text('Add to Left Sidebar')),
        const PopupMenuItem(value: false, child: Text('Add to Right Sidebar')),
      ],
      child: Chip(
        avatar: Icon(type.icon, size: 16, color: AppTheme.royalPurple),
        label: Text(type.displayName, style: const TextStyle(fontSize: 12)),
        backgroundColor: AppTheme.royalPurple.withValues(alpha: 0.08),
        side: BorderSide(color: AppTheme.royalPurple.withValues(alpha: 0.2)),
      ),
    );
  }
}
