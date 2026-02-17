import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/enhanced_beacon.dart';
import '../../theme/app_theme.dart';

class EnhancedBeaconDetailScreen extends StatefulWidget {
  final EnhancedBeacon beacon;

  const EnhancedBeaconDetailScreen({
    super.key,
    required this.beacon,
  });

  @override
  State<EnhancedBeaconDetailScreen> createState() => _EnhancedBeaconDetailScreenState();
}

class _EnhancedBeaconDetailScreenState extends State<EnhancedBeaconDetailScreen> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: CustomScrollView(
        slivers: [
          // App bar with image
          SliverAppBar(
            expandedHeight: 250,
            pinned: true,
            backgroundColor: Colors.black,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // Map background
                  FlutterMap(
                    options: MapOptions(
                      initialCenter: LatLng(widget.beacon.lat, widget.beacon.lng),
                      initialZoom: 15.0,
                      interactiveFlags: InteractiveFlag.none,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.sojorn',
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: LatLng(widget.beacon.lat, widget.beacon.lng),
                            width: 40,
                            height: 40,
                            child: Container(
                              decoration: BoxDecoration(
                                color: widget.beacon.category.color,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 3),
                                boxShadow: [
                                  BoxShadow(
                                    color: widget.beacon.category.color.withOpacity(0.5),
                                    blurRadius: 12,
                                    spreadRadius: 3,
                                  ),
                                ],
                              ),
                              child: Icon(
                                widget.beacon.category.icon,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  
                  // Gradient overlay
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.7),
                          Colors.black,
                        ],
                      ),
                    ),
                  ),
                  
                  // Category badge
                  Positioned(
                    top: 60,
                    left: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: widget.beacon.category.color,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: widget.beacon.category.color.withOpacity(0.3),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            widget.beacon.category.icon,
                            color: Colors.white,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            widget.beacon.category.displayName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Content
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title and status
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.beacon.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: widget.beacon.status.color,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    widget.beacon.status.displayName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  widget.beacon.timeAgo,
                                  style: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      
                      // Share button
                      IconButton(
                        onPressed: _shareBeacon,
                        icon: const Icon(Icons.share, color: Colors.white),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Author info
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundImage: widget.beacon.authorAvatar != null
                            ? NetworkImage(widget.beacon.authorAvatar!)
                            : null,
                        child: widget.beacon.authorAvatar == null
                            ? const Icon(Icons.person, color: Colors.white)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  widget.beacon.authorHandle,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (widget.beacon.isVerified) ...[
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.verified,
                                    color: Colors.blue,
                                    size: 16,
                                  ),
                                ],
                                if (widget.beacon.isOfficialSource) ...[
                                  const SizedBox(width: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.blue,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text(
                                      'Official',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 8,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if (widget.beacon.organizationName != null)
                              Text(
                                widget.beacon.organizationName!,
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Description
                  Text(
                    widget.beacon.description,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      height: 1.4,
                    ),
                  ),
                  
                  // Image if available
                  if (widget.beacon.imageUrl != null) ...[
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        widget.beacon.imageUrl!,
                        height: 200,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            height: 200,
                            color: Colors.grey[800],
                            child: const Center(
                              child: Icon(
                                Icons.image_not_supported,
                                color: Colors.grey,
                                size: 48,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                  
                  const SizedBox(height: 20),
                  
                  // Confidence score
                  _buildConfidenceSection(),
                  
                  const SizedBox(height: 20),
                  
                  // Engagement stats
                  _buildEngagementStats(),
                  
                  const SizedBox(height: 20),
                  
                  // Action items
                  if (widget.beacon.hasActionItems) ...[
                    _buildActionItems(),
                    const SizedBox(height: 20),
                  ],
                  
                  // How to help section
                  _buildHowToHelpSection(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfidenceSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                widget.beacon.isHighConfidence ? Icons.check_circle : Icons.info,
                color: widget.beacon.confidenceColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                widget.beacon.confidenceLabel,
                style: TextStyle(
                  color: widget.beacon.confidenceColor,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: widget.beacon.confidenceScore,
            backgroundColor: Colors.grey[700],
            valueColor: AlwaysStoppedAnimation<Color>(widget.beacon.confidenceColor),
          ),
          const SizedBox(height: 4),
          Text(
            'Based on ${widget.beacon.vouchCount + widget.beacon.reportCount} community responses',
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEngagementStats() {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'Vouches',
            widget.beacon.vouchCount.toString(),
            Icons.thumb_up,
            Colors.green,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            'Reports',
            widget.beacon.reportCount.toString(),
            Icons.flag,
            Colors.red,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            'Status',
            widget.beacon.status.displayName,
            Icons.info,
            widget.beacon.status.color,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionItems() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Action Items',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          ...widget.beacon.actionItems.asMap().entries.map((entry) {
            final index = entry.key;
            final action = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: AppTheme.navyBlue,
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      action,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildHowToHelpSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'How to Help',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          
          // Help actions based on category
          ..._getHelpActions().map((action) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildHelpAction(action),
          )).toList(),
          
          const SizedBox(height: 12),
          
          // Contact info
          if (widget.beacon.isOfficialSource)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Official Contact Information',
                    style: TextStyle(
                      color: Colors.blue,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (widget.beacon.organizationName != null)
                    Text(
                      widget.beacon.organizationName!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    'This beacon is from an official source. Contact them directly for more information.',
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<HelpAction> _getHelpActions() {
    switch (widget.beacon.category) {
      case BeaconCategory.safetyAlert:
        return [
          HelpAction(
            title: 'Report to Authorities',
            description: 'Contact local emergency services if this is an active emergency',
            icon: Icons.emergency,
            color: Colors.red,
            action: () => _callEmergency(),
          ),
          HelpAction(
            title: 'Share Information',
            description: 'Help spread awareness by sharing this alert',
            icon: Icons.share,
            color: Colors.blue,
            action: () => _shareBeacon(),
          ),
          HelpAction(
            title: 'Provide Updates',
            description: 'If you have new information about this situation',
            icon: Icons.update,
            color: Colors.green,
            action: () => _provideUpdate(),
          ),
        ];
      case BeaconCategory.communityNeed:
        return [
          HelpAction(
            title: 'Volunteer',
            description: 'Offer your time and skills to help',
            icon: Icons.volunteer_activism,
            color: Colors.green,
            action: () => _volunteer(),
          ),
          HelpAction(
            title: 'Donate Resources',
            description: 'Contribute needed items or funds',
            icon: Icons.card_giftcard,
            color: Colors.orange,
            action: () => _donate(),
          ),
          HelpAction(
            title: 'Spread the Word',
            description: 'Help find more people who can assist',
            icon: Icons.campaign,
            color: Colors.blue,
            action: () => _shareBeacon(),
          ),
        ];
      case BeaconCategory.lostFound:
        return [
          HelpAction(
            title: 'Report Sighting',
            description: 'If you have seen this person/item',
            icon: Icons.search,
            color: Colors.blue,
            action: () => _reportSighting(),
          ),
          HelpAction(
            title: 'Contact Owner',
            description: 'Reach out with information you may have',
            icon: Icons.phone,
            color: Colors.green,
            action: () => _contactOwner(),
          ),
          HelpAction(
            title: 'Keep Looking',
            description: 'Join the search effort in your area',
            icon: Icons.visibility,
            color: Colors.orange,
            action: () => _joinSearch(),
          ),
        ];
      case BeaconCategory.event:
        return [
          HelpAction(
            title: 'RSVP',
            description: 'Let the organizer know you\'re attending',
            icon: Icons.event_available,
            color: Colors.green,
            action: () => _rsvp(),
          ),
          HelpAction(
            title: 'Volunteer',
            description: 'Help with event setup or coordination',
            icon: Icons.people,
            color: Colors.blue,
            action: () => _volunteer(),
          ),
          HelpAction(
            title: 'Share Event',
            description: 'Help promote this community event',
            icon: Icons.share,
            color: Colors.orange,
            action: () => _shareBeacon(),
          ),
        ];
      case BeaconCategory.mutualAid:
        return [
          HelpAction(
            title: 'Offer Help',
            description: 'Provide direct assistance if you\'re able',
            icon: Icons.handshake,
            color: Colors.green,
            action: () => _offerHelp(),
          ),
          HelpAction(
            title: 'Share Resources',
            description: 'Connect them with relevant services or people',
            icon: Icons.share,
            color: Colors.blue,
            action: () => _shareResources(),
          ),
          HelpAction(
            title: 'Provide Support',
            description: 'Offer emotional support or encouragement',
            icon: Icons.favorite,
            color: Colors.pink,
            action: () => _provideSupport(),
          ),
        ];
    }
  }

  Widget _buildHelpAction(HelpAction action) {
    return GestureDetector(
      onTap: action.action,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey[800],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: action.color,
                shape: BoxShape.circle,
              ),
              child: Icon(
                action.icon,
                color: Colors.white,
                size: 16,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    action.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    action.description,
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios,
              color: Colors.grey[400],
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  void _shareBeacon() {
    Share.share(
      '${widget.beacon.title}\n\n${widget.beacon.description}\n\nView on Sojorn',
      subject: widget.beacon.title,
    );
  }

  void _callEmergency() async {
    const url = 'tel:911';
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  void _provideUpdate() {
    // Navigate to comment/create post for this beacon
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Feature coming soon')),
    );
  }

  void _volunteer() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Volunteer feature coming soon')),
    );
  }

  void _donate() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Donation feature coming soon')),
    );
  }

  void _reportSighting() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sighting report feature coming soon')),
    );
  }

  void _contactOwner() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Contact feature coming soon')),
    );
  }

  void _joinSearch() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Search coordination feature coming soon')),
    );
  }

  void _rsvp() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('RSVP feature coming soon')),
    );
  }

  void _offerHelp() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Direct help feature coming soon')),
    );
  }

  void _shareResources() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Resource sharing feature coming soon')),
    );
  }

  void _provideSupport() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Support feature coming soon')),
    );
  }
}

class HelpAction {
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final VoidCallback action;

  HelpAction({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.action,
  });
}
