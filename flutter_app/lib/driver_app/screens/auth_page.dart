import 'package:flutter/material.dart';
import 'package:ambulance_app/driver_app/models/driver.dart';
import 'package:ambulance_app/driver_app/services/auth_service.dart';
import 'package:ambulance_app/driver_app/screens/home_screen.dart';

enum AuthStage {
  loading,
  stageA, // Signed out: Google Sign In button
  stageB, // Signed in: Select ambulance
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  AuthStage _stage = AuthStage.loading;

  DriverModel? _driver;
  List<AmbulanceModel> _ambulances = [];
  AmbulanceModel? _selectedAmbulance;

  bool _isActionLoading = false;
  String? _errorMessage;
  bool _isNotRegisteredError = false;

  @override
  void initState() {
    super.initState();
    _checkInitialSession();
  }

  Future<void> _checkInitialSession() async {
    setState(() {
      _stage = AuthStage.loading;
      _errorMessage = null;
    });

    try {
      final token = await AuthService.getStoredToken();
      final driver = await AuthService.getStoredDriver();
      final savedAmbulance = await AuthService.getSelectedAmbulance();

      if (token != null && driver != null) {
        if (savedAmbulance != null && mounted) {
          // Both token and ambulance exist -> go straight to Home
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => DriverHomeScreen(
                driver: driver,
                ambulance: savedAmbulance,
              ),
            ),
          );
          return;
        }

        // Token exists but no ambulance saved -> load ambulances for Stage B
        _driver = driver;
        await _loadAmbulances();
        return;
      }

