import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/error_mapper.dart';
import '../../core/errors/failure.dart';
import '../../core/routing/route_paths.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../core/utils/validators.dart';
import '../../models/user.dart';
import '../../providers/auth_providers.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/confirmation_dialog.dart';
import '../../widgets/error_state.dart';
import '../../widgets/form_error_banner.dart';
import '../../widgets/loading_widget.dart';

/// §49. Who you are, plus the two things you can change about it.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final bool confirmed = await ConfirmationDialog.show(
      context,
      title: 'Sign out?',
      message: 'You will need to sign in again to see your tickets.',
      confirmLabel: 'Sign out',
      isDestructive: true,
      icon: Icons.logout_rounded,
    );
    if (!confirmed) return;
    await ref.read(authControllerProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final User? user = ref.watch(currentUserProvider);

    if (user == null) return const Scaffold(body: LoadingView());

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: Responsive.pagePadding(context),
        children: <Widget>[
          Row(
            children: <Widget>[
              CircleAvatar(
                radius: 32,
                backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
                child: Text(
                  Formatters.initials(user.firstName, user.lastName),
                  style: theme.textTheme.titleLarge?.copyWith(color: theme.colorScheme.primary),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(user.fullName, style: theme.textTheme.titleLarge),
                    const SizedBox(height: 2),
                    Text(
                      user.email,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Chip(
                      label: Text(user.role.label),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.10),
                      labelStyle: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.colorScheme.primary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          AppCard(
            child: Column(
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.phone_outlined),
                  title: const Text('Phone'),
                  subtitle: Text(user.phone),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.event_outlined),
                  title: const Text('Member since'),
                  subtitle: Text(Formatters.fullDate(Formatters.parse(user.createdAt))),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppCard(
            child: Column(
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Edit profile'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _EditProfileSheet.show(context, user),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.lock_outline_rounded),
                  title: const Text('Change password'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _ChangePasswordSheet.show(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('Settings'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(RoutePaths.settings),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: const Text('About SmartQueue'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(RoutePaths.about),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          AppSecondaryButton(
            label: 'Sign out',
            icon: Icons.logout_rounded,
            isDestructive: true,
            onPressed: () => _logout(context, ref),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _EditProfileSheet extends ConsumerStatefulWidget {
  const _EditProfileSheet({required this.user});

  final User user;

  static Future<void> show(BuildContext context, User user) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext context) => _EditProfileSheet(user: user),
    );
  }

  @override
  ConsumerState<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends ConsumerState<_EditProfileSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _firstName =
      TextEditingController(text: widget.user.firstName);
  late final TextEditingController _lastName = TextEditingController(text: widget.user.lastName);
  late final TextEditingController _phone = TextEditingController(text: widget.user.phone);

  bool _submitting = false;
  String? _error;
  Map<String, String> _fieldErrors = const <String, String>{};

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
      _fieldErrors = const <String, String>{};
    });

    try {
      await ref.read(authControllerProvider.notifier).updateProfile(
            firstName: _firstName.text,
            lastName: _lastName.text,
            phone: _phone.text,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      showSuccessSnackBar(context, 'Profile updated.');
    } catch (error) {
      final Failure failure = ErrorMapper.fromObject(error);
      if (!mounted) return;
      setState(() {
        _error = failure.userMessage;
        _fieldErrors = failure.fieldErrors;
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 4,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('Edit profile', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            if (_error != null) ...<Widget>[
              FormErrorBanner(message: _error!),
              const SizedBox(height: 16),
            ],
            AppTextField(
              label: 'First name',
              controller: _firstName,
              validator: (String? v) => Validators.name(v, 'First name'),
              errorText: _fieldErrors['firstName'],
              enabled: !_submitting,
            ),
            const SizedBox(height: 14),
            AppTextField(
              label: 'Last name',
              controller: _lastName,
              validator: (String? v) => Validators.name(v, 'Last name'),
              errorText: _fieldErrors['lastName'],
              enabled: !_submitting,
            ),
            const SizedBox(height: 14),
            AppTextField(
              label: 'Phone number',
              controller: _phone,
              keyboardType: TextInputType.phone,
              validator: Validators.phone,
              errorText: _fieldErrors['phone'],
              enabled: !_submitting,
            ),
            const SizedBox(height: 14),
            Text(
              'Your email address is your sign-in name and cannot be changed here.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 20),
            AppButton(label: 'Save changes', isLoading: _submitting, onPressed: _save),
          ],
        ),
      ),
    );
  }
}

class _ChangePasswordSheet extends ConsumerStatefulWidget {
  const _ChangePasswordSheet();

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext context) => const _ChangePasswordSheet(),
    );
  }

  @override
  ConsumerState<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends ConsumerState<_ChangePasswordSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _current = TextEditingController();
  final TextEditingController _next = TextEditingController();
  final TextEditingController _confirm = TextEditingController();

  bool _submitting = false;
  String? _error;
  Map<String, String> _fieldErrors = const <String, String>{};

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
      _fieldErrors = const <String, String>{};
    });

    try {
      await ref.read(authControllerProvider.notifier).changePassword(
            currentPassword: _current.text,
            newPassword: _next.text,
            confirmPassword: _confirm.text,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      showSuccessSnackBar(context, 'Password changed.');
    } catch (error) {
      final Failure failure = ErrorMapper.fromObject(error);
      if (!mounted) return;
      setState(() {
        _error = failure.userMessage;
        _fieldErrors = failure.fieldErrors;
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 4,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('Change password', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            if (_error != null) ...<Widget>[
              FormErrorBanner(message: _error!),
              const SizedBox(height: 16),
            ],
            AppTextField(
              label: 'Current password',
              controller: _current,
              obscure: true,
              validator: (String? v) => Validators.required(v, label: 'Current password'),
              errorText: _fieldErrors['currentPassword'],
              enabled: !_submitting,
            ),
            const SizedBox(height: 14),
            AppTextField(
              label: 'New password',
              controller: _next,
              obscure: true,
              helperText: 'At least 8 characters, with a letter and a number',
              validator: Validators.password,
              errorText: _fieldErrors['newPassword'],
              enabled: !_submitting,
            ),
            const SizedBox(height: 14),
            AppTextField(
              label: 'Confirm new password',
              controller: _confirm,
              obscure: true,
              validator: (String? v) => Validators.confirmPassword(v, _next.text),
              errorText: _fieldErrors['confirmPassword'],
              enabled: !_submitting,
            ),
            const SizedBox(height: 20),
            AppButton(label: 'Update password', isLoading: _submitting, onPressed: _save),
          ],
        ),
      ),
    );
  }
}
