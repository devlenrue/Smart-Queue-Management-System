import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/error_mapper.dart';
import '../../core/routing/route_paths.dart';
import '../../core/utils/responsive.dart';
import '../../models/announcement.dart';
import '../../models/service.dart';
import '../../providers/admin_providers.dart';
import '../../providers/paged_state.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/error_state.dart';
import '../../widgets/form_error_banner.dart';
import 'admin_shell.dart';

/// The composer.
///
/// "Publish now" is a checkbox rather than a second screen because the
/// server treats it as one transition: a notice created as `published`
/// fans out its notifications immediately, exactly as if it had been saved
/// as a draft and published a moment later.
class AnnouncementFormScreen extends ConsumerStatefulWidget {
  const AnnouncementFormScreen({super.key, this.announcementId});

  final int? announcementId;

  @override
  ConsumerState<AnnouncementFormScreen> createState() => _AnnouncementFormScreenState();
}

class _AnnouncementFormScreenState extends ConsumerState<AnnouncementFormScreen> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _content = TextEditingController();

  int? _serviceId;
  bool _publishNow = false;
  bool _loaded = false;
  bool _busy = false;
  Object? _error;

  bool get _isEdit => widget.announcementId != null;

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  void _fill(ManagedAnnouncement item) {
    if (_loaded) return;
    _loaded = true;
    _title.text = item.title;
    _content.text = item.content;
    _serviceId = item.serviceId;
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final AdminActionController actions = ref.read(adminActionProvider.notifier);
      if (_isEdit) {
        await actions.updateAnnouncement(
          widget.announcementId!,
          title: _title.text.trim(),
          content: _content.text.trim(),
          serviceId: _serviceId,
          clearService: _serviceId == null,
        );
        if (_publishNow) await actions.publishAnnouncement(widget.announcementId!);
      } else {
        await actions.createAnnouncement(
          title: _title.text.trim(),
          content: _content.text.trim(),
          serviceId: _serviceId,
          publishNow: _publishNow,
        );
      }

      if (!mounted) return;
      showSuccessSnackBar(
        context,
        _publishNow ? 'Published — customers have been notified.' : 'Saved as a draft.',
      );
      context.go(RoutePaths.adminAnnouncements);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // The list is already in memory when the composer is opened from it, so
    // editing reads from there rather than issuing another request. A deep
    // link that misses simply starts from an empty form.
    if (_isEdit && !_loaded) {
      final PagedState<ManagedAnnouncement>? page =
          ref.watch(adminAnnouncementsProvider).valueOrNull;
      if (page != null) {
        for (final ManagedAnnouncement item in page.items) {
          if (item.id == widget.announcementId) {
            _fill(item);
            break;
          }
        }
      }
    }

    final List<Service> services =
        ref.watch(adminServicesProvider).valueOrNull ?? const <Service>[];

    return AdminPage(
      title: _isEdit ? 'Edit notice' : 'New notice',
      actions: <Widget>[
        TextButton(
          onPressed: _busy ? null : () => context.go(RoutePaths.adminAnnouncements),
          child: const Text('Cancel'),
        ),
      ],
      body: Form(
        key: _form,
        child: ListView(
          padding: Responsive.pagePadding(context),
          children: <Widget>[
            if (_error != null) ...<Widget>[
              FormErrorBanner(message: ErrorMapper.fromObject(_error!).userMessage),
              const SizedBox(height: 12),
            ],
            AppCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  AppTextField(
                    key: const Key('announcement-title'),
                    label: 'Title',
                    controller: _title,
                    validator: (String? v) =>
                        (v ?? '').trim().length < 3 ? 'Give the notice a title' : null,
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    key: const Key('announcement-content'),
                    label: 'Message',
                    controller: _content,
                    maxLines: 6,
                    validator: (String? v) =>
                        (v ?? '').trim().length < 10 ? 'Say a little more than that' : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    key: const Key('announcement-service'),
                    value: _serviceId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Who is it for?',
                      border: OutlineInputBorder(),
                    ),
                    items: <DropdownMenuItem<int?>>[
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('Everyone'),
                      ),
                      for (final Service service in services)
                        DropdownMenuItem<int?>(
                          value: service.id,
                          child: Text('${service.name} only'),
                        ),
                    ],
                    onChanged: (int? id) => setState(() => _serviceId = id),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    key: const Key('announcement-publish'),
                    contentPadding: EdgeInsets.zero,
                    value: _publishNow,
                    onChanged: (bool? value) => setState(() => _publishNow = value ?? false),
                    title: const Text('Publish immediately'),
                    subtitle: const Text(
                      'Every active customer receives a notification, once.',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AppButton(
              key: const Key('announcement-save'),
              label: _publishNow ? 'Save and publish' : 'Save draft',
              isLoading: _busy,
              onPressed: _busy ? null : _save,
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
