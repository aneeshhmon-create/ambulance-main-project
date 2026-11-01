// lib/driver_app/widgets/ambulance_type_selector.dart
//
// ALS / BLS / Both picker used when registering an ambulance.

import 'package:flutter/material.dart';

/// Values sent to the server (`vehicle_type`).
class AmbulanceTypes {
  AmbulanceTypes._();

  static const als = 'ALS';
  static const bls = 'BLS';
  static const both = 'ALS+BLS';

  /// Compact form for tight spaces, e.g. the home header.
  static String shortLabel(String? value) => value == both ? 'ALS + BLS' : (value ?? '');

  /// Human-readable form of a stored `vehicle_type`.
  static String label(String? value) {
    switch (value) {
      case als:
        return 'ALS (Advanced Life Support)';
      case bls:
        return 'BLS (Basic Life Support)';
      case both:
        return 'ALS + BLS';
      case null:
      case '':
        return 'Standard';
      default:
        return value;
    }
  }
}

class AmbulanceTypeSelector extends StatelessWidget {
  const AmbulanceTypeSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.errorText,
  });

  final String? value;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Ambulance type', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          emptySelectionAllowed: true,
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: AmbulanceTypes.als, label: Text('ALS')),
            ButtonSegment(value: AmbulanceTypes.bls, label: Text('BLS')),
            ButtonSegment(value: AmbulanceTypes.both, label: Text('Both')),
          ],
          selected: value == null ? <String>{} : {value!},
          onSelectionChanged: enabled
              ? (selection) {
                  if (selection.isNotEmpty) onChanged(selection.first);
                }
              : null,
        ),
        const SizedBox(height: 6),
        Text(
          errorText ??
              'ALS = Advanced Life Support, BLS = Basic Life Support. '
                  'Choose Both if the vehicle is equipped for either.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: errorText != null
                ? theme.colorScheme.error
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
