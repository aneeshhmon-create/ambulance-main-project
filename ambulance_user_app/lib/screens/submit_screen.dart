import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/submit_controller.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/user_storage.dart';

/// Screen for acquiring GPS location and uploading the voice report.
///
/// Route: `/submit`
class SubmitScreen extends StatefulWidget {
  const SubmitScreen({
    super.key,
    this.audioPath,
    this.controller,
    this.locationService,
    this.apiService,
    this.userStorage,
  });

  final String? audioPath;
  final SubmitController? controller;
  final LocationService? locationService;
  final ApiService? apiService;
  final UserStorage? userStorage;

  @override
  State<SubmitScreen> createState() => _SubmitScreenState();
}

class _SubmitScreenState extends State<SubmitScreen> {
  late SubmitController _controller;
  bool _initialized = false;
  Timer? _messageTimer;
  int _messageIndex = 0;

  static const List<String> _uploadMessages = [
    'Uploading your report...',
    'Understanding your message...',
    'Finding nearby hospitals...',
    'Coordinating emergency dispatch...',
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      if (widget.controller != null) {
        _controller = widget.controller!;
      } else {
        final routeArg = ModalRoute.of(context)?.settings.arguments as String?;
        final path = widget.audioPath ?? routeArg ?? '';
        _controller = SubmitController(
          audioPath: path,
          locationService: widget.locationService,
          apiService: widget.apiService,
          userStorage: widget.userStorage,
        );
      }

      _controller.addListener(_onControllerChange);
      _startMessageCycle();
      _controller.submit();
    }
  }

  void _startMessageCycle() {
    _messageTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_controller.state == SubmitState.uploading && mounted) {
        setState(() {
          _messageIndex = (_messageIndex + 1) % _uploadMessages.length;
        });
      }
    });
  }

  void _onControllerChange() {
    if (!mounted) return;
    setState(() {});

    if (_controller.state == SubmitState.success && _controller.incident != null) {
      Navigator.of(context).pushReplacementNamed(
        '/result',
        arguments: _controller.incident,
      );
    }
  }

  @override
  void dispose() {
    _messageTimer?.cancel();
    if (_initialized) {
      _controller.removeListener(_onControllerChange);
      if (widget.controller == null) {
        _controller.dispose();
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Colors.red),
        ),
      );
    }
    final isBusy = _controller.isBusy;

    return PopScope(
      canPop: !isBusy,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Submitting Report'),
          backgroundColor: Colors.red[700],
          foregroundColor: Colors.white,
          automaticallyImplyLeading: !isBusy,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Center(
              child: _buildBody(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_controller.state) {
      case SubmitState.gettingLocation:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.red),
            const SizedBox(height: 24),
            Text(
              'Getting your location...',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Acquiring precise GPS coordinates to dispatch the nearest ambulance.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        );

      case SubmitState.uploading:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.red),
            const SizedBox(height: 24),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: Text(
                _uploadMessages[_messageIndex],
                key: ValueKey<int>(_messageIndex),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.amber[50],
                border: Border.all(color: Colors.amber.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.amber[900]),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'AI transcription & hospital allocation can take up to a minute.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.amber[950],
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );

      case SubmitState.locationServicesOff:
        return _buildErrorState(
          icon: Icons.location_off_rounded,
          title: 'Location Services Disabled',
          description:
              'Please turn on device location (GPS) so emergency services know where to reach you.',
          primaryButtonLabel: 'Open Location Settings',
          onPrimaryPressed: () =>
              _controller.locationService.openLocationSettings(),
          secondaryButtonLabel: 'Try Again',
          onSecondaryPressed: _controller.retry,
        );

      case SubmitState.locationDenied:
        return _buildErrorState(
          icon: Icons.location_disabled_rounded,
          title: 'Location Permission Denied',
          description:
              'Location permission is required to identify the incident site and find nearby hospitals.',
          primaryButtonLabel: 'Grant Permission & Retry',
          onPrimaryPressed: _controller.retry,
        );

      case SubmitState.locationPermanentlyDenied:
        return _buildErrorState(
          icon: Icons.security_rounded,
          title: 'Location Access Blocked',
          description:
              'Location permission is permanently denied. Please open App Settings and allow location permissions for this app.',
          primaryButtonLabel: 'Open App Settings',
          onPrimaryPressed: () => _controller.locationService.openAppSettings(),
          secondaryButtonLabel: 'Try Again',
          onSecondaryPressed: _controller.retry,
        );

      case SubmitState.error:
        return _buildErrorState(
          icon: Icons.error_outline_rounded,
          title: 'Submission Failed',
          description: _controller.errorMessage,
          primaryButtonLabel: 'Retry Submission',
          onPrimaryPressed: _controller.retry,
        );

      case SubmitState.success:
        return const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, color: Colors.green, size: 64),
            SizedBox(height: 16),
            Text(
              'Report Submitted Successfully!',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        );
    }
  }

  Widget _buildErrorState({
    required IconData icon,
    required String title,
    required String description,
    required String primaryButtonLabel,
    required VoidCallback onPrimaryPressed,
    String? secondaryButtonLabel,
    VoidCallback? onSecondaryPressed,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(icon, size: 72, color: Colors.red[700]),
        const SizedBox(height: 16),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          description,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[700],
              ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        ElevatedButton(
          onPressed: onPrimaryPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red[700],
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Text(primaryButtonLabel, style: const TextStyle(fontSize: 16)),
        ),
        if (secondaryButtonLabel != null && onSecondaryPressed != null) ...[
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onSecondaryPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red[700],
              side: BorderSide(color: Colors.red[700]!),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(secondaryButtonLabel, style: const TextStyle(fontSize: 16)),
          ),
        ],
      ],
    );
  }
}
