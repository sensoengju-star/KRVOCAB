import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/app_status_provider.dart';
import '../theme/app_colors.dart';

/// The header's answer to "can I rely on this right now?".
///
/// Quiet when things are fine and loud when they are not: a status that
/// shouted "READY" at you all day would train you to stop looking at it, and
/// then the one day it said otherwise would go unread.
class AppStatusPill extends ConsumerWidget {
  const AppStatusPill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStatusProvider);
    final building = s.isConstruction;

    // Amber for construction: the colour of a road sign, and outside the
    // app's gold palette on purpose so it cannot be mistaken for decoration.
    const amber = Color(0xFFE8A33C);
    final accent = building ? amber : const Color(0xFF6FBF8B);

    final label = building
        ? (s.note.isEmpty ? 'Under construction' : 'Under construction · ${s.note}')
        : 'Ready';

    return Tooltip(
      message: building
          ? 'Something is being worked on — tap for details'
          : 'Ready for use — tap to change',
      child: Material(
        color: building
            ? amber.withValues(alpha: 0.16)
            : AppColors.onyxLift,
        shape: StadiumBorder(
          side: BorderSide(color: accent.withValues(alpha: 0.55)),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => _edit(context, ref, s),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  building ? Icons.construction : Icons.check_circle,
                  size: 15,
                  color: accent,
                ),
                const SizedBox(width: 6),
                ConstrainedBox(
                  // A long note must not shove the header buttons off-screen.
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: building ? amber : AppColors.lightGold,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    AppStatusState current,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _StatusDialog(current: current, ref: ref),
    );
  }
}

class _StatusDialog extends StatefulWidget {
  const _StatusDialog({required this.current, required this.ref});

  final AppStatusState current;
  final WidgetRef ref;

  @override
  State<_StatusDialog> createState() => _StatusDialogState();
}

class _StatusDialogState extends State<_StatusDialog> {
  late AppStatus _status = widget.current.status;
  late final _note = TextEditingController(text: widget.current.note);

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final building = _status == AppStatus.construction;

    return AlertDialog(
      title: Text('App status',
          style: GoogleFonts.playfairDisplay(fontSize: 19)),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Mark the app as under construction while you are changing it, '
              'so it is obvious at a glance when something may not work yet.',
              style: GoogleFonts.inter(
                color: AppColors.mutedInk(context),
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            SegmentedButton<AppStatus>(
              segments: [
                ButtonSegment(
                  value: AppStatus.ready,
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: Text('Ready',
                      style: GoogleFonts.inter(fontSize: 12.5)),
                ),
                ButtonSegment(
                  value: AppStatus.construction,
                  icon: const Icon(Icons.construction, size: 16),
                  label: Text('Under construction',
                      style: GoogleFonts.inter(fontSize: 12.5)),
                ),
              ],
              selected: {_status},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _status = s.first),
            ),
            if (building) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _note,
                autofocus: true,
                maxLength: 40,
                style: GoogleFonts.inter(fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'What is being worked on? (optional)',
                  hintText: 'e.g. tray settings',
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () async {
            await widget.ref
                .read(appStatusProvider.notifier)
                .set(_status, note: _note.text);
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
