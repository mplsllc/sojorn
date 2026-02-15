import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../models/local_intel.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/tokens.dart';

/// Bottom sheet displaying nearby public resources
class ResourcesSheet extends StatelessWidget {
  final List<PublicResource> resources;
  final LatLng? userLocation;

  const ResourcesSheet({
    super.key,
    required this.resources,
    this.userLocation,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.textDisabled.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF009688).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.place_outlined,
                    color: const Color(0xFF009688),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Public Resources',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.navyBlue,
                                ),
                      ),
                      Text(
                        '${resources.length} locations within 2km',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.textDisabled,
                            ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Resource list
          Expanded(
            child: resources.isEmpty
                ? _buildEmptyState(context)
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: resources.length,
                    separatorBuilder: (_, __) => const Divider(
                      height: 1,
                      indent: 72,
                    ),
                    itemBuilder: (context, index) =>
                        _buildResourceTile(context, resources[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.location_off_outlined,
              size: 48,
              color: AppTheme.textDisabled,
            ),
            const SizedBox(height: 16),
            Text(
              'No resources found nearby',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppTheme.textDisabled,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try expanding your search area or moving to a different location.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textDisabled,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResourceTile(BuildContext context, PublicResource resource) {
    final color = _getTypeColor(resource.type);
    final icon = _getTypeIcon(resource.type);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 24),
      ),
      title: Text(
        resource.name,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: AppTheme.navyBlue,
            ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  resource.type.displayName,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w600,
                        fontSize: 10,
                      ),
                ),
              ),
              if (resource.distanceMeters != null) ...[
                const SizedBox(width: 8),
                Icon(
                  Icons.directions_walk,
                  size: 12,
                  color: AppTheme.textDisabled,
                ),
                const SizedBox(width: 2),
                Text(
                  resource.formattedDistance,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppTheme.textDisabled,
                      ),
                ),
              ],
            ],
          ),
          if (resource.address != null) ...[
            const SizedBox(height: 4),
            Text(
              resource.address!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textDisabled,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (resource.phone != null)
            IconButton(
              onPressed: () => _launchPhone(resource.phone!),
              icon: const Icon(Icons.phone_outlined),
              iconSize: 20,
              color: AppTheme.brightNavy,
              tooltip: 'Call',
            ),
          IconButton(
            onPressed: () => _launchDirections(resource),
            icon: const Icon(Icons.directions_outlined),
            iconSize: 20,
            color: AppTheme.egyptianBlue,
            tooltip: 'Directions',
          ),
        ],
      ),
    );
  }

  Color _getTypeColor(ResourceType type) {
    switch (type) {
      case ResourceType.library:
        return const Color(0xFF2196F3);
      case ResourceType.park:
        return const Color(0xFF4CAF50);
      case ResourceType.hospital:
        return const Color(0xFFF44336);
      case ResourceType.police:
        return const Color(0xFF3F51B5);
      case ResourceType.pharmacy:
        return const Color(0xFF009688);
      case ResourceType.fireStation:
        return const Color(0xFFFF9800);
      case ResourceType.other:
        return AppTheme.textDisabled;
    }
  }

  IconData _getTypeIcon(ResourceType type) {
    switch (type) {
      case ResourceType.library:
        return Icons.local_library;
      case ResourceType.park:
        return Icons.park;
      case ResourceType.hospital:
        return Icons.local_hospital;
      case ResourceType.police:
        return Icons.local_police;
      case ResourceType.pharmacy:
        return Icons.local_pharmacy;
      case ResourceType.fireStation:
        return Icons.local_fire_department;
      case ResourceType.other:
        return Icons.place;
    }
  }

  Future<void> _launchPhone(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _launchDirections(PublicResource resource) async {
    // Open in maps app with directions
    final uri = Uri.parse(
      'https://www.openstreetmap.org/directions?from=${userLocation?.latitude ?? ''},${userLocation?.longitude ?? ''}&to=${resource.latitude},${resource.longitude}',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
