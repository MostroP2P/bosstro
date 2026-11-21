import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bosstro/core/app_theme.dart';
import 'package:bosstro/features/serbero/providers/serbero_providers.dart';
import 'package:bosstro/features/serbero/screens/serbero_screen.dart';
import 'package:bosstro/features/serbero/services/serbero_core.dart';
import 'package:bosstro/features/settings/providers/serbero_provider.dart';
import 'package:bosstro/l10n/app_localizations.dart';
import 'package:bosstro/shared/utils/date_time_format.dart';
import 'package:bosstro/shared/widgets/labeled_icon_action.dart';
import 'package:bosstro/shared/widgets/order_data_card.dart';

/// The Info segment's way into Serbero's mediation of the dispute (D13):
/// when its last report arrived and "Read Serbero's mediation", or why
/// there is nothing to read.
class SerberoCard extends ConsumerWidget {
  const SerberoCard({super.key, required this.disputeId});

  final String disputeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final read = ref.watch(serberoMediationProvider(disputeId));
    // Never the previous value while the node, the key or the trusted
    // Serbero changes, nor after a failed read: it may be a report the
    // solver no longer trusts.
    final mediation =
        read.isReloading || read.hasError ? null : read.valueOrNull;
    if (mediation == null) return const SizedBox.shrink();
    final trusted = ref.watch(serberoNpubProvider).valueOrNull != null;
    final l10n = AppLocalizations.of(context);
    final pal = ShellPalette.of(context);
    final locale = Localizations.localeOf(context).toString();
    final last = mediation.lastSentAt;

    final line =
        last != null
            ? l10n.serberoCardReceived(formatDateTime(last, locale))
            : trusted
            ? l10n.serberoCardEmpty
            : l10n.serberoCardNotTrusted;

    // The action's own 10-dp padding lines its icon up with the title's, as
    // ObserverCard.
    const actionPadding = 10.0;
    return SurfaceCard(
      padding: EdgeInsetsDirectional.fromSTEB(
        14 - actionPadding,
        14,
        14,
        mediation.isBlank ? 14 : 6,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: actionPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.smart_toy_outlined,
                      size: 16,
                      color: pal.textTertiary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.serberoCardTitle,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: pal.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  line,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: pal.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (!mediation.isBlank) ...[
            const SizedBox(height: 4),
            LabeledIconAction(
              icon: Icons.article_outlined,
              label: l10n.serberoReadAction,
              onPressed: () => openSerberoScreen(context, disputeId),
            ),
          ],
        ],
      ),
    );
  }
}
