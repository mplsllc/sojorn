// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../models/event.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../utils/snackbar_ext.dart';
import '../../widgets/media/signed_media_image.dart';

/// Browse and discover upcoming public events.
class EventDiscoveryScreen extends StatefulWidget {
  const EventDiscoveryScreen({super.key});

  @override
  State<EventDiscoveryScreen> createState() => _EventDiscoveryScreenState();
}

class _EventDiscoveryScreenState extends State<EventDiscoveryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<GroupEvent> _upcomingEvents = [];
  List<GroupEvent> _myEvents = [];
  bool _loadingUpcoming = true;
  bool _loadingMine = true;
  String? _upcomingError;
  String? _mineError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadUpcoming();
    _loadMine();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadUpcoming() async {
    try {
      final rawList = await ApiService.instance.fetchUpcomingEvents(limit: 50);
      if (mounted) {
        setState(() {
          _upcomingEvents = rawList.map((e) => GroupEvent.fromJson(e)).toList();
          _loadingUpcoming = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _upcomingError = e.toString().replaceAll('Exception: ', '');
          _loadingUpcoming = false;
        });
      }
    }
  }

  Future<void> _loadMine() async {
    try {
      final rawList = await ApiService.instance.fetchMyEvents(limit: 50);
      if (mounted) {
        setState(() {
          _myEvents = rawList.map((e) => GroupEvent.fromJson(e)).toList();
          _loadingMine = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _mineError = e.toString().replaceAll('Exception: ', '');
          _loadingMine = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg,
      appBar: AppBar(
        title: const Text('Events'),
        backgroundColor: AppTheme.scaffoldBg,
        surfaceTintColor: Colors.transparent,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.brightNavy,
          labelColor: AppTheme.navyText,
          unselectedLabelColor: AppTheme.navyText.withValues(alpha: 0.4),
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          tabs: const [
            Tab(text: 'Discover'),
            Tab(text: 'My Events'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildDiscoverTab(),
          _buildMyEventsTab(),
        ],
      ),
    );
  }

  Widget _buildDiscoverTab() {
    if (_loadingUpcoming) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_upcomingError != null) {
      return _buildError(_upcomingError!, _loadUpcoming);
    }
    if (_upcomingEvents.isEmpty) {
      return _buildEmpty('No upcoming events', 'Public events from groups will appear here.');
    }

    return RefreshIndicator(
      onRefresh: _loadUpcoming,
      child: ListView.builder(
        padding: const EdgeInsets.all(SojornSpacing.md),
        itemCount: _upcomingEvents.length,
        itemBuilder: (ctx, i) => _EventCard(
          event: _upcomingEvents[i],
          onTap: () => _openEvent(_upcomingEvents[i]),
          onRsvp: () => _rsvp(_upcomingEvents[i]),
        ),
      ),
    );
  }

  Widget _buildMyEventsTab() {
    if (_loadingMine) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_mineError != null) {
      return _buildError(_mineError!, _loadMine);
    }
    if (_myEvents.isEmpty) {
      return _buildEmpty('No events yet', 'Events from groups you\'ve joined will appear here.');
    }

    return RefreshIndicator(
      onRefresh: _loadMine,
      child: ListView.builder(
        padding: const EdgeInsets.all(SojornSpacing.md),
        itemCount: _myEvents.length,
        itemBuilder: (ctx, i) => _EventCard(
          event: _myEvents[i],
          onTap: () => _openEvent(_myEvents[i]),
          onRsvp: () => _rsvp(_myEvents[i]),
        ),
      ),
    );
  }

  Widget _buildError(String message, VoidCallback retry) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 48, color: AppTheme.navyText.withValues(alpha: 0.3)),
          const SizedBox(height: 12),
          Text(message, style: TextStyle(color: AppTheme.navyText.withValues(alpha: 0.6), fontSize: 14)),
          const SizedBox(height: 12),
          TextButton(onPressed: retry, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildEmpty(String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event, size: 48, color: AppTheme.navyText.withValues(alpha: 0.2)),
          const SizedBox(height: 12),
          Text(title, style: TextStyle(color: AppTheme.navyText, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(color: AppTheme.navyText.withValues(alpha: 0.5), fontSize: 13)),
        ],
      ),
    );
  }

  void _openEvent(GroupEvent event) {
    context.push('/events/${event.groupId}/${event.id}', extra: event);
  }

  Future<void> _rsvp(GroupEvent event) async {
    final newStatus = event.myRsvp == RSVPStatus.going ? null : RSVPStatus.going;
    try {
      if (newStatus == null) {
        await ApiService.instance.removeRsvp(event.groupId, event.id);
      } else {
        await ApiService.instance.rsvpEvent(event.groupId, event.id, newStatus.value);
      }
      // Refresh both tabs
      _loadUpcoming();
      _loadMine();
    } catch (e) {
      if (mounted) context.showError('Could not update RSVP');
    }
  }
}

