// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../models/event.dart';
import '../../models/group.dart';
import '../../services/api_service.dart';
import '../../theme/tokens.dart';
import '../../utils/snackbar_ext.dart';

/// Full event detail screen. Accepts either:
///   - [event] directly (when navigating with `extra:`)
///   - [groupId] + [eventId] for deep-link fetching
class EventDetailScreen extends StatefulWidget {
  final String groupId;
  final String eventId;
  final GroupEvent? initialEvent;  // pre-populated when navigating from a list
  final GroupRole? userRole;       // caller passes this when it knows the role

  const EventDetailScreen({
    super.key,
    required this.groupId,
    required this.eventId,
    this.initialEvent,
    this.userRole,
  });

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  GroupEvent? _event;
  bool _loading = true;
  bool _rsvpLoading = false;

  bool get _isAdmin =>
      widget.userRole == GroupRole.owner || widget.userRole == GroupRole.admin;

  bool get _isFuture => _event != null && _event!.startsAt.isAfter(DateTime.now());

  @override
  void initState() {
    super.initState();
    if (widget.initialEvent != null) {
      _event = widget.initialEvent;
      _loading = false;
    } else {
      _fetchEvent();
    }
  }

  Future<void> _fetchEvent() async {
    try {
      final data = await ApiService.instance.getGroupEvent(widget.groupId, widget.eventId);
      if (mounted) {
        setState(() {
          _event = GroupEvent.fromJson(data);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        context.showError('Could not load event');
      }
    }
  }

  Future<void> _rsvp(RSVPStatus status) async {
    if (_event == null) return;
    setState(() => _rsvpLoading = true);
    try {
      if (_event!.myRsvp == status) {
        // Toggle off
        await ApiService.instance.removeRsvp(widget.groupId, _event!.id);
        setState(() {
          _event = _event!.copyWith(
            myRsvp: null,
            attendeeCount: status == RSVPStatus.going
                ? (_event!.attendeeCount - 1).clamp(0, 9999)
                : _event!.attendeeCount,
          );
        });
      } else {
        final wasGoing = _event!.myRsvp == RSVPStatus.going;
        await ApiService.instance.rsvpEvent(widget.groupId, _event!.id, status.value);
        int newCount = _event!.attendeeCount;
        if (status == RSVPStatus.going) newCount++;
        if (wasGoing) newCount--;
        setState(() {
          _event = _event!.copyWith(myRsvp: status, attendeeCount: newCount.clamp(0, 9999));
        });
      }
    } catch (e) {
      if (mounted) context.showError('Failed to update RSVP');
    }
    if (mounted) setState(() => _rsvpLoading = false);
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Event'),
        content: const Text('This will permanently delete the event and all RSVPs. Continue?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ApiService.instance.deleteGroupEvent(widget.groupId, widget.eventId);
      if (mounted) {
        context.showSuccess('Event deleted');
        context.pop();
      }
    } catch (e) {
      if (mounted) context.showError('Failed to delete event');
    }
  }

  void _showEditSheet() {
    if (_event == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(SojornRadii.modal)),
      ),
      builder: (_) => _EditEventSheet(
        groupId: widget.groupId,
        event: _event!,
        onUpdated: (updated) => setState(() => _event = updated),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_event == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Event not found')),
      );
    }

    final event = _event!;
    final isPast = !_isFuture;
    final dateFmt = DateFormat('EEEE, MMMM d, y');
    final timeFmt = DateFormat('h:mm a');

    return Scaffold(
      appBar: AppBar(
        title: Text(event.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (_isAdmin)
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'edit') _showEditSheet();
                if (v == 'delete') _delete();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('Edit event'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, size: 18, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Delete event', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(SojornSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Date / Time block ──────────────────────────────────────────
            _DateBlock(event: event, isPast: isPast),
            const SizedBox(height: SojornSpacing.lg),

            // ── Title ──────────────────────────────────────────────────────
            Text(
              event.title,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: isPast ? SojornColors.textDisabled : null,
              ),
            ),
            const SizedBox(height: SojornSpacing.sm),

            // ── Public badge ───────────────────────────────────────────────
            if (event.isPublic)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                margin: const EdgeInsets.only(bottom: SojornSpacing.sm),
                decoration: BoxDecoration(
                  color: SojornColors.basicRoyalPurple.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(SojornRadii.full),
                ),
                child: Text(
                  'Public Event',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: SojornColors.basicRoyalPurple,
                    letterSpacing: 0.3,
                  ),
                ),
              ),

            // ── Description ────────────────────────────────────────────────
            if (event.description.isNotEmpty) ...[
              Text(event.description, style: theme.textTheme.bodyMedium),
              const SizedBox(height: SojornSpacing.md),
            ],

            const Divider(),
            const SizedBox(height: SojornSpacing.md),

            // ── Location ───────────────────────────────────────────────────
            if (event.locationName != null) ...[
              _InfoRow(
                icon: Icons.location_on_outlined,
                text: event.locationName!,
              ),
              const SizedBox(height: SojornSpacing.sm),
            ],

            // ── Time info ─────────────────────────────────────────────────
            _InfoRow(
              icon: Icons.calendar_today,
              text: dateFmt.format(event.startsAt.toLocal()),
            ),
            const SizedBox(height: 4),
            _InfoRow(
              icon: Icons.access_time,
              text: event.endsAt != null
                  ? '${timeFmt.format(event.startsAt.toLocal())} – ${timeFmt.format(event.endsAt!.toLocal())}'
                  : 'Starts at ${timeFmt.format(event.startsAt.toLocal())}',
            ),

            // ── Group ──────────────────────────────────────────────────────
            if (event.groupName != null) ...[
              const SizedBox(height: SojornSpacing.sm),
              _InfoRow(
                icon: Icons.group_outlined,
                text: event.groupName!,
              ),
            ],

            const SizedBox(height: SojornSpacing.md),
            const Divider(),
            const SizedBox(height: SojornSpacing.md),

            // ── Attendees ──────────────────────────────────────────────────
            _AttendeeSection(event: event),

            const SizedBox(height: SojornSpacing.lg),

            // ── RSVP buttons ───────────────────────────────────────────────
            if (!isPast) ...[
              Text('Your RSVP', style: theme.textTheme.labelLarge),
              const SizedBox(height: SojornSpacing.sm),
              _RsvpButtons(
                current: event.myRsvp,
                loading: _rsvpLoading,
                onRsvp: _rsvp,
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(SojornSpacing.sm),
                decoration: BoxDecoration(
                  color: SojornColors.textDisabled.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(SojornRadii.md),
                ),
                child: Row(
                  children: [
                    Icon(Icons.history, size: 16, color: SojornColors.textDisabled),
                    const SizedBox(width: 8),
                    Text('This event has passed',
                        style: TextStyle(color: SojornColors.textDisabled, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _DateBlock extends StatelessWidget {
  final GroupEvent event;
  final bool isPast;

  const _DateBlock({required this.event, required this.isPast});

  @override
  Widget build(BuildContext context) {
    final local = event.startsAt.toLocal();
    final monthFmt = DateFormat('MMM');
    final color = isPast ? SojornColors.textDisabled : SojornColors.basicRoyalPurple;

    return Row(
      children: [
        Container(
          width: 52,
          height: 58,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(SojornRadii.md),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                monthFmt.format(local).toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: color,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                '${local.day}',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: color,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: SojornSpacing.md),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DateFormat('EEEE').format(local),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color),
            ),
            Text(
              DateFormat('h:mm a').format(local),
              style: TextStyle(fontSize: 12, color: color.withValues(alpha: 0.7)),
            ),
            if (event.endsAt != null)
              Text(
                'until ${DateFormat('h:mm a').format(event.endsAt!.toLocal())}',
                style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.5)),
              ),
          ],
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: SojornColors.textDisabled),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    );
  }
}

class _AttendeeSection extends StatelessWidget {
  final GroupEvent event;

  const _AttendeeSection({required this.event});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasCapacity = event.maxAttendees != null && event.maxAttendees! > 0;
    final isFull = hasCapacity && event.attendeeCount >= event.maxAttendees!;

    return Row(
      children: [
        Icon(Icons.people_outline, size: 18, color: SojornColors.textDisabled),
        const SizedBox(width: 8),
        if (hasCapacity) ...[
          Text(
            '${event.attendeeCount} / ${event.maxAttendees} going',
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          if (isFull)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(SojornRadii.full),
              ),
              child: Text('Full', style: TextStyle(fontSize: 11, color: Colors.orange.shade700)),
            ),
        ] else
          Text(
            '${event.attendeeCount} going',
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
      ],
    );
  }
}

class _RsvpButtons extends StatelessWidget {
  final RSVPStatus? current;
  final bool loading;
  final ValueChanged<RSVPStatus> onRsvp;

  const _RsvpButtons({
    required this.current,
    required this.loading,
    required this.onRsvp,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Btn(
          label: 'Going',
          icon: Icons.check_circle_outline,
          activeIcon: Icons.check_circle,
          isSelected: current == RSVPStatus.going,
          loading: loading,
          onTap: () => onRsvp(RSVPStatus.going),
          color: const Color(0xFF22C55E),
        ),
        const SizedBox(width: SojornSpacing.sm),
        _Btn(
          label: 'Interested',
          icon: Icons.star_border,
          activeIcon: Icons.star,
          isSelected: current == RSVPStatus.interested,
          loading: loading,
          onTap: () => onRsvp(RSVPStatus.interested),
          color: const Color(0xFFFBBF24),
        ),
        const SizedBox(width: SojornSpacing.sm),
        _Btn(
          label: "Can't go",
          icon: Icons.cancel_outlined,
          activeIcon: Icons.cancel,
          isSelected: current == RSVPStatus.notGoing,
          loading: loading,
          onTap: () => onRsvp(RSVPStatus.notGoing),
          color: const Color(0xFF9E9E9E),
        ),
      ],
    );
  }
}

class _Btn extends StatelessWidget {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final bool isSelected;
  final bool loading;
  final VoidCallback onTap;
  final Color color;

