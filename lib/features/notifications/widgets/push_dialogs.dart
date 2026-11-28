import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bosstro/features/notifications/providers/push_providers.dart';
import 'package:bosstro/l10n/app_localizations.dart';
import 'package:bosstro/shared/widgets/mostro_modal.dart';

/// Says why notifications were not turned on, when they were not: the
/// permission was refused, or Google gave no token. Nothing for
/// [PushEnableResult.enabled].
Future<void> showPushEnableFailure(
  BuildContext context,
  PushEnableResult result,
) async {
  final l10n = AppLocalizations.of(context);
  final (title, body) = switch (result) {
    PushEnableResult.enabled => (null, null),
    PushEnableResult.permissionDenied => (
      l10n.notificationsBlockedTitle,
      l10n.notificationsBlockedBody,
    ),
    PushEnableResult.unavailable => (
      l10n.notificationsUnavailableTitle,
      l10n.notificationsUnavailableBody,
    ),
  };
  if (title == null) return;
  await showMostroDialog<void>(
    context: context,
    builder:
        (dialog) => MostroDialog(
          icon: Icons.notifications_off_outlined,
          title: title,
          body: body,
          primary: ModalAction(
            label: MaterialLocalizations.of(dialog).okButtonLabel,
            onPressed: () => Navigator.of(dialog).pop(),
          ),
        ),
  );
}

/// The one time the app brings notifications up by itself: right after the
/// solver picks a node for the first time. It says what a notification does
/// and what turning it on shares, and takes yes or "not now"; afterwards the
/// switch is in Settings → Notifications and nothing asks again.
///
/// Nothing shows where no push can be received, when the offer was already
/// made, or when notifications are already on. Accepting asks the OS for
/// the permission and Google for a token; a refusal of either is said.
Future<void> offerPushNotifications(BuildContext context, WidgetRef ref) async {
  final controller = ref.read(pushControllerProvider.notifier);
  if (!await controller.takeOffer()) return;
  if (!context.mounted) return;
  final l10n = AppLocalizations.of(context);
  final accepted = await showMostroDialog<bool>(
    context: context,
    builder:
        (dialog) => MostroDialog(
          icon: Icons.notifications_none_rounded,
          title: l10n.pushOfferTitle,
          body: l10n.pushOfferBody,
          secondary: ModalAction(
            label: l10n.pushOfferDecline,
            onPressed: () => Navigator.of(dialog).pop(false),
          ),
          primary: ModalAction(
            label: l10n.pushOfferAccept,
            onPressed: () => Navigator.of(dialog).pop(true),
          ),
        ),
  );
  if (accepted != true) return;
  final result = await controller.enable();
  if (!context.mounted) return;
  await showPushEnableFailure(context, result);
}
