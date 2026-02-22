// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'package:flutter/material.dart';
import '../../models/profile_widgets.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../utils/snackbar_ext.dart';
import '../../widgets/profile_widgets/profile_widget_renderer.dart';

/// Full-screen editor for customizing the user's MySpace-style profile layout.
class ProfileLayoutEditor extends StatefulWidget {
  const ProfileLayoutEditor({super.key});

  @override
  State<ProfileLayoutEditor> createState() => _ProfileLayoutEditorState();
}

class _ProfileLayoutEditorState extends State<ProfileLayoutEditor> {
  ProfileLayout? _layout;
  bool _loading = true;
  bool _saving = false;
  late List<ProfileWidget> _widgets;
  String _theme = 'default';

  @override
  void initState() {
    super.initState();
    _loadLayout();
  }

  Future<void> _loadLayout() async {
    try {
      final data = await ApiService.instance.callGoApi('/profile/layout', method: 'GET');
      final layout = ProfileLayout.fromJson(data);
      if (mounted) {
        setState(() {
          _layout = layout;
          _widgets = List.of(layout.widgets);
          _theme = layout.theme;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _widgets = [];
          _loading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    // Reindex orders
    for (int i = 0; i < _widgets.length; i++) {
      _widgets[i] = _widgets[i].copyWith(order: i);
    }

    try {
      await ApiService.instance.callGoApi('/profile/layout', method: 'PUT', body: {
        'widgets': _widgets.map((w) => w.toJson()).toList(),
        'theme': _theme,
        'accent_color': _layout?.accentColor?.value.toRadixString(16),
        'banner_image_url': _layout?.bannerImageUrl,
      });
      if (mounted) {
        context.showSuccess('Profile layout saved');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) context.showError('Failed to save layout');
    }
    if (mounted) setState(() => _saving = false);
  }

  void _addWidget(ProfileWidgetType type) {
    setState(() {
      _widgets.add(ProfileWidget(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        type: type,
        config: {},
        order: _widgets.length,
      ));
    });
  }

  void _removeWidget(int index) {
    setState(() => _widgets.removeAt(index));
  }

  void _editWidgetConfig(int index) {
    final w = _widgets[index];
    // Only quote and customText have editable config for now
    if (w.type == ProfileWidgetType.quote) {
      _showQuoteEditor(index, w);
    } else if (w.type == ProfileWidgetType.customText) {
      _showCustomTextEditor(index, w);
    }
  }

  void _showQuoteEditor(int index, ProfileWidget w) {
    final textCtrl = TextEditingController(text: w.config['text'] as String? ?? '');
    final authorCtrl = TextEditingController(text: w.config['author'] as String? ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Quote'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: textCtrl, decoration: const InputDecoration(labelText: 'Quote text'), maxLines: 3),
            const SizedBox(height: 8),
            TextField(controller: authorCtrl, decoration: const InputDecoration(labelText: 'Author (optional)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              setState(() {
                _widgets[index] = w.copyWith(config: {
                  'text': textCtrl.text,
                  'author': authorCtrl.text,
                });
              });
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showCustomTextEditor(int index, ProfileWidget w) {
    final titleCtrl = TextEditingController(text: w.config['title'] as String? ?? '');
    final bodyCtrl = TextEditingController(text: w.config['body'] as String? ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Text Block'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Title (optional)')),
            const SizedBox(height: 8),
            TextField(controller: bodyCtrl, decoration: const InputDecoration(labelText: 'Content'), maxLines: 4),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              setState(() {
                _widgets[index] = w.copyWith(config: {
                  'title': titleCtrl.text,
                  'body': bodyCtrl.text,
                });
              });
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit Profile Layout')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final currentTheme = ProfileTheme.getThemeByName(_theme);
    final usedTypes = _widgets.map((w) => w.type).toSet();
    final availableTypes = ProfileWidgetType.values.where((t) => !usedTypes.contains(t)).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile Layout'),
        actions: [
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Row(
        children: [
          // Editor panel
          SizedBox(
            width: 320,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Theme picker
                Padding(
                  padding: const EdgeInsets.all(SojornSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Theme', style: TextStyle(color: AppTheme.navyText, fontWeight: FontWeight.w700, fontSize: 14)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: ProfileTheme.availableThemes.map((t) {
                          final isSelected = t.name == _theme;
                          return ChoiceChip(
                            label: Text(t.name[0].toUpperCase() + t.name.substring(1)),
                            selected: isSelected,
                            onSelected: (_) => setState(() => _theme = t.name),
                            selectedColor: t.accentColor.withValues(alpha: 0.2),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // Widgets list
                Padding(
                  padding: const EdgeInsets.fromLTRB(SojornSpacing.md, SojornSpacing.md, SojornSpacing.md, 8),
                  child: Text('Widgets', style: TextStyle(color: AppTheme.navyText, fontWeight: FontWeight.w700, fontSize: 14)),
                ),
                Expanded(
                  child: _widgets.isEmpty
                      ? Center(
                          child: Text('Add widgets below', style: TextStyle(color: SojornColors.textDisabled, fontSize: 13)),
                        )
                      : ReorderableListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: SojornSpacing.md),
                          itemCount: _widgets.length,
                          onReorder: (oldIndex, newIndex) {
                            setState(() {
                              if (newIndex > oldIndex) newIndex--;
                              final item = _widgets.removeAt(oldIndex);
                              _widgets.insert(newIndex, item);
                            });
                          },
                          itemBuilder: (context, index) {
                            final w = _widgets[index];
                            return ListTile(
                              key: ValueKey(w.id),
                              dense: true,
                              leading: Icon(w.type.icon, size: 18, color: currentTheme.accentColor),
                              title: Text(w.type.displayName, style: const TextStyle(fontSize: 13)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (w.type == ProfileWidgetType.quote || w.type == ProfileWidgetType.customText)
                                    IconButton(
                                      icon: const Icon(Icons.edit, size: 16),
                                      onPressed: () => _editWidgetConfig(index),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    icon: const Icon(Icons.close, size: 16),
                                    onPressed: () => _removeWidget(index),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),

                // Add widget catalog
                if (availableTypes.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(SojornSpacing.md),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: Colors.grey.withValues(alpha: 0.2))),
                    ),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: availableTypes.map((t) => ActionChip(
                        avatar: Icon(t.icon, size: 14),
                        label: Text(t.displayName, style: const TextStyle(fontSize: 11)),
                        onPressed: () => _addWidget(t),
                      )).toList(),
                    ),
                  ),
              ],
            ),
          ),
          // Preview panel
          Expanded(
            child: Container(
              color: currentTheme.backgroundColor,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(SojornSpacing.lg),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 500),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Preview', style: TextStyle(color: currentTheme.textColor, fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(height: SojornSpacing.md),
                        ProfileWidgetRenderer(
                          layout: ProfileLayout(
                            widgets: _widgets,
                            theme: _theme,
                            accentColor: _layout?.accentColor,
                            bannerImageUrl: _layout?.bannerImageUrl,
                            updatedAt: DateTime.now(),
                          ),
                          isOwnProfile: true,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
