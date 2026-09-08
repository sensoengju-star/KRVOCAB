import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/vocab_provider.dart';
import '../services/inbox_service.dart';
import '../theme/app_colors.dart';
import 'gold_button.dart';

/// Settings for the phone inbox: which synced folder to watch, and a way to
/// pull from it on demand.
///
/// There is no key and no account here — the phone does the API call and
/// writes a file, and this app only ever reads a folder that Google Drive (or
/// any other sync client) has already put on this disk.
class InboxSettings extends ConsumerStatefulWidget {
  const InboxSettings({super.key});

  @override
  ConsumerState<InboxSettings> createState() => _InboxSettingsState();
}

class _InboxSettingsState extends ConsumerState<InboxSettings> {
  final _folder = TextEditingController();
  bool _loading = true;
  bool _importing = false;
  InboxResult? _last;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final saved = await InboxService.instance.folder();
    if (!mounted) return;
    setState(() {
      _folder.text = saved ?? '';
      _loading = false;
    });
  }

  @override
  void dispose() {
    _folder.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final path = _folder.text.trim();
    if (path.isEmpty) {
      await InboxService.instance.clearFolder();
    } else {
      await InboxService.instance.setFolder(path);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(path.isEmpty ? 'Inbox folder cleared' : 'Inbox folder saved'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _importNow() async {
    await _save();
    setState(() => _importing = true);
    final result = await InboxService.instance.importNow();
    if (!mounted) return;
    if (result.changedAnything) ref.read(vocabProvider.notifier).refresh();
    setState(() {
      _importing = false;
      _last = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox(height: 8);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.hairline(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Synced folder',
            style: GoogleFonts.inter(
              color: AppColors.ink(context),
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Words captured on your phone are read from here at launch and '
            'whenever this window comes back into focus. Files are moved to a '
            'processed subfolder once imported, never deleted.',
            style: GoogleFonts.inter(
              color: AppColors.mutedInk(context),
              fontSize: 12,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _folder,
            style: GoogleFonts.inter(fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              hintText: InboxService.defaultFolder,
              hintStyle: GoogleFonts.inter(
                color: AppColors.mutedInk(context),
                fontSize: 13,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppColors.hairline(context)),
              ),
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              GoldButton(
                label: _importing ? 'Importing…' : 'Import now',
                icon: Icons.download_outlined,
                onPressed: _importing ? null : _importNow,
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _save,
                style:
                    TextButton.styleFrom(foregroundColor: AppColors.antiqueGold),
                child: Text('Save path',
                    style: GoogleFonts.inter(
                        fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          if (_last != null) ...[
            const SizedBox(height: 12),
            _Report(result: _last!),
          ],
        ],
      ),
    );
  }
}

class _Report extends StatelessWidget {
  const _Report({required this.result});
  final InboxResult result;

  @override
  Widget build(BuildContext context) {
    final bad = result.errors.isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: bad ? AppColors.inset(context) : AppColors.goldTint(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: bad
              ? AppColors.vermilion.withValues(alpha: 0.4)
              : AppColors.antiqueGold.withValues(alpha: 0.3),
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
                  result.summary,
                  style: GoogleFonts.inter(
                    color: AppColors.ink(context),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          // The specific reason matters here — "folder not found" and "that
          // file is still syncing" need very different responses.
          for (final e in result.errors)
            Padding(
              padding: const EdgeInsets.only(top: 5, left: 22),
              child: Text(
                e,
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
}
