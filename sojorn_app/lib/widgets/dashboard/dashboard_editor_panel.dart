// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import '../../models/dashboard_widgets.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../utils/snackbar_ext.dart';

/// Inline dashboard editor that replaces the center feed column.
/// Shows left/right sidebar widget lists with add/remove/toggle/reorder
/// and fires [onLayoutChanged] on every mutation so sidebars update live.
class DashboardEditorPanel extends StatefulWidget {
  final DashboardLayout layout;
  final ValueChanged<DashboardLayout> onLayoutChanged;
  final VoidCallback onClose;

  const DashboardEditorPanel({
    super.key,
    required this.layout,
    required this.onLayoutChanged,
    required this.onClose,
  });

  @override
  State<DashboardEditorPanel> createState() => _DashboardEditorPanelState();
}

class _DashboardEditorPanelState extends State<DashboardEditorPanel> {
  late List<DashboardWidget> _left;
  late List<DashboardWidget> _right;
  bool _saving = false;

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

  void _fireChange() {
    _reindex();
    widget.onLayoutChanged(DashboardLayout(
      leftSidebar: List.of(_left),
      rightSidebar: List.of(_right),
    ));
  }

  void _reindex() {
    for (int i = 0; i < _left.length; i++) {
      _left[i] = _left[i].copyWith(order: i);
    }
    for (int i = 0; i < _right.length; i++) {
      _right[i] = _right[i].copyWith(order: i);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    _reindex();
    final layout = DashboardLayout(leftSidebar: _left, rightSidebar: _right);
    try {
      await ApiService.instance.saveDashboardLayout(layout.toJson());
      if (mounted) {
        widget.onLayoutChanged(layout);
        context.showSuccess('Dashboard saved');
        widget.onClose();
      }
    } catch (e) {
      if (mounted) context.showError('Failed to save: $e');
    }
    if (mounted) setState(() => _saving = false);
  }

  void _addWidget(DashboardWidgetType type, bool toLeft) {
    setState(() {
      final list = toLeft ? _left : _right;
      list.add(DashboardWidget(type: type, order: list.length));
    });
    _fireChange();
  }

  void _removeWidget(DashboardWidgetType type) {
    if (!type.isRemovable) return;
    setState(() {
      _left.removeWhere((w) => w.type == type);
      _right.removeWhere((w) => w.type == type);
    });
    _fireChange();
  }

  void _toggleWidget(List<DashboardWidget> list, int index, bool enabled) {
    setState(() {
      list[index] = list[index].copyWith(isEnabled: enabled);
    });
    _fireChange();
  }

  void _reorder(List<DashboardWidget> list, int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final item = list.removeAt(oldIndex);
      list.insert(newIndex, item);
    });
    _fireChange();
  }

  @override
  Widget build(BuildContext context) {
    final used = _usedTypes;
    final unusedTypes =
        DashboardWidgetType.values.where((t) => !used.contains(t)).toList();

    return Column(
      children: [
        // ── Header bar ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: AppTheme.cardSurface,
            border: Border(
              bottom: BorderSide(
                  color: AppTheme.royalPurple.withValues(alpha: 0.1)),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.dashboard_customize_outlined,
                  color: AppTheme.royalPurple, size: 22),
              const SizedBox(width: 10),
              Text(
                'Customize Dashboard',
                style: TextStyle(
                  color: AppTheme.navyText,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: widget.onClose,
                child: Text('Cancel',
                    style: TextStyle(
                        color: AppTheme.navyText.withValues(alpha: 0.6),
                        fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.royalPurple,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Save',
                        style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
        // ── Body ──
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _buildSectionHeader('Left Sidebar', Icons.view_sidebar_outlined),
              const SizedBox(height: 8),
              _buildWidgetList(_left, true),
              const SizedBox(height: 24),
              _buildSectionHeader(
                  'Right Sidebar', Icons.view_sidebar_outlined),
              const SizedBox(height: 8),
              _buildWidgetList(_right, false),
              const SizedBox(height: 28),
              _buildSectionHeader('Add Widgets', Icons.add_circle_outline),
              const SizedBox(height: 12),
              if (unusedTypes.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('All widgets placed',
                      style: TextStyle(
                          color: AppTheme.navyText.withValues(alpha: 0.4),
                          fontSize: 12)),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children:
                      unusedTypes.map((t) => _buildCatalogChip(t)).toList(),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppTheme.royalPurple.withValues(alpha: 0.6)),
        const SizedBox(width: 6),
        Text(title,
            style: TextStyle(
              color: AppTheme.navyText,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            )),
      ],
    );
  }

  Widget _buildWidgetList(List<DashboardWidget> widgets, bool isLeft) {
    if (widgets.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          border: Border.all(
              color: AppTheme.royalPurple.withValues(alpha: 0.15),
              style: BorderStyle.solid),
          borderRadius: BorderRadius.circular(SojornRadii.card),
          color: AppTheme.royalPurple.withValues(alpha: 0.03),
        ),
        child: Center(
          child: Text('No widgets — add from catalog below',
              style: TextStyle(
                  color: AppTheme.navyText.withValues(alpha: 0.4),
                  fontSize: 12)),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(SojornRadii.card),
        boxShadow: [
          BoxShadow(
            color: AppTheme.royalPurple.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: widgets.length,
        onReorder: (old, neu) => _reorder(widgets, old, neu),
        buildDefaultDragHandles: false,
        itemBuilder: (context, index) {
          final w = widgets[index];
          return _WidgetTile(
            key: ValueKey('${isLeft ? "L" : "R"}_${w.type.value}'),
            widget: w,
            index: index,
            onToggle: (val) => _toggleWidget(widgets, index, val),
            onRemove: w.type.isRemovable ? () => _removeWidget(w.type) : null,
          );
        },
      ),
    );
  }

  Widget _buildCatalogChip(DashboardWidgetType type) {
    return PopupMenuButton<bool>(
      onSelected: (toLeft) => _addWidget(type, toLeft),
      tooltip: 'Add ${type.displayName}',
      itemBuilder: (_) => [
        const PopupMenuItem(value: true, child: Text('Add to Left Sidebar')),
        const PopupMenuItem(value: false, child: Text('Add to Right Sidebar')),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.royalPurple.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border:
              Border.all(color: AppTheme.royalPurple.withValues(alpha: 0.15)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(type.icon, size: 16, color: AppTheme.royalPurple),
            const SizedBox(width: 6),
            Text(type.displayName,
                style: TextStyle(
                    color: AppTheme.navyText,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            const SizedBox(width: 4),
            Icon(Icons.add,
                size: 14,
                color: AppTheme.royalPurple.withValues(alpha: 0.6)),
          ],
        ),
      ),
    );
  }
}

/// Single widget row inside the editor list.
class _WidgetTile extends StatelessWidget {
  final DashboardWidget widget;
  final int index;
  final ValueChanged<bool> onToggle;
  final VoidCallback? onRemove;

  const _WidgetTile({
    super.key,
    required this.widget,
    required this.index,
    required this.onToggle,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
              color: AppTheme.royalPurple.withValues(alpha: 0.06)),
        ),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ReorderableDragStartListener(
              index: index,
              child: Icon(Icons.drag_indicator,
                  size: 18,
                  color: AppTheme.navyText.withValues(alpha: 0.3)),
            ),
            const SizedBox(width: 8),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppTheme.royalPurple.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(widget.type.icon,
                  size: 16, color: AppTheme.royalPurple),
            ),
          ],
        ),
        title: Text(widget.type.displayName,
            style: TextStyle(
              color: widget.isEnabled
                  ? AppTheme.navyText
                  : AppTheme.navyText.withValues(alpha: 0.4),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            )),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 28,
              child: Switch(
                value: widget.isEnabled,
                // Active: brand purple thumb on lighter purple track.
                activeColor: AppTheme.royalPurple,
                activeTrackColor: AppTheme.royalPurple.withValues(alpha: 0.35),
                // Inactive: clearly neutral grey so on/off is unambiguous at a glance.
                inactiveThumbColor: const Color(0xFFCBD5E1),
                inactiveTrackColor: const Color(0xFFE2E8F0),
                onChanged: onToggle,
              ),
            ),
            if (onRemove != null)
              IconButton(
                icon: Icon(Icons.close,
                    size: 16,
                    color: AppTheme.navyText.withValues(alpha: 0.3)),
                onPressed: onRemove,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Remove',
              )
            else
              Tooltip(
                message: 'This widget is always visible',
                child: Icon(Icons.lock_outline,
                    size: 14,
                    color: AppTheme.navyText.withValues(alpha: 0.2)),
              ),
          ],
        ),
      ),
    );
  }
}
