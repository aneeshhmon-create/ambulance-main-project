import 'package:flutter/material.dart';

import '../config/routes.dart';

/// Full-screen friendly error fallback page shown instead of the red crash screen.
class GlobalErrorScreen extends StatelessWidget {
  const GlobalErrorScreen({
    super.key,
    this.errorMessage,
    this.errorDetails,
    this.onBackHome,
  });

  final String? errorMessage;
  final FlutterErrorDetails? errorDetails;
  final VoidCallback? onBackHome;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.healing_rounded,
                      size: 72,
                      color: Colors.red[700],
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Something went wrong',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'An unexpected application issue occurred. '
                      'Emergency dispatch services remain active.',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[700],
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton.icon(
                      onPressed: () {
                        if (onBackHome != null) {
                          onBackHome!();
                          return;
                        }
                        Navigator.of(context).pushNamedAndRemoveUntil(
                          AppRoutes.root,
                          (route) => false,
                        );
                      },
                      icon: const Icon(Icons.home_rounded),
                      label: const Text(
                        'Back to Home',
                        style: TextStyle(fontSize: 16),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red[700],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
