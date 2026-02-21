// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'package:flutter/material.dart';
import 'package:sojorn/models/profile_widgets.dart';
import 'package:sojorn/widgets/profile/profile_widget_renderer.dart';
import '../../theme/app_theme.dart';

class DraggableWidgetGrid extends StatefulWidget {
  final List<ProfileWidget> widgets;
  final Function(List<ProfileWidget>)? onWidgetsReordered;
  final Function(ProfileWidget)? onWidgetAdded;
  final Function(ProfileWidget)? onWidgetRemoved;
  final ProfileTheme theme;
  final bool isEditable;

  const DraggableWidgetGrid({
    super.key,
    required this.widgets,
    this.onWidgetsReordered,
    this.onWidgetAdded,
    this.onWidgetRemoved,
    required this.theme,
    this.isEditable = true,
  });

  @override
  State<DraggableWidgetGrid> createState() => _DraggableWidgetGridState();
}

class _DraggableWidgetGridState extends State<DraggableWidgetGrid> {
  late List<ProfileWidget> _widgets;
  final GlobalKey _gridKey = GlobalKey();
  int? _draggedIndex;
  bool _showAddButton = false;

  @override
  void initState() {
    super.initState();
    _widgets = List.from(widget.widgets);
    _sortWidgetsByOrder();
  }

