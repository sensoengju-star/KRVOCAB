import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/grammar_topic.dart';
import '../providers/grammar_provider.dart';
import '../services/llm_launcher.dart';
import '../services/llm_service.dart';
import '../theme/app_colors.dart';
import '../widgets/gold_button.dart';
import '../widgets/mugunghwa_spinner.dart';

/// "Grammar" tab — ask the model to explain a grammar point, review the
/// generated template, and save it only if you approve. Saved topics are
/// editable and persisted.
class GrammarScreen extends ConsumerStatefulWidget {
  const GrammarScreen({super.key});

  @override
  ConsumerState<GrammarScreen> createState() => _GrammarScreenState();
}

class _GrammarScreenState extends ConsumerState<GrammarScreen> {
  final _prompt = TextEditingController();

  bool _loading = false;
  bool _startingServer = false;
  String? _error;

  /// The generated-but-not-yet-saved topic awaiting approval.
  ({String title, String body})? _draft;

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final prompt = _prompt.text.trim();
    if (prompt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Type a grammar point to explain')),
      );
      return;
    }

    setState(() {
      _loading = true;
      _startingServer = false;
      _error = null;
      _draft = null;
    });

    if (!await LlmLauncher.instance.isHealthy()) {
      if (!mounted) return;
      setState(() => _startingServer = true);
      final ok = await LlmLauncher.instance.ensureRunning();
      if (!mounted) return;
      setState(() => _startingServer = false);
      if (!ok) {
        setState(() {
          _loading = false;
          _error = LlmLauncher.instance.lastError ??
              'The model server is still starting. Try again in a moment.';
        });
        return;
      }
    }

    try {
      final result = await LlmService.instance.generateGrammar(prompt);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _draft = result;
      });
    } on LlmException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not reach the model server. Is llama-server running?';
      });
    }
  }

  Future<void> _saveDraft() async {
    final draft = _draft;
    if (draft == null) return;
    await ref.read(grammarProvider.notifier).add(
          GrammarTopic(
            id: 'g-${DateTime.now().millisecondsSinceEpoch}',
            title: draft.title,
            body: draft.body,
            dateAdded: DateTime.now(),
          ),
        );
    if (!mounted) return;
    setState(() {
      _draft = null;
      _prompt.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved to your grammar notes')),
    );
  }

  void _discardDraft() => setState(() => _draft = null);

  void _edit(GrammarTopic topic) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditGrammarSheet(topic: topic),
    );
  }

  void _addManual() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _EditGrammarSheet(),
    );
  }

  Future<void> _delete(GrammarTopic topic) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${topic.title}"?',
            style: GoogleFonts.playfairDisplay(fontSize: 18)),
        content: Text('This removes the saved grammar note.',
            style: GoogleFonts.inter(fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete',
                  style: TextStyle(color: AppColors.softRed))),
        ],
      ),
    );
    if (ok == true) await ref.read(grammarProvider.notifier).delete(topic.id);
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(grammarProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 100),
      children: [
        Text(
          'Ask about grammar',
          style: GoogleFonts.playfairDisplay(
            color: AppColors.ink(context),
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Describe a grammar point and the model writes a clean explanation. '
          'Review it, then save if you like it.',
          style: GoogleFonts.inter(
            color: AppColors.mutedInk(context),
            fontSize: 13,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _prompt,
          minLines: 1,
          maxLines: 3,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _loading ? null : _generate(),
          decoration: const InputDecoration(
            hintText: 'e.g. ~(으)면, the difference between 은/는 and 이/가…',
          ),
        ),
        const SizedBox(height: 12),
        GoldButton(
          label: _loading ? 'Thinking…' : 'Explain',
          icon: Icons.auto_awesome,
          onPressed: _loading ? null : _generate,
          expanded: true,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: GoldOutlinedButton(
                label: 'Add manually',
                icon: Icons.edit_note,
                onPressed: _addManual,
              ),
            ),
          ],
        ),
        if (_loading) ...[
          const SizedBox(height: 20),
          Center(
            child: Column(
              children: [
                const MugunghwaSpinner(size: 48),
                const SizedBox(height: 10),
                Text(
                  _startingServer
                      ? 'starting the model server…'
                      : 'writing the explanation…',
                  style: const TextStyle(
                    color: AppColors.antiqueGold,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 16),
          _ErrorCard(message: _error!, onRetry: _generate),
        ],
        if (_draft != null) ...[
          const SizedBox(height: 20),
          _DraftCard(
            title: _draft!.title,
            body: _draft!.body,
            onSave: _saveDraft,
            onDiscard: _discardDraft,
            onRegenerate: _loading ? null : _generate,
          ),
        ],
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Text(
                'Saved topics',
                style: GoogleFonts.inter(
                  color: AppColors.antiqueGold,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  letterSpacing: 2.0,
                ),
              ),
            ),
            Text(
              '${saved.length}',
              style: GoogleFonts.inter(
                color: AppColors.mutedInk(context),
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (saved.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(
              'No saved grammar notes yet.',
              style: GoogleFonts.inter(
                color: AppColors.mutedInk(context),
                fontStyle: FontStyle.italic,
              ),
            ),
          )
        else
          for (final t in saved)
            _SavedTopicCard(
              topic: t,
              onEdit: () => _edit(t),
              onDelete: () => _delete(t),
            ),
      ],
    );
  }
}

/// Renders the Markdown-ish [body] template: ## section headers, - bullets,
/// and paragraphs. Korean renders via Noto Serif KR.
class GrammarBody extends StatelessWidget {
  const GrammarBody({super.key, required this.body});
  final String body;

  String _strip(String s) => s.replaceAll('**', '').trim();

  @override
  Widget build(BuildContext context) {
    final lines = body.split('\n');
    final children = <Widget>[];

    for (final raw in lines) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        children.add(const SizedBox(height: 8));
        continue;
      }
      if (line.startsWith('## ') || line.startsWith('# ')) {
        final text = _strip(line.replaceFirst(RegExp(r'^#+\s*'), ''));
        children.add(Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 4),
          child: Text(
            text.toUpperCase(),
            style: GoogleFonts.inter(
              color: AppColors.antiqueGold,
              fontWeight: FontWeight.w700,
              fontSize: 11,
              letterSpacing: 1.6,
            ),
          ),
        ));
      } else if (line.trimLeft().startsWith('- ') ||
          line.trimLeft().startsWith('* ')) {
        final text = _strip(line.trimLeft().substring(2));
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('•  ',
                  style: GoogleFonts.notoSerifKr(
                    color: AppColors.deepGold,
                    fontSize: 15,
                    height: 1.45,
                  )),
              Expanded(
                child: Text(
                  text,
                  style: GoogleFonts.notoSerifKr(
                    color: AppColors.ink(context),
                    fontSize: 15,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ));
      } else {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            _strip(line),
            style: GoogleFonts.notoSerifKr(
              color: AppColors.ink(context),
              fontSize: 15,
              height: 1.5,
            ),
          ),
        ));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

