import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/error_mapper.dart';
import '../../core/errors/failure.dart';
import '../../core/utils/responsive.dart';
import '../../core/utils/validators.dart';
import '../../providers/auth_providers.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/form_error_banner.dart';

/// §39. Registration always creates a **customer** — the role is decided by
/// the server and is not a field on this form. Staff and admin accounts are
/// created by an administrator (Phase 8).
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _firstName = TextEditingController();
  final TextEditingController _lastName = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();

  bool _submitting = false;
  bool _acceptedTerms = false;
  int _strength = 0;
  String? _formError;
  Map<String, String> _fieldErrors = const <String, String>{};

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _formError = null;
      _fieldErrors = const <String, String>{};
    });

    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (!_acceptedTerms) {
      setState(() => _formError = 'Please accept the terms to continue.');
      return;
    }

    setState(() => _submitting = true);
    try {
      await ref.read(authControllerProvider.notifier).register(
            firstName: _firstName.text,
            lastName: _lastName.text,
            email: _email.text,
            phone: _phone.text,
            password: _password.text,
            confirmPassword: _confirm.text,
          );
    } catch (error) {
      final Failure failure = ErrorMapper.fromObject(error);
      if (!mounted) return;
      setState(() {
        _formError = failure.userMessage;
        _fieldErrors = failure.fieldErrors;
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: Responsive.pagePadding(context),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      'One account lets you join any service queue on campus.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (_formError != null) ...<Widget>[
                      FormErrorBanner(message: _formError!),
                      const SizedBox(height: 16),
                    ],
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: AppTextField(
                            key: const Key('register-firstName'),
                            label: 'First name',
                            controller: _firstName,
                            textInputAction: TextInputAction.next,
                            autofillHints: const <String>[AutofillHints.givenName],
                            validator: (String? v) => Validators.name(v, 'First name'),
                            errorText: _fieldErrors['firstName'],
                            enabled: !_submitting,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AppTextField(
                            key: const Key('register-lastName'),
                            label: 'Last name',
                            controller: _lastName,
                            textInputAction: TextInputAction.next,
                            autofillHints: const <String>[AutofillHints.familyName],
                            validator: (String? v) => Validators.name(v, 'Last name'),
                            errorText: _fieldErrors['lastName'],
                            enabled: !_submitting,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    AppTextField(
                      key: const Key('register-email'),
                      label: 'Email',
                      controller: _email,
                      prefixIcon: Icons.mail_outline_rounded,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const <String>[AutofillHints.email],
                      validator: Validators.email,
                      errorText: _fieldErrors['email'],
                      enabled: !_submitting,
                    ),
                    const SizedBox(height: 16),
                    AppTextField(
                      key: const Key('register-phone'),
                      label: 'Phone number',
                      controller: _phone,
                      hint: '+254 700 000 000',
                      prefixIcon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      autofillHints: const <String>[AutofillHints.telephoneNumber],
                      validator: Validators.phone,
                      errorText: _fieldErrors['phone'],
                      enabled: !_submitting,
                    ),
                    const SizedBox(height: 16),
                    AppTextField(
                      key: const Key('register-password'),
                      label: 'Password',
                      controller: _password,
                      prefixIcon: Icons.lock_outline_rounded,
                      obscure: true,
                      textInputAction: TextInputAction.next,
                      autofillHints: const <String>[AutofillHints.newPassword],
                      helperText: 'At least 8 characters, with a letter and a number',
                      validator: Validators.password,
                      errorText: _fieldErrors['password'],
                      enabled: !_submitting,
                      onChanged: (String value) =>
                          setState(() => _strength = Validators.passwordStrength(value)),
                    ),
                    PasswordStrengthBar(
                      score: _strength,
                      label: Validators.passwordStrengthLabel(_strength),
                    ),
                    const SizedBox(height: 16),
                    AppTextField(
                      key: const Key('register-confirmPassword'),
                      label: 'Confirm password',
                      controller: _confirm,
                      prefixIcon: Icons.lock_reset_rounded,
                      obscure: true,
                      textInputAction: TextInputAction.done,
                      validator: (String? v) => Validators.confirmPassword(v, _password.text),
                      errorText: _fieldErrors['confirmPassword'],
                      enabled: !_submitting,
                      onSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      key: const Key('register-terms'),
                      value: _acceptedTerms,
                      onChanged: _submitting
                          ? null
                          : (bool? value) => setState(() => _acceptedTerms = value ?? false),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(
                        'I agree to queue fairly and to show up when called.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(height: 16),
                    AppButton(
                      key: const Key('register-submit'),
                      label: 'Create account',
                      isLoading: _submitting,
                      onPressed: _submit,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Text(
                          'Already registered?',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        TextButton(
                          onPressed: _submitting ? null : () => context.pop(),
                          child: const Text('Sign in'),
                        ),
                      ],
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
