import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/import_log.dart';
import '../theme/app_colors.dart';

/// Everything the phone inbox has brought in, newest first.
class ImportHistorySheet extends StatefulWidget {
  const ImportHistorySheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const ImportHistorySheet(),
      );

  @override
  State<ImportHistorySheet> createState() => _ImportHistorySheetState();
}

class _ImportHistorySheetState extends State<ImportHistorySheet> {
  List<ImportLogEntry> _entries = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await ImportLog.instance.entries();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Clear the import history?',
            style: GoogleFonts.playfairDisplay(fontSize: 18)),
        content: Text(
          'Only the log is cleared. Your words, and the files in the processed '
          'folder, are untouched.',
          style: GoogleFonts.inter(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear',
                style: TextStyle(color: AppColors.softRed)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ImportLog.instance.clear();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.35,
      maxChildSize: 0.92,
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
              padding: const EdgeInsets.fromLTRB(22, 16, 10, 6),
              child: Row(
                children: [
                  const Icon(Icons.history,
                      color: AppColors.antiqueGold, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Import history',
                          style: GoogleFonts.playfairDisplay(
                            color: AppColors.ink(context),
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Every import that added, corrected or complained',
                          style: GoogleFonts.inter(
                            color: AppColors.mutedInk(context),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_entries.isNotEmpty)
                    IconButton(
                      tooltip: 'Clear history',
                      icon: Icon(Icons.delete_sweep_outlined,
                          size: 19, color: AppColors.mutedInk(context)),
                      onPressed: _clear,
                    ),
                ],
              ),
            ),
            const Divider(height: 20),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _entries.isEmpty
                      ? _empty(context)
                      : ListView.builder(
                          controller: controller,
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
                          itemCount: _entries.length,
                          itemBuilder: (context, i) =>
                              _Entry(entry: _entries[i]),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(40, 0, 40, 40),
          child: Text(
            'Nothing imported yet.\n\nWords you capture on your phone will be '
            'listed here — including any spelling the model changed on the way '
            'in.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: AppColors.mutedInk(context),
              fontSize: 13,
              height: 1.6,
            ),
          ),
        ),
      );
}

class _Entry extends StatelessWidget {
  const _Entry({required this.entry});
  final ImportLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final bad = entry.hadTrouble;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
      decoration: BoxDecoration(
        color: bad ? AppColors.inset(context) : AppColors.goldTint(context),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: bad
              ? AppColors.vermilion.withValues(alpha: 0.35)
              : AppColors.antiqueGold.withValues(alpha: 0.28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                bad ? Icons.error_outline : Icons.check_circle_outline,
                size: 15,
                color: bad ? AppColors.vermilion : AppColors.antiqueGold,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  entry.summary,
                  style: GoogleFonts.inter(
                    color: AppColors.ink(context),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _stamp(entry.at),
                style: GoogleFonts.inter(
                  color: AppColors.mutedInk(context),
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
          // Corrections in Korean type — they are the words themselves, not
          // interface text.
          for (final c in entry.corrections)
            Padding(
              padding: const EdgeInsets.only(top: 5, left: 22),
              child: Text(
                '• $c',
                style: GoogleFonts.notoSerifKr(
                  color: AppColors.mutedInk(context),
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
          for (final e in entry.errors)
            Padding(
              padding: const EdgeInsets.only(top: 5, left: 22),
              child: Text(
                '• $e',
                style: GoogleFonts.inter(
                  color: AppColors.mutedInk(context),
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _stamp(DateTime d) {
    final now = DateTime.now();
    final sameDay =
        d.year == now.year && d.month == now.month && d.day == now.day;
    final time = '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
    return sameDay
        ? time
        : '${d.month.toString().padLeft(2, '0')}.'
            '${d.day.toString().padLeft(2, '0')} $time';
  }
}
