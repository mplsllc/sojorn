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

  void _moveToOtherSidebar(DashboardWidgetType type, bool currentlyInLeft) {
    setState(() {
      final from = currentlyInLeft ? _left : _right;
      final to = currentlyInLeft ? _right : _left;
      final idx = from.indexWhere((w) => w.type == type);
      if (idx < 0) return;
      final widget = from.removeAt(idx);
      to.add(widget.copyWith(order: to.length));
    });
    _fireChange();
  }

  void _updateConfig(DashboardWidgetType type, Map<String, dynamic> newConfig) {
    setState(() {
      for (int i = 0; i < _left.length; i++) {
        if (_left[i].type == type) {
          _left[i] = _left[i].copyWith(config: newConfig);
          return;
        }
      }
      for (int i = 0; i < _right.length; i++) {
        if (_right[i].type == type) {
          _right[i] = _right[i].copyWith(config: newConfig);
          return;
        }
      }
    });
    _fireChange();
  }

  @override
  Widget build(BuildContext context) {
    final used = _usedTypes;
    final unusedTypes = DashboardWidgetType.values
        .where((t) =>
            !used.contains(t) &&
            t != DashboardWidgetType.musicPlayer &&
            t != DashboardWidgetType.nowPlaying)
        .toList();

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
            isLeft: isLeft,
            onToggle: (val) => _toggleWidget(widgets, index, val),
            onRemove: w.type.isRemovable ? () => _removeWidget(w.type) : null,
            onMove: () => _moveToOtherSidebar(w.type, isLeft),
            onConfigChange: (cfg) => _updateConfig(w.type, cfg),
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

// Widget types that support a configurable item count.
const _maxItemsTypes = {
  DashboardWidgetType.upcomingEvents,
  DashboardWidgetType.groupEvents,
  DashboardWidgetType.friendActivity,
  DashboardWidgetType.whosOnline,
};

const _maxItemsDefaults = {
  DashboardWidgetType.upcomingEvents: 3,
  DashboardWidgetType.groupEvents: 5,
  DashboardWidgetType.friendActivity: 5,
  DashboardWidgetType.whosOnline: 10,
};

/// Single widget row inside the editor list.
class _WidgetTile extends StatefulWidget {
  final DashboardWidget widget;
  final int index;
  final bool isLeft;
  final ValueChanged<bool> onToggle;
  final VoidCallback? onRemove;
  final VoidCallback onMove;
  final ValueChanged<Map<String, dynamic>> onConfigChange;

  const _WidgetTile({
    super.key,
    required this.widget,
    required this.index,
    required this.isLeft,
    required this.onToggle,
    required this.onMove,
    required this.onConfigChange,
    this.onRemove,
  });

  @override
  State<_WidgetTile> createState() => _WidgetTileState();
}

class _WidgetTileState extends State<_WidgetTile> {
  bool _expanded = false;

  bool get _hasSettings => _maxItemsTypes.contains(widget.widget.type);

  int get _currentMaxItems =>
      widget.widget.config['max_items'] as int? ??
      _maxItemsDefaults[widget.widget.type] ??
      5;

  void _setMaxItems(int value) {
    final newConfig = Map<String, dynamic>.from(widget.widget.config)
      ..['max_items'] = value;
    widget.onConfigChange(newConfig);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                  color: AppTheme.royalPurple.withValues(alpha: 0.06)),
            ),
          ),
          child: ListTile(
            dense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            leading: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ReorderableDragStartListener(
                  index: widget.index,
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
                  child: Icon(widget.widget.type.icon,
                      size: 16, color: AppTheme.royalPurple),
                ),
              ],
            ),
            title: Text(widget.widget.type.displayName,
                style: TextStyle(
                  color: widget.widget.isEnabled
                      ? AppTheme.navyText
                      : AppTheme.navyText.withValues(alpha: 0.4),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                )),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Move to other sidebar
                Tooltip(
                  message: widget.isLeft
                      ? 'Move to Right Sidebar'
                      : 'Move to Left Sidebar',
                  child: IconButton(
                    icon: Icon(
                      widget.isLeft
                          ? Icons.arrow_forward
                          : Icons.arrow_back,
                      size: 15,
                      color: AppTheme.navyText.withValues(alpha: 0.4),
                    ),
                    onPressed: widget.onMove,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ),
                const SizedBox(width: 4),
                // Settings expand (only for configurable types)
                if (_hasSettings)
                  IconButton(
                    icon: Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.tune_outlined,
                      size: 15,
                      color: _expanded
                          ? AppTheme.royalPurple
                          : AppTheme.navyText.withValues(alpha: 0.4),
                    ),
                    onPressed: () => setState(() => _expanded = !_expanded),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Settings',
                  ),
                if (!_hasSettings) const SizedBox(width: 19),
                const SizedBox(width: 4),
                SizedBox(
                  height: 28,
                  child: Switch(
                    value: widget.widget.isEnabled,
                    activeColor: AppTheme.royalPurple,
                    activeTrackColor:
                        AppTheme.royalPurple.withValues(alpha: 0.35),
                    inactiveThumbColor: const Color(0xFFCBD5E1),
                    inactiveTrackColor: const Color(0xFFE2E8F0),
                    onChanged: widget.onToggle,
                  ),
                ),
                if (widget.onRemove != null)
                  IconButton(
                    icon: Icon(Icons.close,
                        size: 16,
                        color: AppTheme.navyText.withValues(alpha: 0.3)),
                    onPressed: widget.onRemove,
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
        ),
        // Expandable settings panel
        if (_expanded && _hasSettings)
          Container(
            color: AppTheme.royalPurple.withValues(alpha: 0.03),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Text('Show items:',
                    style: TextStyle(
                        color: AppTheme.navyText.withValues(alpha: 0.6),
                        fontSize: 12)),
                const Spacer(),
                _StepperButton(
                  icon: Icons.remove,
                  onPressed: _currentMaxItems > 1
                      ? () => _setMaxItems(_currentMaxItems - 1)
                      : null,
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 28,
                  child: Text(
                    '$_currentMaxItems',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: AppTheme.navyText,
                        fontSize: 13,
                        fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 8),
                _StepperButton(
                  icon: Icons.add,
                  onPressed: _currentMaxItems < 20
                      ? () => _setMaxItems(_currentMaxItems + 1)
                      : null,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;

  const _StepperButton({required this.icon, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: onPressed != null
              ? AppTheme.royalPurple.withValues(alpha: 0.1)
              : AppTheme.royalPurple.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon,
            size: 14,
            color: onPressed != null
                ? AppTheme.royalPurple
                : AppTheme.royalPurple.withValues(alpha: 0.3)),
      ),
    );
  }
}
