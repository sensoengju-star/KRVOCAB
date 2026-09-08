import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../models/vocab_word.dart';
import '../providers/review_settings_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/tts_settings_provider.dart';
import '../providers/vocab_provider.dart';
import '../services/llm_launcher.dart';
import '../services/llm_service.dart';
import '../services/storage_service.dart';
import '../services/tts_service.dart';
import '../theme/app_colors.dart';
import '../widgets/elevenlabs_settings.dart';
import '../widgets/gold_button.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _serverPath = TextEditingController();
  final _modelPath = TextEditingController();
  final _endpoint = TextEditingController();
  final _alias = TextEditingController();

  bool _serverUp = false;
  Timer? _poller;

  @override
  void initState() {
    super.initState();
    _loadPaths();
    _poll();
    // Poll every 5s instead of 3s. Cheap HTTP call, but no need to thrash.
    _poller = Timer.periodic(const Duration(seconds: 5), (_) => _poll());
  }

  @override
  void dispose() {
    _poller?.cancel();
    _serverPath.dispose();
    _modelPath.dispose();
    _endpoint.dispose();
    _alias.dispose();
    super.dispose();
  }

  Future<void> _loadPaths() async {
    _serverPath.text = await LlmLauncher.instance.serverPath();
    _modelPath.text = await LlmLauncher.instance.modelPath();
    final cfg = await LlmConfig.load();
    _endpoint.text = cfg.endpoint;
    _alias.text = cfg.modelAlias;
    if (mounted) setState(() {});
  }

  Future<void> _poll() async {
    final ok = await LlmLauncher.instance.isHealthy();
    if (mounted && ok != _serverUp) setState(() => _serverUp = ok);
  }

  Future<void> _mergeDuplicates() async {
    final removed = await ref.read(vocabProvider.notifier).mergeDuplicates();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          removed == 0
              ? 'No duplicates found'
              : 'Merged $removed duplicate ${removed == 1 ? 'entry' : 'entries'}',
        ),
      ),
    );
  }

  Future<void> _confirmDeleteLearning() async {
    final count = ref
        .read(vocabProvider)
        .where((w) => w.status == WordStatus.learning)
        .length;
    if (count == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No learning words to delete')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Delete $count learning word${count == 1 ? '' : 's'}?',
          style: GoogleFonts.playfairDisplay(fontSize: 18),
        ),
        content: Text(
          'This permanently removes every word currently marked as Learning. '
          'This cannot be undone.',
          style: GoogleFonts.inter(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.softRed),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final removed =
          await ref.read(vocabProvider.notifier).deleteAllLearning();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Deleted $removed learning word${removed == 1 ? '' : 's'}')),
        );
      }
    }
  }

  Future<void> _confirmDeleteReinforced() async {
    final count = ref
        .read(vocabProvider)
        .where((w) => w.status == WordStatus.reinforcement)
        .length;
    if (count == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No reinforced words to delete')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Delete $count reinforced word${count == 1 ? '' : 's'}?',
          style: GoogleFonts.playfairDisplay(fontSize: 18),
        ),
        content: Text(
          'This permanently removes every word currently marked for '
          'reinforcement. This cannot be undone.',
          style: GoogleFonts.inter(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.softRed),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final removed =
          await ref.read(vocabProvider.notifier).deleteAllReinforced();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Deleted $removed reinforced word${removed == 1 ? '' : 's'}')),
        );
      }
    }
  }

  Future<void> _exportJson() async {
    final words = ref.read(vocabProvider);
    final data = jsonEncode(words.map((e) => e.toJson()).toList());
    await Share.share(data, subject: 'Maldari vocabulary export');
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(themeModeProvider);
    final includeReinforcement = ref.watch(includeReinforcementProvider);
    final learningOnly = ref.watch(learningOnlyProvider);
    final autoSpeak = ref.watch(autoSpeakProvider);
    final speechRate = ref.watch(speechRateProvider);
    final recovery = StorageService.instance.recoveryNotes;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      children: [
        // Only appears when the last launch had to repair a data file — an
        // abrupt shutdown should never leave the user wondering silently
        // where their words went.
        if (recovery.isNotEmpty) ...[
          _section(context, 'Data recovery'),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.champagne.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.antiqueGold),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.healing_outlined,
                        size: 18, color: AppColors.deepGold),
                    const SizedBox(width: 8),
                    Text(
                      'A data file was repaired at startup',
                      style: GoogleFonts.inter(
                        color: AppColors.deepGold,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Nothing was deleted. Any file that could not be reopened '
                  'was kept alongside it, renamed with ".corrupt-", in the '
                  'app\'s documents folder.',
                  style: GoogleFonts.inter(fontSize: 12.5, height: 1.5),
                ),
                const SizedBox(height: 8),
                for (final note in recovery)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '· $note',
                      style: GoogleFonts.inter(
                        color: AppColors.mutedInk(context),
                        fontSize: 11.5,
                        height: 1.4,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const GoldDiamondDivider(),
        ],
        _section(context, 'Appearance'),
        _Tile(
          title: 'Dark mode',
          subtitle: 'Obsidian ink with cream text',
          trailing: Switch(
            value: mode == ThemeMode.dark,
            activeColor: AppColors.antiqueGold,
            onChanged: (_) => ref.read(themeModeProvider.notifier).toggle(),
          ),
        ),
        const GoldDiamondDivider(),

        _section(context, 'Pronunciation'),
        if (!TtsService.instance.isKoreanAvailable)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.champagne.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.antiqueGold),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.volume_off_outlined,
                    size: 18, color: AppColors.deepGold),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    TtsService.instance.unavailableReason ??
                        'No Korean voice found on this device.',
                    style: GoogleFonts.inter(fontSize: 12.5, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(
            'Words are spoken by the local system voice — free, offline and '
            'instant. Only story narration uses ElevenLabs.',
            style: GoogleFonts.inter(
              color: AppColors.mutedInk(context),
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ),
        _Tile(
          title: 'Speak the answer automatically',
          subtitle: 'Pronounce each word when its card turns to the answer',
          trailing: Switch(
            value: autoSpeak,
            activeColor: AppColors.antiqueGold,
            onChanged: (v) => ref.read(autoSpeakProvider.notifier).set(v),
          ),
        ),
        _Tile(
          title: 'Speaking speed',
          subtitle: 'Slower is easier to imitate — these are single words',
          trailing: SizedBox(
            width: 140,
            child: Slider(
              value: speechRate,
              min: 0.2,
              max: 0.9,
              divisions: 7,
              label: speechRate.toStringAsFixed(2),
              onChanged: (v) => ref.read(speechRateProvider.notifier).set(v),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: GoldOutlinedButton(
              label: '들어보기  ·  안녕하세요',
              icon: Icons.volume_up_outlined,
              onPressed: TtsService.instance.isKoreanAvailable
                  ? () => TtsService.instance.speak('안녕하세요')
                  : null,
            ),
          ),
        ),
        const GoldDiamondDivider(),

        _section(context, 'Story narration'),
        const ElevenLabsSettings(),
        const GoldDiamondDivider(),

        _section(context, 'Review'),
        _Tile(
          title: 'Learning only',
          subtitle:
              'Restrict the review deck to words still marked as Learning '
              '(excludes Reinforced words)',
          trailing: Switch(
            value: learningOnly,
            activeColor: AppColors.antiqueGold,
            onChanged: (v) {
              ref.read(learningOnlyProvider.notifier).set(v);
              // Mutually exclusive with the "Include …" toggles.
              if (v) ref.read(includeReinforcementProvider.notifier).set(false);
            },
          ),
        ),
        _Tile(
          title: 'Include reinforced words',
          subtitle: 'Show words marked for reinforcement in the review deck',
          trailing: Switch(
            value: includeReinforcement,
            activeColor: AppColors.antiqueGold,
            onChanged: (v) {
              ref.read(includeReinforcementProvider.notifier).set(v);
              // Mutually exclusive with "Learning only".
              if (v) ref.read(learningOnlyProvider.notifier).set(false);
            },
          ),
        ),
        const GoldDiamondDivider(),

        _section(context, 'LLM Server'),
        _Tile(
          title: 'Status',
          subtitle: _serverUp
              ? 'running'
              : (LlmLauncher.instance.lastError ?? 'offline'),
          trailing: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: _serverUp ? AppColors.softGreen : AppColors.softRed,
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _serverPath,
          decoration: const InputDecoration(labelText: 'llama-server.exe path'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _modelPath,
          decoration: const InputDecoration(labelText: 'Model .gguf path'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _endpoint,
          decoration: const InputDecoration(labelText: 'Endpoint URL'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _alias,
          decoration: const InputDecoration(labelText: 'Model alias'),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: GoldOutlinedButton(
                label: 'Save',
                onPressed: () async {
                  await LlmLauncher.instance.setPaths(
                    serverPath: _serverPath.text.trim(),
                    modelPath: _modelPath.text.trim(),
                  );
                  await LlmConfig.save(
                    endpoint: _endpoint.text.trim(),
                    modelAlias: _alias.text.trim(),
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Saved')),
                    );
                  }
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GoldButton(
                label: 'Start server',
                icon: Icons.play_arrow,
                onPressed: () async {
                  final ok = await LlmLauncher.instance.ensureRunning();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(ok ? 'Server is up' : 'Could not start'),
                      ),
                    );
                  }
                },
                expanded: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: GoldOutlinedButton(
                label: 'Stop server',
                icon: Icons.stop_circle_outlined,
                onPressed: () async {
                  await LlmLauncher.instance.stop();
                  // Also kill any orphaned llama-server.exe we may not own
                  // (e.g. left over from a previous crash). Windows only.
                  if (Platform.isWindows) {
                    try {
                      await Process.run(
                        'taskkill',
                        ['/F', '/IM', 'llama-server.exe'],
                      );
                    } catch (_) {}
                  }
                  await _poll();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Server stopped')),
                    );
                  }
                },
              ),
            ),
          ],
        ),
        const GoldDiamondDivider(),

        _section(context, 'Data'),
        Row(
          children: [
            Expanded(
              child: GoldOutlinedButton(
                label: 'Export vocabulary as JSON',
                icon: Icons.ios_share,
                onPressed: _exportJson,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: GoldOutlinedButton(
                label: 'Merge duplicate words',
                icon: Icons.merge_type,
                onPressed: _mergeDuplicates,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: GoldOutlinedButton(
                label: 'Delete all learning words',
                icon: Icons.delete_sweep_outlined,
                onPressed: _confirmDeleteLearning,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: GoldOutlinedButton(
                label: 'Delete all reinforced words',
                icon: Icons.delete_sweep_outlined,
                onPressed: _confirmDeleteReinforced,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _section(BuildContext c, String label) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 8),
        child: Text(
          label.toUpperCase(),
          style: GoogleFonts.inter(
            color: AppColors.antiqueGold,
            fontWeight: FontWeight.w700,
            fontSize: 11,
            letterSpacing: 2.0,
          ),
        ),
      );
}

class _Tile extends StatelessWidget {
  const _Tile({required this.title, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.hairline(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    color: AppColors.ink(context),
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: GoogleFonts.inter(
                      color: AppColors.mutedInk(context),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