  @override
  void didUpdateWidget(DraggableWidgetGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.widgets != widget.widgets) {
      _widgets = List.from(widget.widgets);
      _sortWidgetsByOrder();
    }
  }

  void _sortWidgetsByOrder() {
    _widgets.sort((a, b) => a.order.compareTo(b.order));
  }

  void _onWidgetReordered(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;

    setState(() {
      final widget = _widgets.removeAt(oldIndex);
      _widgets.insert(newIndex, widget);
      
      // Update order values
      for (int i = 0; i < _widgets.length; i++) {
        _widgets[i] = _widgets[i].copyWith(order: i);
      }
    });

    widget.onWidgetsReordered?.call(_widgets);
  }

  void _onWidgetTapped(ProfileWidget widget, int index) {
    if (!this.widget.isEditable) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildWidgetOptions(widget, index),
    );
  }

  Widget _buildWidgetOptions(ProfileWidget widget, int index) {
    final theme = this.widget.theme;
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.backgroundColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.primaryColor.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  widget.type.icon,
                  color: theme.primaryColor,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.type.displayName,
                  style: TextStyle(
                    color: theme.textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(
                    Icons.close,
                    color: theme.textColor,
                  ),
                ),
              ],
            ),
          ),

          // Options
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Remove widget
                ListTile(
                  leading: const Icon(
                    Icons.delete_outline,
                    color: Colors.red,
                  ),
                  title: Text(
                    'Remove Widget',
                    style: TextStyle(
                      color: theme.textColor,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _removeWidget(widget, index);
                  },
                ),

                // Edit widget (if supported)
                if (_canEditWidget(widget)) ...[
                  ListTile(
                    leading: Icon(
                      Icons.edit,
                      color: theme.primaryColor,
                    ),
                    title: Text(
                      'Edit Widget',
                      style: TextStyle(
                        color: theme.textColor,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _editWidget(widget, index);
                    },
                  ),
                ],

                // Move to top
                ListTile(
                  leading: Icon(
                    Icons.keyboard_arrow_up,
                    color: theme.primaryColor,
                  ),
                  title: Text(
                    'Move to Top',
                    style: TextStyle(
                      color: theme.textColor,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _moveWidgetToTop(index);
                  },
                ),

                // Move to bottom
                ListTile(
                  leading: Icon(
                    Icons.keyboard_arrow_down,
                    color: theme.primaryColor,
                  ),
                  title: Text(
                    'Move to Bottom',
                    style: TextStyle(
                      color: theme.textColor,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _moveWidgetToBottom(index);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _canEditWidget(ProfileWidget widget) {
    // Define which widgets can be edited
    switch (widget.type) {
      case ProfileWidgetType.customText:
      case ProfileWidgetType.socialLinks:
      case ProfileWidgetType.quote:
        return true;
      default:
        return false;
    }
  }

  void _removeWidget(ProfileWidget widget, int index) {
    setState(() {
      _widgets.removeAt(index);
      _updateOrderValues();
    });
    this.widget.onWidgetRemoved?.call(widget);
  }

  void _editWidget(ProfileWidget widget, int index) {
    // Navigate to widget-specific edit screen
    switch (widget.type) {
      case ProfileWidgetType.customText:
        _showCustomTextEdit(widget, index);
        break;
      case ProfileWidgetType.socialLinks:
        _showSocialLinksEdit(widget, index);
        break;
      case ProfileWidgetType.quote:
        _showQuoteEdit(widget, index);
        break;
    }
  }

  void _showCustomTextEdit(ProfileWidget widget, int index) {
    showDialog(
      context: context,
      builder: (context) => _CustomTextEditDialog(
        widget: widget,
        onSave: (updatedWidget) {
          setState(() {
            _widgets[index] = updatedWidget;
          });
          this.widget.onWidgetAdded?.call(updatedWidget);
        },
      ),
    );
  }

  void _showSocialLinksEdit(ProfileWidget widget, int index) {
    showDialog(
      context: context,
      builder: (context) => _SocialLinksEditDialog(
        widget: widget,
        onSave: (updatedWidget) {
          setState(() {
            _widgets[index] = updatedWidget;
          });
          this.widget.onWidgetAdded?.call(updatedWidget);
        },
      ),
    );
  }

  void _showQuoteEdit(ProfileWidget widget, int index) {
    showDialog(
      context: context,
      builder: (context) => _QuoteEditDialog(
        widget: widget,
        onSave: (updatedWidget) {
          setState(() {
            _widgets[index] = updatedWidget;
          });
          this.widget.onWidgetAdded?.call(updatedWidget);
        },
      ),
    );
  }

  void _moveWidgetToTop(int index) {
    if (index == 0) return;
    
    setState(() {
      final widget = _widgets.removeAt(index);
      _widgets.insert(0, widget);
      _updateOrderValues();
    });
    widget.onWidgetsReordered?.call(_widgets);
  }

  void _moveWidgetToBottom(int index) {
    if (index == _widgets.length - 1) return;
    
    setState(() {
      final widget = _widgets.removeAt(index);
      _widgets.add(widget);
      _updateOrderValues();
    });
    widget.onWidgetsReordered?.call(_widgets);
  }

  void _updateOrderValues() {
    for (int i = 0; i < _widgets.length; i++) {
      _widgets[i] = _widgets[i].copyWith(order: i);
    }
  }

  void _showAddWidgetDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildAddWidgetDialog(),
    );
  }

  Widget _buildAddWidgetDialog() {
    final availableWidgets = ProfileWidgetType.values.where((type) {
      // Check if widget type is already in use
      return !_widgets.any((w) => w.type == type);
    }).toList();

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: widget.theme.backgroundColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: widget.theme.primaryColor.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.add_circle_outline,
                  color: widget.theme.primaryColor,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  'Add Widget',
                  style: TextStyle(
                    color: widget.theme.textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(
                    Icons.close,
                    color: widget.theme.textColor,
                  ),
                ),
              ],
            ),
          ),
          
          // Widget list
          if (availableWidgets.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'All available widgets are already in use',
                style: TextStyle(
                  color: widget.theme.textColor,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: availableWidgets.map((type) {
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      _addWidget(type);
                    },
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: widget.theme.primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: widget.theme.primaryColor.withOpacity(0.3),
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            type.icon,
                            color: widget.theme.primaryColor,
                            size: 24,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            type.displayName,
                            style: TextStyle(
                              color: widget.theme.textColor,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  void _addWidget(ProfileWidgetType type) {
    final newWidget = ProfileWidget(
      id: '${type.name}_${DateTime.now().millisecondsSinceEpoch}',
      type: type,
      config: _getDefaultConfig(type),
      order: _widgets.length,
    );

    setState(() {
      _widgets.add(newWidget);
    });

    widget.onWidgetAdded?.call(newWidget);
  }

  Map<String, dynamic> _getDefaultConfig(ProfileWidgetType type) {
    switch (type) {
      case ProfileWidgetType.customText:
        return {
          'title': 'Custom Text',
          'content': 'Add your custom text here...',
          'textStyle': 'body',
          'alignment': 'left',
        };
      case ProfileWidgetType.socialLinks:
        return {
          'links': [],
        };
      case ProfileWidgetType.quote:
        return {
          'text': 'Your favorite quote here...',
          'author': 'Anonymous',
        };
      case ProfileWidgetType.pinnedPosts:
        return {
          'postIds': [],
          'maxPosts': 3,
        };
      case ProfileWidgetType.musicWidget:
        return {
          'currentTrack': null,
          'isPlaying': false,
        };
      case ProfileWidgetType.photoGrid:
        return {
          'imageUrls': [],
          'maxPhotos': 6,
          'columns': 3,
        };
      case ProfileWidgetType.stats:
        return {
          'showFollowers': true,
          'showPosts': true,
          'showMemberSince': true,
        };
      case ProfileWidgetType.beaconActivity:
        return {
          'maxActivities': 5,
        };
      case ProfileWidgetType.featuredFriends:
        return {
          'friendIds': [],
          'maxFriends': 6,
        };
      default:
        return {};
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Widget grid
        Expanded(
          child: ReorderableListView.builder(
            key: _gridKey,
            onReorder: widget.isEditable ? _onWidgetReordered : null,
            itemCount: _widgets.length,
            itemBuilder: (context, index) {
              final pw = _widgets[index];
              final size = ProfileWidgetConstraints.getWidgetSize(pw.type);

              return ReorderableDelayedDragStartListener(
                key: ValueKey(pw.id),
                index: index,
                child: widget.isEditable
                    ? Draggable<ProfileWidget>(
                        data: pw,
                        feedback: Container(
                          width: size.width,
                          height: size.height,
                          decoration: BoxDecoration(
                            color: widget.theme.primaryColor.withOpacity(0.8),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Icon(
                              pw.type.icon,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                        childWhenDragging: Container(
                          width: size.width,
                          height: size.height,
                          decoration: BoxDecoration(
                            color: widget.theme.primaryColor.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: widget.theme.primaryColor,
                              width: 2,
                            ),
                          ),
                        ),
                        child: ProfileWidgetRenderer(
                          widget: pw,
                          theme: widget.theme,
                          onTap: () => _onWidgetTapped(pw, index),
                        ),
                      )
                    : ProfileWidgetRenderer(
                      widget: pw,
                      theme: widget.theme,
                      onTap: () => _onWidgetTapped(pw, index),
                    ),
              );
            },
          ),
        ),
        
        // Add button
        if (widget.isEditable && _widgets.length < 10)
          Padding(
            padding: const EdgeInsets.all(16),
            child: GestureDetector(
              onTap: _showAddWidgetDialog,
              child: Container(
                width: double.infinity,
                height: 50,
                decoration: BoxDecoration(
                  color: widget.theme.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: widget.theme.primaryColor.withOpacity(0.3),
                    style: BorderStyle.solid,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_circle_outline,
                      color: widget.theme.primaryColor,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Add Widget',
                      style: TextStyle(
                        color: widget.theme.primaryColor,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// Edit dialog widgets
class _CustomTextEditDialog extends StatefulWidget {
  final ProfileWidget widget;
  final Function(ProfileWidget) onSave;

  const _CustomTextEditDialog({
    super.key,
    required this.widget,
    required this.onSave,
  });

  @override
  State<_CustomTextEditDialog> createState() => _CustomTextEditDialogState();
}

class _CustomTextEditDialogState extends State<_CustomTextEditDialog> {
  late TextEditingController _titleController;
  late TextEditingController _contentController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.widget.config['title'] ?? '');
    _contentController = TextEditingController(text: widget.widget.config['content'] ?? '');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Custom Text'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: 'Title',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _contentController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Content',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final updatedWidget = widget.widget.copyWith(
              config: {
                ...widget.widget.config,
                'title': _titleController.text,
                'content': _contentController.text,
              },
            );
            widget.onSave(updatedWidget);
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _SocialLinksEditDialog extends StatefulWidget {
  final ProfileWidget widget;
  final Function(ProfileWidget) onSave;

  const _SocialLinksEditDialog({
    super.key,
    required this.widget,
    required this.onSave,
  });

  @override
  State<_SocialLinksEditDialog> createState() => _SocialLinksEditDialogState();
}

class _SocialLinksEditDialogState extends State<_SocialLinksEditDialog> {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Social Links'),
      content: const Text('Social links editing coming soon...'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _QuoteEditDialog extends StatefulWidget {
  final ProfileWidget widget;
  final Function(ProfileWidget) onSave;

  const _QuoteEditDialog({
    super.key,
    required this.widget,
    required this.onSave,
  });

  @override
  State<_QuoteEditDialog> createState() => _QuoteEditDialogState();
}

class _QuoteEditDialogState extends State<_QuoteEditDialog> {
  late TextEditingController _quoteController;
  late TextEditingController _authorController;

  @override
  void initState() {
    super.initState();
    _quoteController = TextEditingController(text: widget.widget.config['text'] ?? '');
    _authorController = TextEditingController(text: widget.widget.config['author'] ?? '');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Quote'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _quoteController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Quote',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _authorController,
            decoration: const InputDecoration(
              labelText: 'Author',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final updatedWidget = widget.widget.copyWith(
              config: {
                ...widget.widget.config,
                'text': _quoteController.text,
                'author': _authorController.text,
              },
            );
            widget.onSave(updatedWidget);
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
