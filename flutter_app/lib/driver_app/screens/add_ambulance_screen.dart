// lib/driver_app/screens/add_ambulance_screen.dart
//
// For a signed-in driver who has no ambulance yet. Collects the registration
// number and type (ALS / BLS / Both), registers it and pops with the new
// [AmbulanceModel] (or null if the driver backs out).

import 'package:flutter/material.dart';

import 'package:ambulance_app/driver_app/models/driver.dart';
import 'package:ambulance_app/driver_app/services/auth_service.dart';
import 'package:ambulance_app/driver_app/utils/validators.dart';
import 'package:ambulance_app/driver_app/widgets/ambulance_type_selector.dart';

class AddAmbulanceScreen extends StatefulWidget {
  const AddAmbulanceScreen({super.key});

  @override
  State<AddAmbulanceScreen> createState() => _AddAmbulanceScreenState();
}

class _AddAmbulanceScreenState extends State<AddAmbulanceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _plateController = TextEditingController();
  String? _vehicleType;
  bool _typeMissing = false;

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _plateController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final formOk = _formKey.currentState!.validate();
    setState(() => _typeMissing = _vehicleType == null);
    if (!formOk || _vehicleType == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final ambulance = await AuthService.addAmbulance(
        registrationNumber: _plateController.text.trim(),
        vehicleType: _vehicleType!,
      );
      if (!mounted) return;
      Navigator.of(context).pop<AmbulanceModel>(ambulance);
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
        appBar: AppBar(title: const Text('Add ambulance')),
        body: SafeArea(
          child: SingleChildScrollView(
            padding:
                const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Register the ambulance you drive so dispatch can send you incidents.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _plateController,
                    enabled: !_isLoading,
                    textInputAction: TextInputAction.done,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Ambulance registration number',
                      hintText: 'e.g. KL 07 AB 1234',
                      prefixIcon: Icon(Icons.local_shipping_outlined),
                      border: OutlineInputBorder(),
                    ),
                    validator: Validators.validateRegistrationNumber,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 16),
                  AmbulanceTypeSelector(
                    value: _vehicleType,
                    enabled: !_isLoading,
                    errorText: _typeMissing && _vehicleType == null
                        ? 'Choose ALS, BLS or Both'
                        : null,
                    onChanged: (v) => setState(() {
                      _vehicleType = v;
                      _typeMissing = false;
                    }),
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
                        : const Text('Add ambulance'),
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
