import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/tray_service.dart';
import '../services/vocab_export_service.dart';
import '../theme/app_colors.dart';
import 'settings_card.dart';

/// Whether Maldari keeps running after its window is closed, and how often it
/// looks for words while it does.
class TraySettings extends StatefulWidget {
  const TraySettings({super.key});

  @override
  State<TraySettings> createState() => _TraySettingsState();
}

class _TraySettingsState extends State<TraySettings> {
  bool _inTray = true;
  bool _atLogin = false;
  bool _export = true;
  bool _exporting = false;
  int _seconds = TrayService.defaultIntervalSeconds;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final inTray = await TrayService.instance.runInTray();
    final seconds = await TrayService.instance.intervalSeconds();
    final atLogin = await TrayService.instance.startsWithWindows();
    final export = await VocabExportService.instance.enabled();
    if (!mounted) return;
    setState(() {
      _inTray = inTray;
      _atLogin = atLogin;
      _export = export;
      _seconds = seconds;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox(height: 8);

    return SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Keep running when closed',
                      style: GoogleFonts.inter(
                        color: AppColors.ink(context),
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'The window hides to the notification area instead of '
                      'quitting, and words from your phone keep arriving on '
                      'their own. Quit from the tray icon when you mean it — '
                      'though you never have to: shutting Windows down with '
                      'Maldari still running costs nothing. See Data safety '
                      'in the header.',
                      style: GoogleFonts.inter(
                        color: AppColors.mutedInk(context),
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Switch(
                value: _inTray,
                activeThumbColor: AppColors.antiqueGold,
                onChanged: (v) async {
                  setState(() => _inTray = v);
                  await TrayService.instance.setRunInTray(v);
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
          Opacity(
            // Meaningless with the tray off — nothing is running to check.
            opacity: _inTray ? 1 : 0.45,
            child: IgnorePointer(
              ignoring: !_inTray,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Check for new words every',
                      style: GoogleFonts.inter(
                        color: AppColors.ink(context),
                        fontSize: 13,
                      ),
                    ),
                  ),
                  DropdownButton<int>(
                    value: _seconds,
                    underline: const SizedBox.shrink(),
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppColors.ink(context),
                      fontWeight: FontWeight.w600,
                    ),
                    items: [
                      for (final choice in TrayService.intervalChoices)
                        DropdownMenuItem(
                          value: choice,
                          child: Text(TrayService.intervalLabel(choice)),
                        ),
                    ],
                    onChanged: (v) async {
                      if (v == null) return;
                      setState(() => _seconds = v);
                      await TrayService.instance.setIntervalSeconds(v);
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Opacity(
            opacity: _inTray ? 1 : 0.45,
            child: IgnorePointer(
              ignoring: !_inTray,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Start with Windows',
                          style: GoogleFonts.inter(
                            color: AppColors.ink(context),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Opens at login, in front and ready.',
                          style: GoogleFonts.inter(
                            color: AppColors.mutedInk(context),
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _atLogin,
                    activeThumbColor: AppColors.antiqueGold,
                    onChanged: (v) async {
                      // Report what the registry actually says afterwards,
                      // not what was asked for — a switch that lies about a
                      // change that failed is worse than no switch.
                      final now =
                          await TrayService.instance.setStartsWithWindows(v);
                      if (!mounted) return;
                      setState(() => _atLogin = now);
                      if (now != v) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Windows would not accept that '
                                'change'),
                            duration: Duration(seconds: 3),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 26),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Readable on your phone',
                      style: GoogleFonts.inter(
                        color: AppColors.ink(context),
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Writes your whole collection to an export folder beside '
                      'the inbox — vocab.md to read, vocab.json for a Shortcut '
                      'to search. It follows the app, so what you see on the '
                      'phone is current. One-way: edits there are not read '
                      'back.',
                      style: GoogleFonts.inter(
                        color: AppColors.mutedInk(context),
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Switch(
                value: _export,
                activeThumbColor: AppColors.antiqueGold,
                onChanged: (v) async {
                  setState(() => _export = v);
                  await VocabExportService.instance.setEnabled(v);
                },
              ),
            ],
          ),
          if (_export) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _exporting
                    ? null
                    : () async {
                        setState(() => _exporting = true);
                        final ok =
                            await VocabExportService.instance.exportNow();
                        if (!mounted) return;
                        setState(() => _exporting = false);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(ok
                              ? 'Exported to the export folder'
                              : 'Nothing exported — set the synced folder '
                                  'above first'),
                          duration: const Duration(seconds: 3),
                        ));
                      },
                icon: const Icon(Icons.ios_share, size: 16),
                label: Text(_exporting ? 'Exporting…' : 'Export now',
                    style: GoogleFonts.inter(
                        fontSize: 12.5, fontWeight: FontWeight.w600)),
                style: TextButton.styleFrom(
                    foregroundColor: AppColors.antiqueGold),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            'A check on an empty folder costs nothing, and reading it seems '
            'to nudge iCloud into delivering sooner — so checking often is '
            'worth more than it looks. Words are only sent for definition '
            'when there are new ones.',
            style: GoogleFonts.inter(
              color: AppColors.mutedInk(context),
              fontSize: 11.5,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
