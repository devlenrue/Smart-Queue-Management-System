import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController(text: 'alice@example.com');
  final _passwordController = TextEditingController(text: 'password');
  bool _isRegistering = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final success = _isRegistering
        ? await auth.register(
            _nameController.text,
            _emailController.text,
            _passwordController.text,
          )
        : await auth.login(
            _emailController.text,
            _passwordController.text,
          );

    if (!mounted || success) return;
    // The provider exposes the error below. Keeping it in the form makes it
    // visible even when the keyboard is open.
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Consumer<AuthProvider>(
                    builder: (context, auth, _) {
                      return Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Icon(
                              Icons.queue_play_next_rounded,
                              size: 56,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Smart Queue',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _isRegistering
                                  ? 'Create a customer account'
                                  : 'Join the line without standing in it',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 28),
                            SegmentedButton<bool>(
                              segments: const [
                                ButtonSegment(value: false, label: Text('Login')),
                                ButtonSegment(value: true, label: Text('Register')),
                              ],
                              selected: {_isRegistering},
                              onSelectionChanged: (selection) {
                                setState(() {
                                  _isRegistering = selection.first;
                                });
                                auth.clearError();
                              },
                            ),
                            const SizedBox(height: 22),
                            if (_isRegistering) ...[
                              TextFormField(
                                controller: _nameController,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: 'Full name',
                                  prefixIcon: Icon(Icons.person_outline),
                                ),
                                validator: (value) => value == null || value.trim().length < 2
                                    ? 'Enter your name'
                                    : null,
                              ),
                              const SizedBox(height: 14),
                            ],
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Email address',
                                prefixIcon: Icon(Icons.email_outlined),
                              ),
                              validator: (value) => value == null || !value.contains('@')
                                  ? 'Enter a valid email'
                                  : null,
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              onFieldSubmitted: (_) => _submit(),
                              decoration: InputDecoration(
                                labelText: 'Password',
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                                  onPressed: () => setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  }),
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                ),
                              ),
                              validator: (value) => value == null || value.length < 6
                                  ? 'Use at least 6 characters'
                                  : null,
                            ),
                            if (auth.error != null) ...[
                              const SizedBox(height: 16),
                              Text(
                                auth.error!,
                                style: TextStyle(color: theme.colorScheme.error),
                              ),
                            ],
                            const SizedBox(height: 22),
                            FilledButton.icon(
                              onPressed: auth.isLoading ? null : _submit,
                              icon: auth.isLoading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : Icon(_isRegistering ? Icons.person_add : Icons.login),
                              label: Text(_isRegistering ? 'Create account' : 'Login'),
                            ),
                            if (!_isRegistering) ...[
                              const SizedBox(height: 18),
                              Text(
                                'Demo: alice@example.com / password',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
