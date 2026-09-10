import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/storage_service.dart';
import '../theme/app_colors.dart';

/// What happens to your words when the app dies badly.
///
/// Every claim on this page describes code that actually runs — the flush
/// timer in [StorageService], the four shutdown hooks in main.dart, and the
/// quarantine-instead-of-delete recovery path. Keep them in step: a promise
/// here that the code stopped keeping is worse than no page at all.
class DataSafetySheet extends StatelessWidget {
  const DataSafetySheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const DataSafetySheet(),
      );

  @override
  Widget build(BuildContext context) {
    final notes = StorageService.instance.recoveryNotes;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.94,
      expand: false,
      builder: (context, controller) => Container(
        decoration: BoxDecoration(
          color: AppColors.surface(context),
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
          border: Border.all(color: AppColors.hairline(context)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.hairline(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.goldTint(context),
                    ),
                    child: const Icon(Icons.shield_outlined,
                        color: AppColors.antiqueGold, size: 21),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Data safety',
                          style: GoogleFonts.playfairDisplay(
                            color: AppColors.ink(context),
                            fontSize: 19,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Why your words survive an abrupt shutdown',
                          style: GoogleFonts.inter(
                            color: AppColors.mutedInk(context),
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 20),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
                children: [
                  _StatusCard(notes: notes),
                  const SizedBox(height: 16),
                  _sectionLabel(context, 'HOW IT SAVES'),
                  const _Point(
                    icon: Icons.power_off_outlined,
                    title: 'You never have to quit first',
                    body: 'Shut the machine down with Maldari still in the '
                        'tray, kill it from Task Manager, pull the plug — none '
                        'of it costs you a word. Nothing here depends on the '
                        'app being closed politely. Quitting from the tray is '
                        'tidier, not safer.',
                  ),
                  const _Point(
                    icon: Icons.save_outlined,
                    title: 'Written to disk within 0.4 seconds',
                    body: 'Adding or editing a word schedules a write almost '
                        'immediately. There is no save button and nothing to '
                        'remember to press. A burst of edits collapses into a '
                        'single write, so it stays fast.',
                  ),
                  const _Point(
                    icon: Icons.power_settings_new,
                    title: 'Four separate shutdown hooks',
                    body: 'Closing the window, the engine detaching, the app '
                        'going inactive, a hot restart — each one runs its own '
                        'save. No single hook catches every way an app can '
                        'end, so they are all wired up.',
                  ),
                  const _Point(
                    icon: Icons.laptop_chromebook_outlined,
                    title: 'Safe the moment it leaves the screen',
                    body: 'Closing the window to the tray saves everything '
                        'first, and so does going to the background or a '
                        'closing lid. Whatever kills the app after that '
                        'arrives too late to cost you anything.',
                  ),
                  const _Point(
                    icon: Icons.exit_to_app,
                    title: 'Quit saves before it does anything else',
                    body: 'Choosing Quit writes everything to disk before it '
                        'hides the window, closes the files or stops the '
                        'model. If the machine dies halfway through that '
                        'tidying, the words are already safe — the rest is '
                        'housekeeping, not something your data rests on.',
                  ),
                  const SizedBox(height: 10),
                  _sectionLabel(context, 'WHEN A FILE IS DAMAGED'),
                  const _Point(
                    icon: Icons.healing_outlined,
                    title: 'Checked and repaired at every launch',
                    body: 'If power was cut mid-write and the file ends in a '
                        'torn record, startup trims just that tail and opens '
                        'everything before it intact.',
                  ),
                  const _Point(
                    icon: Icons.inventory_2_outlined,
                    title: 'Never deleted, whatever the damage',
                    body: 'A file too damaged to repair is renamed aside as '
                        '.corrupt-<timestamp>.hive rather than removed, and a '
                        'fresh one is opened. Your data is still on disk and '
                        'can be recovered by hand.',
                  ),
                  const _Point(
                    icon: Icons.lock_outline,
                    title: 'Refuses rather than shows you an empty list',
                    body: 'If another copy of the app is holding the files, '
                        'this one will not start on empty stand-ins — that '
                        'looks exactly like having lost everything. It says so '
                        'instead, and waits. A lock is never mistaken for '
                        'damage, so a healthy file is never renamed aside.',
                  ),
                  const SizedBox(height: 10),
                  _sectionLabel(context, 'WHAT IS COVERED'),
                  const _Point(
                    icon: Icons.folder_copy_outlined,
                    title: 'All of it, not just the words',
                    body: 'Words, stories, archived sets, blocks, grammar and '
                        'the cached word pages are all stored and recovered '
                        'the same way.',
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Everything stays on this machine. None of it is sent to '
                    'a server.',
                    style: GoogleFonts.inter(
                      color: AppColors.mutedInk(context),
                      fontSize: 11.5,
                      height: 1.5,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 6, 0, 8),
        child: Text(
          text,
          style: GoogleFonts.inter(
            color: AppColors.antiqueGold,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
          ),
        ),
      );
}

/// Live state, so the page reports rather than only promises.
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.notes});

  final List<String> notes;

  @override
  Widget build(BuildContext context) {
    final storage = StorageService.instance;
    final clean = notes.isEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        color: clean ? AppColors.goldTint(context) : AppColors.inset(context),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: clean
              ? AppColors.antiqueGold.withValues(alpha: 0.35)
              : AppColors.vermilion.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                clean ? Icons.verified_outlined : Icons.build_outlined,
                size: 17,
                color: clean ? AppColors.antiqueGold : AppColors.vermilion,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  clean
                      ? 'This launch: nothing needed repair'
                      : 'This launch: something was repaired',
                  style: GoogleFonts.inter(
                    color: AppColors.ink(context),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${_count(() => storage.box.length)} words · '
            '${_count(() => storage.storiesBox.length)} stories · '
            '${_count(() => storage.setsBox.length)} archived sets',
            style: GoogleFonts.inter(
              color: AppColors.mutedInk(context),
              fontSize: 12,
            ),
          ),
          if (!clean) ...[
            const SizedBox(height: 10),
            for (final n in notes)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• $n',
                  style: GoogleFonts.inter(
                    color: AppColors.mutedInk(context),
                    fontSize: 11,
                    height: 1.45,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// The boxes throw if the app somehow reaches here before init — a status
  /// readout must never be the thing that crashes the app.
  static String _count(int Function() read) {
    try {
      return '${read()}';
    } catch (_) {
      return '—';
    }
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 16, color: AppColors.antiqueGold),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    color: AppColors.ink(context),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: GoogleFonts.inter(
                    color: AppColors.mutedInk(context),
                    fontSize: 12,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
