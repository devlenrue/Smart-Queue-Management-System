import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/responsive.dart';
import '../../core/utils/validators.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';

/// §39 lists a forgot-password screen, and §82 rules out an email service.
///
/// Rather than fake a reset link, this screen is honest: it tells the user
/// what actually happens on this system — an administrator resets it. No
/// request is sent, and nothing pretends to have been emailed.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _email = TextEditingController();
  bool _submitted = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _submitted = true);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Forgot password')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: Responsive.pagePadding(context),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: _submitted ? _confirmation(theme) : _form(theme),
            ),
          ),
        ),
      ),
    );
  }

  Widget _form(ThemeData theme) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Icon(Icons.lock_reset_rounded, size: 48, color: theme.colorScheme.primary),
          const SizedBox(height: 20),
          Text('Reset your password', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'This system does not send reset emails. Enter your address and '
            'we will show you how to get back in.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          AppTextField(
            label: 'Email',
            controller: _email,
            prefixIcon: Icons.mail_outline_rounded,
            keyboardType: TextInputType.emailAddress,
            validator: Validators.email,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 20),
          AppButton(label: 'Continue', onPressed: _submit),
        ],
      ),
    );
  }

  Widget _confirmation(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Icon(Icons.support_agent_rounded, size: 48, color: theme.colorScheme.primary),
        const SizedBox(height: 20),
        Text('Ask an administrator', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 12),
        Text(
          'Password resets for ${_email.text.trim()} are handled at the service desk. '
          'An administrator can set a new password for you after checking your ID.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        Text(
          'Once you are signed in you can change your own password from '
          'Profile → Change password.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 28),
        AppButton(label: 'Back to sign in', onPressed: () => context.pop()),
      ],
    );
  }
}
