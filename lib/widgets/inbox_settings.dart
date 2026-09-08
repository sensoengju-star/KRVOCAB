import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/vocab_word.dart';
import '../providers/vocab_provider.dart';
import '../services/claude_service.dart';
import '../services/inbox_service.dart';
import '../theme/app_colors.dart';
import 'gold_button.dart';

/// Settings for the phone inbox: the folder to watch, the key used to define
/// what turns up in it, and a way to pull it in on demand.
///
/// The phone's job is deliberately tiny — type words, save the file. Every
/// other step happens here, where it can be written once and tested, rather
/// than assembled by hand in the Shortcuts app.
class InboxSettings extends ConsumerStatefulWidget {
  const InboxSettings({super.key});

  @override
  ConsumerState<InboxSettings> createState() => _InboxSettingsState();
}

class _InboxSettingsState extends ConsumerState<InboxSettings> {
  final _folder = TextEditingController();
  final _key = TextEditingController();

  String _model = ClaudeService.defaultModel;
  WordStatus _status = WordStatus.learning;

  bool _loading = true;
  bool _obscure = true;
  bool _importing = false;
  bool _testing = false;
  String? _testResult;
  bool _testOk = false;
  InboxResult? _last;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final folder = await InboxService.instance.folder();
    final status = await InboxService.instance.defaultStatus();
    final key = await ClaudeService.instance.apiKey();
    final model = await ClaudeService.instance.model();
    if (!mounted) return;
    setState(() {
      _folder.text = folder ?? '';
      _key.text = key ?? '';
      _model = ClaudeService.models.containsKey(model)
          ? model
          : ClaudeService.defaultModel;
      _status = status;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _folder.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final path = _folder.text.trim();
    if (path.isEmpty) {
      await InboxService.instance.clearFolder();
    } else {
      await InboxService.instance.setFolder(path);
    }
    await InboxService.instance.setDefaultStatus(_status);
    await ClaudeService.instance.save(apiKey: _key.text, model: _model);
  }

  Future<void> _saveAndTell() async {
    await _save();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved'), duration: Duration(seconds: 2)),
    );
  }

  /// One word, one round trip — proves the key, the model and the network in
  /// about a second, without touching the collection.
  Future<void> _test() async {
    await _save();
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final answer = await ClaudeService.instance.test();
      if (!mounted) return;
      setState(() {
        _testOk = true;
        _testResult = answer;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testOk = false;
        _testResult = e is ClaudeException ? e.message : '$e';
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
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
          _label(context, 'Synced folder'),
          _hint(
            context,
            'Words you save from your phone are read from here at launch and '
            'whenever this window comes back into focus. A file is moved to a '
            'processed subfolder once imported, never deleted.',
          ),
          const SizedBox(height: 10),
          _field(context, _folder, hint: InboxService.defaultFolder),

          const SizedBox(height: 18),
          _label(context, 'API key'),
          _hint(
            context,
            'A file from the phone is just a list of words. Claude fills in the '
            'reading, meaning, part of speech and 해요체 form on import. The key '
            'is stored on this machine only — never in the project.',
          ),
          const SizedBox(height: 10),
          _field(
            context,
            _key,
            hint: 'sk-ant-…',
            obscure: _obscure,
            trailing: IconButton(
              tooltip: _obscure ? 'Show' : 'Hide',
              icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                  size: 17, color: AppColors.mutedInk(context)),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _model,
                  isDense: true,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: AppColors.hairline(context)),
                    ),
                  ),
                  style: GoogleFonts.inter(
                      fontSize: 12.5, color: AppColors.ink(context)),
                  items: [
                    for (final e in ClaudeService.models.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) =>
                      setState(() => _model = v ?? ClaudeService.defaultModel),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: _testing ? null : _test,
                icon: _testing
                    ? const SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.bolt_outlined, size: 16),
                label: Text('Test',
                    style: GoogleFonts.inter(
                        fontSize: 12.5, fontWeight: FontWeight.w600)),
                style: TextButton.styleFrom(
                    foregroundColor: AppColors.antiqueGold),
              ),
            ],
          ),
          if (_testResult != null) ...[
            const SizedBox(height: 8),
            _Banner(
              ok: _testOk,
              text: _testOk ? 'Working — ${_testResult!}' : _testResult!,
            ),
          ],

          const SizedBox(height: 18),
          _label(context, 'Words arrive as'),
          _hint(
            context,
            'A plain list from the phone carries no status, so it takes this '
            'one. You can move a word to the other pile any time.',
          ),
          const SizedBox(height: 8),
          SegmentedButton<WordStatus>(
            segments: [
              ButtonSegment(
                value: WordStatus.learning,
                label: Text('Learning',
                    style: GoogleFonts.inter(fontSize: 12.5)),
              ),
              ButtonSegment(
                value: WordStatus.reinforcement,
                label: Text('Reinforced',
                    style: GoogleFonts.inter(fontSize: 12.5)),
              ),
            ],
            selected: {_status},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _status = s.first),
          ),

          const SizedBox(height: 16),
          Row(
            children: [
              GoldButton(
                label: _importing ? 'Importing…' : 'Import now',
                icon: Icons.download_outlined,
                onPressed: _importing ? null : _importNow,
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _saveAndTell,
                style: TextButton.styleFrom(
                    foregroundColor: AppColors.antiqueGold),
                child: Text('Save',
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

  Widget _label(BuildContext context, String text) => Text(
        text,
        style: GoogleFonts.inter(
          color: AppColors.ink(context),
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      );

  Widget _hint(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Text(
          text,
          style: GoogleFonts.inter(
            color: AppColors.mutedInk(context),
            fontSize: 12,
            height: 1.5,
          ),
        ),
      );

  Widget _field(
    BuildContext context,
    TextEditingController controller, {
    required String hint,
    bool obscure = false,
    Widget? trailing,
  }) =>
      TextField(
        controller: controller,
        obscureText: obscure,
        style: GoogleFonts.inter(fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          hintStyle: GoogleFonts.inter(
            color: AppColors.mutedInk(context),
            fontSize: 13,
          ),
          suffixIcon: trailing,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppColors.hairline(context)),
          ),
        ),
        onSubmitted: (_) => _saveAndTell(),
      );
}

class _Banner extends StatelessWidget {
  const _Banner({required this.ok, required this.text});
  final bool ok;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
      decoration: BoxDecoration(
        color: ok ? AppColors.goldTint(context) : AppColors.inset(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: ok
              ? AppColors.antiqueGold.withValues(alpha: 0.3)
              : AppColors.vermilion.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ok ? Icons.check_circle_outline : Icons.error_outline,
            size: 15,
            color: ok ? AppColors.antiqueGold : AppColors.vermilion,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                color: AppColors.ink(context),
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Banner(ok: !bad, text: result.summary),
        // The specific reason matters here — "folder not found" and "that file
        // is still syncing" need very different responses.
        for (final e in result.errors)
          Padding(
            padding: const EdgeInsets.only(top: 5, left: 8),
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
    );
  }
}
