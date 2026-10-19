// lib/driver_app/widgets/navigation_status_chip.dart
//
// Status chip overlay showing hospital assignment status, route distance and ETA.

import 'package:flutter/material.dart';
import 'package:ambulance_app/driver_app/models/incident_detail.dart';
import 'package:ambulance_app/driver_app/services/routing_service.dart';

class NavigationStatusChip extends StatelessWidget {
  final DriverIncidentHospital? hospital;
  final RouteResult? route;
  final bool isRouting;

  const NavigationStatusChip({
    super.key,
    required this.hospital,
    this.route,
    this.isRouting = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final hasHospital = hospital != null;

    return Material(
      color: Colors.transparent,
      elevation: 4,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: cs.surface.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: hasHospital
                ? const Color(0xFF00796B).withValues(alpha: 0.4)
                : cs.outlineVariant.withValues(alpha: 0.5),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!hasHospital) ...[
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: cs.primary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Looking for a hospital...',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
            ] else ...[
              const Icon(
                Icons.local_hospital_rounded,
                size: 18,
                color: Color(0xFF00796B),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _buildHospitalText(),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isRouting) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: cs.primary,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  String _buildHospitalText() {
    final hospName = hospital!.name;
    if (route != null) {
      final kmStr = route!.distanceKm.toStringAsFixed(1);
      final minStr = route!.durationMinutes.ceil();
      if (route!.isFallback) {
        return 'Hospital: $hospName • direct $kmStr km';
      }
      return 'Hospital: $hospName • $kmStr km ($minStr min)';
    }
    return 'Hospital assigned: $hospName';
  }
}
