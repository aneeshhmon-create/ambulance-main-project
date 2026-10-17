// lib/driver_app/screens/register_screen.dart
//
// Shown after Google sign-in when the account has no driver profile yet.
// Collects the driver's name and phone, creates the account, and pops with
// the new [DriverModel] (or null if the driver backs out).

import 'package:flutter/material.dart';

import 'package:ambulance_app/driver_app/models/driver.dart';
import 'package:ambulance_app/driver_app/services/auth_service.dart';
import 'package:ambulance_app/driver_app/utils/validators.dart';

class DriverRegisterScreen extends StatefulWidget {
  const DriverRegisterScreen({super.key, required this.registration});

  final PendingDriverRegistration registration;

  @override
  State<DriverRegisterScreen> createState() => _DriverRegisterScreenState();
}

class _DriverRegisterScreenState extends State<DriverRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  final _phoneController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.registration.name);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final driver = await AuthService.registerDriver(
        registration: widget.registration,
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop<DriverModel>(driver);
    } on NetworkException catch (e) {
      _showError(e.message);
    } on ServerException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('An unexpected error occurred: $e');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _errorMessage = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: !_isLoading,
      child: Scaffold(
        appBar: AppBar(title: const Text('Driver registration')),
        body: SafeArea(
          child: SingleChildScrollView(
            padding:
                const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: CircleAvatar(
                      radius: 36,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      backgroundImage: widget.registration.photoUrl != null
                          ? NetworkImage(widget.registration.photoUrl!)
                          : null,
                      child: widget.registration.photoUrl == null
                          ? Icon(Icons.person,
                              size: 40,
                              color: theme.colorScheme.onPrimaryContainer)
                          : null,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Welcome!',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.registration.email,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tell us a bit more so dispatch can identify and reach you.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 28),
                  TextFormField(
                    controller: _nameController,
                    enabled: !_isLoading,
                    textInputAction: TextInputAction.next,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Full Name',
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(),
                    ),
                    validator: Validators.validateName,
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _phoneController,
                    enabled: !_isLoading,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Mobile Number',
                      hintText: 'e.g. 9876543210 or +91 98765 43210',
                      prefixIcon: Icon(Icons.phone_outlined),
                      border: OutlineInputBorder(),
                    ),
                    validator: Validators.validatePhone,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 24),
                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(
                            color: theme.colorScheme.onErrorContainer),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  FilledButton(
                    onPressed: _isLoading ? null : _submit,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : const Text('Create account'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _isLoading
                        ? null
                        : () => Navigator.of(context).pop<DriverModel>(null),
                    child: const Text('Use a different Google account'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
