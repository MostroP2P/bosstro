import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:bosstro/core/app_theme.dart';
import 'package:bosstro/features/notifications/providers/push_providers.dart';
import 'package:bosstro/features/notifications/services/push_core.dart';
import 'package:bosstro/features/notifications/widgets/push_dialogs.dart';
import 'package:bosstro/features/settings/widgets/settings_switch_row.dart';
import 'package:bosstro/l10n/app_localizations.dart';
import 'package:bosstro/shared/widgets/order_data_card.dart';
import 'package:bosstro/shared/widgets/redesign_app_bar.dart';
import 'package:bosstro/shared/widgets/warning_note.dart';

/// Settings → Notifications: the switch of the new-dispute push, where its
/// watch on the push server stands, and what turning it on shares with
/// whom. Reached only where pushes can be received (`canPushProvider`).
///
/// Turning it on asks the OS for the permission and Google for a token
/// ([PushController.enable]); when either says no, a dialog says which and
/// the switch stays off.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  /// How often the status is read again while it is one that settles by
  /// itself: the core retries on its own and tells nobody when it worked.
  static const _recheck = Duration(seconds: 5);

  /// What the switch was last asked to become, while that is being done:
  /// it shows there at once and takes no other tap until it settles.
  bool? _turning;

  Timer? _rechecks;

  @override
  void initState() {
    super.initState();
    // The status on screen is the one of now, not of the last startup.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(pushControllerProvider.notifier).reconcile();
    });
    // Cheap: while the core is waiting it asks the server nothing.
    _rechecks = Timer.periodic(_recheck, (_) {
      final push = ref.read(pushControllerProvider);
      final settles =
          push.status == PushWatchStatus.rateLimited ||
          push.status == PushWatchStatus.serverUnavailable;
      if (_turning == null && push.enabled && settles) {
        ref.read(pushControllerProvider.notifier).reconcile();
      }
    });
  }

  @override
  void dispose() {
    _rechecks?.cancel();
    super.dispose();
  }

  Future<void> _set(bool on) async {
    final controller = ref.read(pushControllerProvider.notifier);
    setState(() => _turning = on);
    PushEnableResult? result;
    try {
      if (on) {
        result = await controller.enable();
      } else {
        await controller.disable();
      }
    } finally {
      if (mounted) setState(() => _turning = null);
    }
    if (!mounted || result == null) return;
    await showPushEnableFailure(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pal = ShellPalette.of(context);
    final push = ref.watch(pushControllerProvider);
    final note = TextStyle(
      fontSize: 12,
      height: 1.45,
      color: pal.textSecondary,
    );

    return Scaffold(
      backgroundColor: pal.bg,
      appBar: redesignAppBar(
        context,
        title: l10n.settingsNotifications,
        onBack: () => context.pop(),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            redesignSidePadding,
            8,
            redesignSidePadding,
            24,
          ),
          children: [
            OrderDataCard(
              rows: [
                SettingsSwitchRow(
                  icon: Icons.notifications_none_rounded,
                  label: l10n.notificationsNewDisputes,
                  value: _turning ?? push.enabled,
                  onChanged: _turning == null ? _set : null,
                ),
              ],
            ),
            if (_turning == null && push.enabled) ...[
              const SizedBox(height: 12),
              // Blocked by the OS comes first: with it nothing rings,
              // whatever the server holds.
              if (push.blocked)
                WarningNote(text: l10n.notificationsStatusBlocked)
              else
                _Status(status: push.status),
            ],
            const SizedBox(height: 16),
            Text(l10n.notificationsAbout, style: note),
            const SizedBox(height: 10),
            Text(l10n.notificationsPrivacy, style: note),
            const SizedBox(height: 10),
            Text(l10n.notificationsLanguageNote, style: note),
          ],
        ),
      ),
    );
  }
}

/// Where the watch stands, in words. What the solver has to act on (a
/// refused phone, a node the server does not cover) is a warning; what
/// settles by itself is a quiet line.
class _Status extends StatelessWidget {
  const _Status({required this.status});

  final PushWatchStatus? status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pal = ShellPalette.of(context);
    final (text, warns) = switch (status) {
      PushWatchStatus.registered => (l10n.notificationsStatusRegistered, false),
      PushWatchStatus.waiting => (l10n.notificationsStatusWaiting, false),
      PushWatchStatus.rateLimited => (
        l10n.notificationsStatusRateLimited,
        false,
      ),
      PushWatchStatus.serverUnavailable => (
        l10n.notificationsStatusServerUnavailable,
        false,
      ),
      PushWatchStatus.tokenRefused => (
        l10n.notificationsStatusTokenRefused,
        true,
      ),
      PushWatchStatus.nodeNotTrusted => (
        l10n.notificationsStatusNodeNotTrusted,
        true,
      ),
      // Off does not show here; not read yet shows nothing.
      PushWatchStatus.off || null => (null, false),
    };
    if (text == null) return const SizedBox.shrink();
    if (warns) return WarningNote(text: text);
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            height: 1.45,
            color:
                status == PushWatchStatus.registered
                    ? pal.limeText
                    : pal.textBody,
          ),
        ),
      ),
    );
  }
}
