// lib/driver_app/widgets/home_footer.dart
//
// HomeFooter — reusable rounded footer widget for the driver Home screen.
// Reserved for future features (live ETA, next assignment info, etc.).
// Currently displays a status line reflecting the ambulance's online state.

import 'package:flutter/material.dart';

class HomeFooter extends StatelessWidget {
  /// Whether the driver is currently online (affects the status message).
  final bool isOnline;

  /// Optional custom message. If null, a default message is shown.
  final String? message;

  const HomeFooter({
    super.key,
    required this.isOnline,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final displayMessage = message ??
        (isOnline
            ? 'Sharing location — waiting for incoming requests…'
            : 'Go online to receive emergency requests');

    final iconColor = isOnline ? const Color(0xFF388E3C) : cs.outline;
    final icon = isOnline
        ? Icons.radio_button_checked_rounded
        : Icons.radio_button_unchecked_rounded;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isOnline
              ? const Color(0xFF388E3C).withValues(alpha: 0.35)
              : cs.outlineVariant,
          width: 1.2,
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              displayMessage,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isOnline ? cs.onSurface : cs.outline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