class _DraftCard extends StatelessWidget {
  const _DraftCard({
    required this.title,
    required this.body,
    required this.onSave,
    required this.onDiscard,
    required this.onRegenerate,
  });

  final String title;
  final String body;
  final VoidCallback onSave;
  final VoidCallback onDiscard;
  final VoidCallback? onRegenerate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.champagne.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.antiqueGold),
        boxShadow: const [AppColors.warmShadow],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.drafts_outlined,
                  size: 16, color: AppColors.deepGold),
              const SizedBox(width: 6),
              Text(
                'DRAFT · REVIEW & SAVE',
                style: GoogleFonts.inter(
                  color: AppColors.deepGold,
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                  letterSpacing: 1.6,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: GoogleFonts.playfairDisplay(
              color: AppColors.ink(context),
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          GrammarBody(body: body),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: GoldButton(
                  label: 'Save',
                  icon: Icons.check,
                  onPressed: onSave,
                  expanded: true,
                ),
              ),
              const SizedBox(width: 10),
              GoldOutlinedButton(
                label: 'Redo',
                icon: Icons.refresh,
                onPressed: onRegenerate,
              ),
              const SizedBox(width: 10),
              GoldOutlinedButton(
                label: 'Discard',
                onPressed: onDiscard,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SavedTopicCard extends StatefulWidget {
  const _SavedTopicCard({
    required this.topic,
    required this.onEdit,
    required this.onDelete,
  });
  final GrammarTopic topic;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  State<_SavedTopicCard> createState() => _SavedTopicCardState();
}

class _SavedTopicCardState extends State<_SavedTopicCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.topic.title,
                      style: GoogleFonts.playfairDisplay(
                        color: AppColors.ink(context),
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    _open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: AppColors.antiqueGold,
                  ),
                ],
              ),
            ),
          ),
          if (_open) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: GrammarBody(body: widget.topic.body),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: widget.onEdit,
                    icon: const Icon(Icons.edit_outlined,
                        size: 16, color: AppColors.deepGold),
                    label: const Text('Edit',
                        style: TextStyle(color: AppColors.deepGold)),
                  ),
                  TextButton.icon(
                    onPressed: widget.onDelete,
                    icon: const Icon(Icons.delete_outline,
                        size: 16, color: AppColors.softRed),
                    label: const Text('Delete',
                        style: TextStyle(color: AppColors.softRed)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Starter skeleton shown when adding a grammar note by hand, so manual
/// entries follow the same clean template the model uses.
const _grammarTemplate = '## In short\n\n\n'
    '## How to form it\n- \n\n'
    '## Examples\n- 한국어 예문  —  English translation\n\n'
    '## Notes\n- ';

class _EditGrammarSheet extends ConsumerStatefulWidget {
  const _EditGrammarSheet({this.topic});

  /// null = create a new note; otherwise edit this one.
  final GrammarTopic? topic;

  @override
  ConsumerState<_EditGrammarSheet> createState() => _EditGrammarSheetState();
}

class _EditGrammarSheetState extends ConsumerState<_EditGrammarSheet> {
  late final TextEditingController _title =
      TextEditingController(text: widget.topic?.title ?? '');
  late final TextEditingController _body = TextEditingController(
      text: widget.topic?.body ?? _grammarTemplate);
  bool _saving = false;

  bool get _isNew => widget.topic == null;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final title = _title.text.trim();
    final body = _body.text.trim();
    if (title.isEmpty || body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Title and body cannot be empty')),
      );
      return;
    }
    setState(() => _saving = true);
    final notifier = ref.read(grammarProvider.notifier);
    final existing = widget.topic;
    if (existing == null) {
      await notifier.add(GrammarTopic(
        id: 'g-${DateTime.now().millisecondsSinceEpoch}',
        title: title,
        body: body,
        dateAdded: DateTime.now(),
      ));
    } else {
      await notifier.update(existing.copyWith(title: title, body: body));
    }
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: AppColors.hairline(context)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.champagne,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(_isNew ? 'New grammar note' : 'Edit grammar note',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 22,
                    color: AppColors.ink(context),
                    fontWeight: FontWeight.w600,
                  )),
              const SizedBox(height: 16),
              TextField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _body,
                minLines: 6,
                maxLines: 20,
                style: GoogleFonts.notoSerifKr(fontSize: 14, height: 1.4),
                decoration: const InputDecoration(
                  labelText: 'Body (Markdown: ## sections, - bullets)',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 20),
              GoldButton(
                label: _saving ? 'Saving…' : 'Save changes',
                onPressed: _saving ? null : _save,
                expanded: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.champagne.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.antiqueGold),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline, color: AppColors.deepGold),
              SizedBox(width: 8),
              Text('Hmm — the garden is quiet',
                  style: TextStyle(
                    color: AppColors.deepGold,
                    fontWeight: FontWeight.w600,
                  )),
            ],
          ),
          const SizedBox(height: 8),
          Text(message, style: GoogleFonts.inter(fontSize: 13)),
          const SizedBox(height: 12),
          GoldOutlinedButton(label: 'Try again', onPressed: onRetry),
        ],
      ),
    );
  }
}
