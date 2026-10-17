import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:ambulance_app/user_app/models/user.dart';
import 'package:ambulance_app/user_app/screens/register_screen.dart';
import 'package:ambulance_app/user_app/services/api_service.dart' show ApiException;
import 'package:ambulance_app/user_app/services/auth_service.dart';

/// Signed-out landing screen: "Sign in with Google".
///
/// A first-time user is sent on to [RegisterScreen] to give their name and
/// phone number before reaching the home screen.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.authService});

  final UserAuthService? authService;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final UserAuthService _auth;
  final _devEmailController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _auth = widget.authService ?? UserAuthService();
  }

  @override
  void dispose() {
    _devEmailController.dispose();
    super.dispose();
  }

  Future<void> _signInWithGoogle() => _run(_auth.signInWithGoogle);

  Future<void> _devSignIn() {
    final email = _devEmailController.text.trim();
    if (email.isEmpty) {
      setState(() => _errorMessage = 'Enter an email for dev login.');
      return Future.value();
    }
    return _run(() => _auth.devSignIn(email));
  }

  Future<void> _run(Future<UserSignInOutcome?> Function() signIn) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final outcome = await signIn();
      if (!mounted) return;

      if (outcome == null) {
        // Dismissed the Google account picker.
        setState(() => _isLoading = false);
        return;
      }

      User? user = outcome.user;
      final registration = outcome.registration;
      if (registration != null) {
        setState(() => _isLoading = false);
        user = await Navigator.of(context).push<User>(
          MaterialPageRoute(
            builder: (_) => RegisterScreen(
              registration: registration,
              authService: _auth,
            ),
          ),
        );
        if (!mounted) return;
        if (user == null) {
          // Registration abandoned — drop the Google session too.
          await _auth.signOut();
          return;
        }
      }

      // Back to the root, which now finds a saved user and shows Home.
      Navigator.of(context).pushReplacementNamed('/');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'An unexpected error occurred. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency Ambulance'),
        backgroundColor: Colors.red[700],
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding:
                const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.local_hospital_rounded,
                  size: 72,
                  color: Colors.red,
                ),
                const SizedBox(height: 16),
                Text(
                  'Welcome',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Sign in to request an ambulance and follow it to your location.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[700],
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      border: Border.all(color: Colors.red.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error_outline,
                            color: Colors.red, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                                color: Colors.red, fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                if (_isLoading)
                  const Center(child: CircularProgressIndicator(color: Colors.red))
                else
                  OutlinedButton(
                    onPressed: _signInWithGoogle,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'G',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.blueAccent,
                          ),
                        ),
                        SizedBox(width: 12),
                        Text(
                          'Sign in with Google',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                if (kDebugMode) ...[
                  const SizedBox(height: 40),
                  Text(
                    'DEBUG: dev login (server needs ALLOW_DEV_LOGIN=true)',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _devEmailController,
                    enabled: !_isLoading,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _isLoading ? null : _devSignIn,
                    child: const Text('Dev login'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