      // No stored token -> Stage A
      if (mounted) {
        setState(() {
          _stage = AuthStage.stageA;
        });
      }
    } catch (e) {
      debugPrint('[AuthPage] Session check error: $e');
      if (mounted) {
        setState(() {
          _stage = AuthStage.stageA;
          _errorMessage = 'Session check error: $e';
        });
      }
    }
  }

  Future<void> _loadAmbulances() async {
    setState(() {
      _isActionLoading = true;
      _errorMessage = null;
    });

    try {
      final list = await AuthService.fetchMyAmbulances();
      if (!mounted) return;
      setState(() {
        _ambulances = list;
        _selectedAmbulance = list.isNotEmpty ? list.first : null;
        _stage = AuthStage.stageB;
        _isActionLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isActionLoading = false;
        _errorMessage = e.toString();
        // If session expired, drop to Stage A
        if (e.toString().contains('Session expired') ||
            e.toString().contains('Not authenticated')) {
          _stage = AuthStage.stageA;
        }
      });
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _isActionLoading = true;
      _errorMessage = null;
      _isNotRegisteredError = false;
    });

    try {
      final driver = await AuthService.signInWithGoogle();
      if (!mounted) return;

      if (driver == null) {
        // User dismissed the Google picker
        setState(() {
          _isActionLoading = false;
        });
        return;
      }

      _driver = driver;
      await _loadAmbulances();
    } on NotRegisteredDriverException catch (e) {
      if (!mounted) return;
      setState(() {
        _isActionLoading = false;
        _errorMessage = e.message;
        _isNotRegisteredError = true;
      });
    } on NetworkException catch (e) {
      if (!mounted) return;
      setState(() {
        _isActionLoading = false;
        _errorMessage = e.message;
      });
    } on ServerException catch (e) {
      if (!mounted) return;
      setState(() {
        _isActionLoading = false;
        _errorMessage = 'Server error (${e.statusCode}): ${e.message}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isActionLoading = false;
        _errorMessage = 'An unexpected error occurred: $e';
      });
    }
  }

  Future<void> _handleDevLogin(String email) async {
    setState(() {
      _isActionLoading = true;
      _errorMessage = null;
      _isNotRegisteredError = false;
    });

    try {
      final driver = await AuthService.devSignIn(email);
      if (!mounted) return;
      _driver = driver;
      await _loadAmbulances();
    } on NotRegisteredDriverException catch (e) {
      if (!mounted) return;
      setState(() {
        _isActionLoading = false;
        _errorMessage = e.message;
        _isNotRegisteredError = true;
      });
    } on NetworkException catch (e) {
      if (!mounted) return;
      setState(() {
        _isActionLoading = false;
        _errorMessage = e.message;
      });
    } on ServerException catch (e) {
      if (!mounted) return;
      setState(() {
        _isActionLoading = false;
        _errorMessage = 'Server error (${e.statusCode}): ${e.message}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isActionLoading = false;
        _errorMessage = 'An unexpected error occurred: $e';
      });
    }
  }

  Future<void> _handleSignOut() async {
    setState(() {
      _isActionLoading = true;
    });

    await AuthService.clearSession();

    if (!mounted) return;
    setState(() {
      _driver = null;
      _ambulances = [];
      _selectedAmbulance = null;
      _errorMessage = null;
      _isNotRegisteredError = false;
      _stage = AuthStage.stageA;
      _isActionLoading = false;
    });
  }

  Future<void> _handleContinue() async {
    if (_selectedAmbulance == null || _driver == null) return;

    setState(() {
      _isActionLoading = true;
    });

    await AuthService.saveSelectedAmbulance(_selectedAmbulance!);

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => DriverHomeScreen(
          driver: _driver!,
          ambulance: (
            id: _selectedAmbulance!.id,
            registrationNumber: _selectedAmbulance!.registrationNumber,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: switch (_stage) {
          AuthStage.loading => const Center(
              child: CircularProgressIndicator(),
            ),
          AuthStage.stageA => _buildStageA(),
          AuthStage.stageB => _buildStageB(),
        },
      ),
    );
  }

  // ── Stage A: Signed Out ──────────────────────────────────────────────────────

  Widget _buildStageA() {
    final theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // App Branding
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.local_hospital_rounded,
                size: 54,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'RapidAlert Driver',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Emergency Ambulance Dispatch & Response',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 48),

            // Error display
            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.colorScheme.error.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: theme.colorScheme.onErrorContainer,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onErrorContainer,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_isNotRegisteredError) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.account_circle, size: 18),
                        label: const Text('Try another Google account'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: theme.colorScheme.onErrorContainer,
                          side: BorderSide(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                        onPressed: _isActionLoading ? null : _handleSignOut,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Sign In Action
            if (_isActionLoading)
              const Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Signing in...'),
                  ],
                ),
              )
            else
              ElevatedButton(
                onPressed: _handleGoogleSignIn,
                style: ElevatedButton.styleFrom(
                  elevation: 2,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  backgroundColor: theme.colorScheme.surface,
                  foregroundColor: theme.colorScheme.onSurface,
                  side: BorderSide(
                    color: theme.colorScheme.outlineVariant,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Google "G" Icon / Logo
                    Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      child: const Text(
                        'G',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.blueAccent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Text(
                      'Sign in with Google',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 32),

            // ── Dev Login Bypass ──────────────────────────────────────────────
            Row(
              children: [
                Expanded(child: Divider(color: theme.colorScheme.outlineVariant)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  child: Text(
                    'DEVELOPMENT MODE',
                    style: theme.textTheme.labelSmall?.copyWith(
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
                Expanded(child: Divider(color: theme.colorScheme.outlineVariant)),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.developer_mode_rounded,
                          size: 20,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Quick Dev Login',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Bypass Google',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Select a pre-seeded demo driver to authenticate directly with PostgreSQL:',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildDevDriverTile(
                      name: 'Ramesh Kumar',
                      email: 'driver1@example.com',
                      details: '2 Ambulances (KL-07-AE-1234, KL-07-AE-5678)',
                      theme: theme,
                    ),
                    const SizedBox(height: 8),
                    _buildDevDriverTile(
                      name: 'Suresh Nair',
                      email: 'driver2@example.com',
                      details: '1 Ambulance (KL-01-BE-1111)',
                      theme: theme,
                    ),
                    const SizedBox(height: 8),
                    _buildDevDriverTile(
                      name: 'Anand V',
                      email: 'driver3@example.com',
                      details: '1 Ambulance (KL-01-BE-2222)',
                      theme: theme,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDevDriverTile({
    required String name,
    required String email,
    required String details,
    required ThemeData theme,
  }) {
    return InkWell(
      onTap: _isActionLoading ? null : () => _handleDevLogin(email),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Text(
                name[0],
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    details,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: theme.colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }

  // ── Stage B: Pick Ambulance ──────────────────────────────────────────────────

  Widget _buildStageB() {
    final theme = Theme.of(context);
    final driver = _driver;

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Driver Greeting Card
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    backgroundImage: driver?.photoUrl != null
                        ? NetworkImage(driver!.photoUrl!)
                        : null,
                    child: driver?.photoUrl == null
                        ? Text(
                            driver != null && driver.name.isNotEmpty
                                ? driver.name[0].toUpperCase()
                                : 'D',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome, ${driver?.name ?? "Driver"}',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          driver?.email ?? '',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.logout, size: 20),
                    tooltip: 'Sign Out',
                    onPressed: _isActionLoading ? null : _handleSignOut,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Header for ambulances list
          Text(
            'Select your ambulance for this shift',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Choose the vehicle you are operating today:',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 12),

          // Error display if any
          if (_errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18),
                    onPressed: _isActionLoading ? null : _loadAmbulances,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Ambulances list or Empty state
          Expanded(
            child: _isActionLoading
                ? const Center(child: CircularProgressIndicator())
                : _ambulances.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.no_crash_outlined,
                              size: 48,
                              color: theme.colorScheme.outline,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No ambulances linked',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 24.0),
                              child: Text(
                                'Your account has not been assigned to any ambulance yet. Please contact hospital dispatch.',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.refresh),
                              label: const Text('Refresh'),
                              onPressed: _loadAmbulances,
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _ambulances.length,
                        itemBuilder: (context, index) {
                          final ambulance = _ambulances[index];
                          final isSelected =
                              _selectedAmbulance?.id == ambulance.id;

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10.0),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () {
                                setState(() {
                                  _selectedAmbulance = ambulance;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? theme.colorScheme.primaryContainer
                                          .withValues(alpha: 0.4)
                                      : theme.colorScheme.surface,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isSelected
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.outlineVariant,
                                    width: isSelected ? 2 : 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? theme.colorScheme.primary
                                            : theme.colorScheme
                                                .surfaceContainerHighest,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.emergency,
                                        size: 22,
                                        color: isSelected
                                            ? theme.colorScheme.onPrimary
                                            : theme
                                                .colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            ambulance.registrationNumber,
                                            style: theme.textTheme.titleMedium
                                                ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Type: ${ambulance.vehicleType ?? "Standard"}',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                              color: theme.colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (isSelected)
                                      Icon(
                                        Icons.check_circle,
                                        color: theme.colorScheme.primary,
                                        size: 24,
                                      )
                                    else
                                      Icon(
                                        Icons.radio_button_unchecked,
                                        color: theme.colorScheme.outline,
                                        size: 24,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),

          // Continue Button
          const SizedBox(height: 16),
          FilledButton(
            onPressed: (_selectedAmbulance == null || _isActionLoading)
                ? null
                : _handleContinue,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: _isActionLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Continue to Dashboard',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