class _EventCard extends StatelessWidget {
  final GroupEvent event;
  final VoidCallback onTap;
  final VoidCallback onRsvp;

  const _EventCard({required this.event, required this.onTap, required this.onRsvp});

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('EEE, MMM d');
    final timeFormat = DateFormat('h:mm a');
    final isToday = DateUtils.isSameDay(event.startsAt, DateTime.now());
    final isTomorrow = DateUtils.isSameDay(event.startsAt, DateTime.now().add(const Duration(days: 1)));

    String dateLabel;
    if (isToday) {
      dateLabel = 'Today';
    } else if (isTomorrow) {
      dateLabel = 'Tomorrow';
    } else {
      dateLabel = dateFormat.format(event.startsAt);
    }

    return Card(
      margin: const EdgeInsets.only(bottom: SojornSpacing.sm),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SojornRadii.card)),
      color: AppTheme.cardSurface,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Cover image or gradient header
            if (event.coverImageUrl != null && event.coverImageUrl!.isNotEmpty)
              SizedBox(
                height: 140,
                child: SignedMediaImage(
                  url: event.coverImageUrl!,
                  fit: BoxFit.cover,
                  width: double.infinity,
                ),
              )
            else
              Container(
                height: 80,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppTheme.brightNavy, AppTheme.royalPurple.withValues(alpha: 0.7)],
                  ),
                ),
                child: const Center(
                  child: Icon(Icons.event, size: 32, color: Colors.white54),
                ),
              ),
            // Content
            Padding(
              padding: const EdgeInsets.all(SojornSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Date + time chip
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.brightNavy.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(SojornRadii.sm),
                        ),
                        child: Text(
                          '$dateLabel at ${timeFormat.format(event.startsAt)}',
                          style: TextStyle(
                            color: AppTheme.brightNavy,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (event.attendeeCount > 0)
                        Text(
                          '${event.attendeeCount} going',
                          style: TextStyle(color: AppTheme.navyText.withValues(alpha: 0.4), fontSize: 11),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Title
                  Text(
                    event.title,
                    style: TextStyle(color: AppTheme.navyText, fontSize: 16, fontWeight: FontWeight.w700),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // Group name
                  if (event.groupName != null && event.groupName!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'by ${event.groupName}',
                      style: TextStyle(color: AppTheme.navyText.withValues(alpha: 0.5), fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  // Location
                  if (event.locationName != null && event.locationName!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.location_on_outlined, size: 14, color: AppTheme.navyText.withValues(alpha: 0.4)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            event.locationName!,
                            style: TextStyle(color: AppTheme.navyText.withValues(alpha: 0.5), fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),
                  // RSVP button
                  Row(
                    children: [
                      Expanded(
                        child: _RsvpButton(
                          status: event.myRsvp,
                          onTap: onRsvp,
                        ),
                      ),
                      if (event.maxAttendees != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          '${event.attendeeCount}/${event.maxAttendees}',
                          style: TextStyle(color: AppTheme.navyText.withValues(alpha: 0.4), fontSize: 11),
                        ),
                      ],
                    ],
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

class _RsvpButton extends StatelessWidget {
  final RSVPStatus? status;
  final VoidCallback onTap;

  const _RsvpButton({this.status, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isGoing = status == RSVPStatus.going;
    final isInterested = status == RSVPStatus.interested;
    final hasRsvp = isGoing || isInterested;

    return SizedBox(
      height: 34,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(
          hasRsvp ? Icons.check_circle : Icons.add_circle_outline,
          size: 16,
        ),
        label: Text(
          isGoing ? 'Going' : isInterested ? 'Interested' : 'RSVP',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: hasRsvp ? Colors.white : AppTheme.brightNavy,
          backgroundColor: hasRsvp ? AppTheme.brightNavy : Colors.transparent,
          side: BorderSide(color: AppTheme.brightNavy.withValues(alpha: hasRsvp ? 0 : 0.3)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SojornRadii.md)),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
      ),
    );
  }
}
