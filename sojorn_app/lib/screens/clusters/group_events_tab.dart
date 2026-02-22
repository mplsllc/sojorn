// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/event.dart';
import '../../models/group.dart';
import '../../services/api_service.dart';
import '../../theme/tokens.dart';
import '../../utils/snackbar_ext.dart';

class GroupEventsTab extends StatefulWidget {
  final String groupId;
  final GroupRole? userRole;

  const GroupEventsTab({
    super.key,
    required this.groupId,
    this.userRole,
  });

  @override
  State<GroupEventsTab> createState() => _GroupEventsTabState();
}

class _GroupEventsTabState extends State<GroupEventsTab> {
  List<GroupEvent> _events = [];
  bool _loading = true;

  bool get _canCreate =>
      widget.userRole == GroupRole.owner || widget.userRole == GroupRole.admin;

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    setState(() => _loading = true);
    try {
      final raw = await ApiService.instance.fetchGroupEvents(widget.groupId);
      _events = raw.map((e) => GroupEvent.fromJson(e)).toList();
    } catch (e) {
      debugPrint('[GroupEvents] Error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _rsvp(GroupEvent event, RSVPStatus status) async {
    try {
      await ApiService.instance.rsvpEvent(widget.groupId, event.id, status.value);
      _loadEvents();
    } catch (e) {
      if (mounted) context.showError('Failed to RSVP');
    }
  }

  void _showCreateEvent() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(SojornRadii.modal)),
      ),
      builder: (_) => _CreateEventSheet(
        groupId: widget.groupId,
        onCreated: _loadEvents,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _loadEvents,
      child: _events.isEmpty
          ? ListView(
              children: [
                const SizedBox(height: 120),
                Center(
                  child: Column(
                    children: [
                      Icon(Icons.event_outlined, size: 48, color: SojornColors.textDisabled),
                      const SizedBox(height: 12),
                      Text('No events yet',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: SojornColors.textDisabled,
                              )),
                      if (_canCreate) ...[
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _showCreateEvent,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Create Event'),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.all(SojornSpacing.md),
              itemCount: _events.length + (_canCreate ? 1 : 0),
              itemBuilder: (context, index) {
                if (_canCreate && index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: SojornSpacing.md),
                    child: FilledButton.icon(
                      onPressed: _showCreateEvent,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Create Event'),
                    ),
                  );
                }
                final event = _events[_canCreate ? index - 1 : index];
                return _EventCard(
                  event: event,
                  onRsvp: (status) => _rsvp(event, status),
                );
              },
            ),
    );
  }
}

class _EventCard extends StatelessWidget {
  final GroupEvent event;
  final ValueChanged<RSVPStatus> onRsvp;

  const _EventCard({required this.event, required this.onRsvp});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFormat = DateFormat('EEE, MMM d');
    final timeFormat = DateFormat('h:mm a');
    final isPast = event.startsAt.isBefore(DateTime.now());

    return Card(
      margin: const EdgeInsets.only(bottom: SojornSpacing.sm),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SojornRadii.card),
      ),
      child: Padding(
        padding: const EdgeInsets.all(SojornSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date + public badge
            Row(
              children: [
                Icon(Icons.calendar_today, size: 14, color: SojornColors.basicRoyalPurple),
                const SizedBox(width: 6),
                Text(
                  '${dateFormat.format(event.startsAt.toLocal())} at ${timeFormat.format(event.startsAt.toLocal())}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: SojornColors.basicRoyalPurple,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (event.isPublic)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: SojornColors.basicRoyalPurple.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(SojornRadii.sm),
                    ),
                    child: Text('Public',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: SojornColors.basicRoyalPurple,
                        )),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // Title
            Text(
              event.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: isPast ? SojornColors.textDisabled : null,
              ),
            ),

            if (event.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(event.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall),
            ],

            if (event.locationName != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.location_on_outlined, size: 14, color: SojornColors.textDisabled),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(event.locationName!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: SojornColors.textDisabled,
                        )),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 12),

            // Bottom row: attendee count + RSVP chips
            Row(
              children: [
                Icon(Icons.people_outline, size: 16, color: SojornColors.textDisabled),
                const SizedBox(width: 4),
                Text('${event.attendeeCount} going',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: SojornColors.textDisabled,
                    )),
                const Spacer(),
                if (!isPast) ...[
                  _RsvpChip(
                    label: 'Going',
                    isSelected: event.myRsvp == RSVPStatus.going,
                    onTap: () => onRsvp(RSVPStatus.going),
                  ),
                  const SizedBox(width: 6),
                  _RsvpChip(
                    label: 'Interested',
                    isSelected: event.myRsvp == RSVPStatus.interested,
                    onTap: () => onRsvp(RSVPStatus.interested),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RsvpChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _RsvpChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(SojornRadii.full),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? SojornColors.basicRoyalPurple
              : SojornColors.basicRoyalPurple.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(SojornRadii.full),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : SojornColors.basicRoyalPurple,
          ),
        ),
      ),
    );
  }
}

