import 'package:flutter/material.dart';

import 'package:bosstro/core/app_theme.dart';

/// A row of a settings group card that turns something on or off in place:
/// a 16-dp icon, the label, and a switch flush right. The whole row is the
/// target, at least 48 tall (DS-CMP-6, DS-A11Y-1), and reads as one switch.
///
/// The switch styles itself from the palette (the theme defines none): on is
/// the accent, with its ink for the thumb. [onChanged] null disables the
/// row, while what it turned on or off is still being done.
class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final pal = ShellPalette.of(context);
    final onChanged = this.onChanged;
    return MergeSemantics(
      child: InkWell(
        onTap: onChanged == null ? null : () => onChanged(!value),
        borderRadius: BorderRadius.circular(AppRadius.tile),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(icon, size: 16, color: pal.textTertiary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 13, color: pal.textBody),
                  ),
                ),
                const SizedBox(width: 10),
                Switch(
                  value: value,
                  onChanged: onChanged,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  thumbColor: WidgetStateProperty.resolveWith(
                    (states) =>
                        states.contains(WidgetState.selected)
                            ? pal.onLime
                            : pal.textTertiary,
                  ),
                  trackColor: WidgetStateProperty.resolveWith(
                    (states) =>
                        states.contains(WidgetState.selected)
                            ? pal.lime
                            : pal.inset,
                  ),
                  trackOutlineColor: WidgetStateProperty.all(pal.border),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
