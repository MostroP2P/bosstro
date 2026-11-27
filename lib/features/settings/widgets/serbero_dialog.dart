import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bosstro/core/app_theme.dart';
import 'package:bosstro/features/nodes/models/node_display.dart';
import 'package:bosstro/features/settings/providers/language_provider.dart';
import 'package:bosstro/features/settings/providers/serbero_provider.dart';
import 'package:bosstro/l10n/app_localizations.dart';
import 'package:bosstro/shared/widgets/boxed_field.dart';
import 'package:bosstro/shared/widgets/mostro_modal.dart';

/// Set the Serbero pubkey trusted on [node] (D13), or stop trusting the one
/// set ([current], an npub). The core checks the key: an error stays in the
/// dialog, under the field (DS-CMP-15).
Future<void> showSerberoDialog(
  BuildContext context, {
  required String node,
  String? current,
}) => showMostroDialog<void>(
  context: context,
  builder: (_) => _SerberoDialog(node: node, current: current),
);

/// The copy for an error of `rust/src/api/serbero.rs`.
String localizedSerberoError(AppLocalizations l10n, Object error) =>
    error.toString().contains('SerberoIsNode')
        ? l10n.serberoErrorIsNode
        : localizedNodeError(l10n, error);

class _SerberoDialog extends ConsumerStatefulWidget {
  const _SerberoDialog({required this.node, this.current});

  final String node;
  final String? current;

  @override
  ConsumerState<_SerberoDialog> createState() => _SerberoDialogState();
}

class _SerberoDialogState extends ConsumerState<_SerberoDialog> {
  late final _pubkey = TextEditingController(text: widget.current ?? '');
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _pubkey.dispose();
    super.dispose();
  }

  Future<void> _write(String? pubkey) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    // The container outlives this dialog: a save that ends after it was
    // dismissed still refreshes what Settings shows.
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      await container
          .read(settingsCoreProvider)
          .setSerberoPubkey(widget.node, pubkey);
      container.invalidate(serberoNpubProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = localizedSerberoError(l10n, e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return MostroDialog(
      title: l10n.serberoDialogTitle,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.serberoDialogBody,
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: ShellPalette.of(context).textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          BoxedField(
            controller: _pubkey,
            label: l10n.serberoPubkeyLabel,
            hint: 'npub1…',
            mono: true,
            autofocus: true,
            errorText: _error,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _write(_pubkey.text),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
        ],
      ),
      links: [
        if (widget.current != null)
          ModalLink(
            label: l10n.serberoRemove,
            onPressed: _busy ? null : () => _write(null),
          ),
      ],
      secondary: ModalAction(
        label: l10n.cancel,
        onPressed: _busy ? null : () => Navigator.of(context).pop(),
      ),
      primary: ModalAction(
        label: l10n.serberoSave,
        busy: _busy,
        onPressed: () => _write(_pubkey.text),
      ),
    );
  }
}