  const _Btn({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.isSelected,
    required this.loading,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: loading ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? color : color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(SojornRadii.md),
            border: Border.all(color: isSelected ? color : color.withValues(alpha: 0.25)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isSelected ? activeIcon : icon,
                size: 20,
                color: isSelected ? Colors.white : color,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Edit Event Sheet ─────────────────────────────────────────────────────────

class _EditEventSheet extends StatefulWidget {
  final String groupId;
  final GroupEvent event;
  final ValueChanged<GroupEvent> onUpdated;

  const _EditEventSheet({
    required this.groupId,
    required this.event,
    required this.onUpdated,
  });

  @override
  State<_EditEventSheet> createState() => _EditEventSheetState();
}

class _EditEventSheetState extends State<_EditEventSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _locationCtrl;
  late DateTime _startsAt;
  DateTime? _endsAt;
  late bool _isPublic;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final e = widget.event;
    _titleCtrl = TextEditingController(text: e.title);
    _descCtrl = TextEditingController(text: e.description);
    _locationCtrl = TextEditingController(text: e.locationName ?? '');
    _startsAt = e.startsAt.toLocal();
    _endsAt = e.endsAt?.toLocal();
    _isPublic = e.isPublic;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool isEnd) async {
    final now = DateTime.now();
    final initial = isEnd ? (_endsAt ?? _startsAt) : _startsAt;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 730)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
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
      final data = await ApiService.instance.updateGroupEvent(widget.groupId, widget.event.id, {
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'location_name': _locationCtrl.text.trim().isEmpty ? null : _locationCtrl.text.trim(),
        'starts_at': _startsAt.toUtc().toIso8601String(),
        if (_endsAt != null) 'ends_at': _endsAt!.toUtc().toIso8601String(),
        'is_public': _isPublic,
      });
      if (mounted) {
        final updated = GroupEvent.fromJson(data);
        widget.onUpdated(updated);
        Navigator.pop(context);
        context.showSuccess('Event updated');
      }
    } catch (e) {
      if (mounted) context.showError('Failed to update event');
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
            Text('Edit Event', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: SojornSpacing.md),

            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(labelText: 'Event Title'),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: SojornSpacing.sm),

            TextField(
              controller: _descCtrl,
              decoration: const InputDecoration(labelText: 'Description'),
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: SojornSpacing.sm),

            TextField(
              controller: _locationCtrl,
              decoration: const InputDecoration(
                labelText: 'Location (optional)',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
            ),
            const SizedBox(height: SojornSpacing.md),

            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today),
              title: const Text('Starts'),
              subtitle: Text(dateFmt.format(_startsAt)),
              onTap: () => _pickDate(false),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today_outlined),
              title: const Text('Ends (optional)'),
              subtitle: Text(_endsAt != null ? dateFmt.format(_endsAt!) : 'Tap to set'),
              onTap: () => _pickDate(true),
            ),

            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Public event'),
              subtitle: const Text('Visible outside this group'),
              value: _isPublic,
              onChanged: (v) => setState(() => _isPublic = v),
            ),

            const SizedBox(height: SojornSpacing.md),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }
}