class _CreateEventSheet extends StatefulWidget {
  final String groupId;
  final VoidCallback onCreated;

  const _CreateEventSheet({required this.groupId, required this.onCreated});

  @override
  State<_CreateEventSheet> createState() => _CreateEventSheetState();
}

class _CreateEventSheetState extends State<_CreateEventSheet> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  DateTime _startsAt = DateTime.now().add(const Duration(days: 1));
  DateTime? _endsAt;
  bool _isPublic = false;
  bool _submitting = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool isEnd) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: isEnd ? (_endsAt ?? _startsAt) : _startsAt,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(isEnd ? (_endsAt ?? _startsAt) : _startsAt),
    );
    if (time == null || !mounted) return;

    final combined = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (isEnd) {
        _endsAt = combined;
      } else {
        _startsAt = combined;
      }
    });
  }

  Future<void> _submit() async {
    if (_titleCtrl.text.trim().isEmpty) return;
    setState(() => _submitting = true);
    try {
      await ApiService.instance.createGroupEvent(widget.groupId, {
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'location_name': _locationCtrl.text.trim().isEmpty ? null : _locationCtrl.text.trim(),
        'starts_at': _startsAt.toUtc().toIso8601String(),
        if (_endsAt != null) 'ends_at': _endsAt!.toUtc().toIso8601String(),
        'is_public': _isPublic,
      });
      if (mounted) {
        Navigator.pop(context);
        context.showSuccess('Event created');
        widget.onCreated();
      }
    } catch (e) {
      if (mounted) context.showError('Failed to create event');
    }
    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFmt = DateFormat('EEE, MMM d · h:mm a');

    return Padding(
      padding: EdgeInsets.only(
        left: SojornSpacing.lg,
        right: SojornSpacing.lg,
        top: SojornSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + SojornSpacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Create Event', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: SojornSpacing.md),

            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Event Title',
                hintText: 'What\'s happening?',
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: SojornSpacing.sm),

            TextField(
              controller: _descCtrl,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'Tell people about this event',
              ),
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: SojornSpacing.sm),

            TextField(
              controller: _locationCtrl,
              decoration: const InputDecoration(
                labelText: 'Location (optional)',
                hintText: 'Where is it?',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
            ),
            const SizedBox(height: SojornSpacing.md),

            // Start date
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today),
              title: const Text('Starts'),
              subtitle: Text(dateFmt.format(_startsAt)),
              onTap: () => _pickDate(false),
            ),

            // End date
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today_outlined),
              title: const Text('Ends (optional)'),
              subtitle: Text(_endsAt != null ? dateFmt.format(_endsAt!) : 'Tap to set'),
              onTap: () => _pickDate(true),
            ),

            // Public toggle
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Public event'),
              subtitle: const Text('Visible to users outside this group'),
              value: _isPublic,
              onChanged: (v) => setState(() => _isPublic = v),
            ),

            const SizedBox(height: SojornSpacing.md),

            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Create Event'),
            ),
          ],
        ),
      ),
    );
  }
}
