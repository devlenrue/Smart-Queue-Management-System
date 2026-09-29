import 'package:flutter/material.dart';

import '../../../core/constants/enums.dart';
import '../../../widgets/status_badge.dart';

/// An account's status as a badge.
///
/// [StatusBadge] has named constructors for the four domain enums but not
/// for `UserStatus`, which only the admin console ever renders — so the
/// mapping lives here rather than in the shared widget.
class UserStatusChip extends StatelessWidget {
  const UserStatusChip({super.key, required this.status, this.dense = true});

  final UserStatus status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    final (String label, Color color, IconData icon) = switch (status) {
      UserStatus.active => ('Active', scheme.primary, Icons.check_circle_outline_rounded),
      UserStatus.inactive => ('Inactive', scheme.outline, Icons.pause_circle_outline_rounded),
      UserStatus.suspended => ('Suspended', scheme.error, Icons.block_rounded),
    };

    return StatusBadge(label: label, color: color, icon: icon, dense: dense);
  }
}
