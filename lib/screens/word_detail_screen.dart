import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../models/vocab_word.dart';
import '../models/word_detail.dart';
import '../providers/vocab_provider.dart';
import '../services/llm_launcher.dart';
import '../services/llm_service.dart';
import '../services/storage_service.dart';
import '../services/tts_service.dart';
import '../theme/app_colors.dart';
import '../widgets/gold_button.dart';
import '../widgets/mugunghwa_spinner.dart';

/// Dedicated page for one vocabulary word — 뜻풀이, 쓰임, 관련 어휘 and 예문,
/// all explained in Korean. Reached by tapping a word in the Vocabulary list.
///
/// The page is generated once by the local model and then cached in Hive, so
/// coming back to a word is instant and works with the server offline.
class WordDetailScreen extends ConsumerStatefulWidget {
  const WordDetailScreen({super.key, required this.wordId});

  /// Looked up live from [vocabProvider] so edits made elsewhere (or from the
  /// status button on this page) are reflected immediately.
  final String wordId;

  @override
  ConsumerState<WordDetailScreen> createState() => _WordDetailScreenState();
}

class _WordDetailScreenState extends ConsumerState<WordDetailScreen> {
  WordDetail? _detail;
  bool _loading = false;
  bool _startingServer = false;
  String? _error;

  /// Invalidates an in-flight generation when the user hits Regenerate again
  /// (or leaves and the widget is disposed).
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _detail = StorageService.instance.wordDetail(widget.wordId);
    if (_detail == null) {
      // The user tapped the word to read about it — start writing the page
      // straight away rather than making them press a button first.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _generate();
      });
    }
  }

  VocabWord? get _word {
    for (final w in ref.read(vocabProvider)) {
      if (w.id == widget.wordId) return w;
    }
    return null;
  }

  Future<void> _generate() async {
    final word = _word;
    if (word == null || _loading) return;

    final myId = ++_requestId;
    setState(() {
      _loading = true;
      _startingServer = false;
      _error = null;
    });

    // Wake the local model server if it isn't up yet — on a cold app launch
    // this is the difference between a page and a SocketException.
    if (!await LlmLauncher.instance.isHealthy()) {
      if (!mounted || myId != _requestId) return;
      setState(() => _startingServer = true);
      final ok = await LlmLauncher.instance.ensureRunning();
      if (!mounted || myId != _requestId) return;
      setState(() => _startingServer = false);
      if (!ok) {
        setState(() {
          _loading = false;
          _error = LlmLauncher.instance.lastError ??
              'The model server is still starting. Give it a moment and try '
                  'again.';
        });
        return;
      }
    }

    try {
      final detail = await LlmService.instance.generateWordDetail(
        hangul: word.hangul,
        englishMeaning: word.englishMeaning,
        partOfSpeech: word.partOfSpeech,
      );
      if (!mounted || myId != _requestId) return;
      await StorageService.instance.putWordDetail(word.id, detail);
      if (!mounted || myId != _requestId) return;
      setState(() {
        _loading = false;
        _detail = detail;
      });
    } on LlmException catch (e) {
      if (!mounted || myId != _requestId) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (err) {
      if (!mounted || myId != _requestId) return;
      final msg = err.toString();
      setState(() {
        _loading = false;
        _error = msg.contains('TimeoutException')
            ? 'The model took too long — try again.'
            : 'Could not reach the model server. Is llama-server running?';
      });
    }
  }

  String _shareText(VocabWord word) {
    final d = _detail;
    final buf = StringBuffer()..writeln(word.hangul);
    if (word.romanization.trim().isNotEmpty) {
      buf.writeln(word.romanization.trim());
    }
    if (word.englishMeaning.trim().isNotEmpty) {
      buf.writeln(word.englishMeaning.trim());
    }
    if (word.politeForm.trim().isNotEmpty) {
      buf.writeln('해요체: ${word.politeForm.trim()}');
    }
    if (d != null) {
      if (d.definitionKo.isNotEmpty) {
        buf..writeln()..writeln('[뜻풀이]')..writeln(d.definitionKo);
      }
      if (d.nuanceKo.isNotEmpty) {
        buf..writeln()..writeln('[쓰임 · 뉘앙스]')..writeln(d.nuanceKo);
      }
      if (d.related.isNotEmpty) {
        buf..writeln()..writeln('[관련 어휘]');
        for (final r in d.related) {
          buf.writeln('· ${r.word} — ${r.noteKo}');
        }
      }
      if (d.examples.isNotEmpty) {
        buf..writeln()..writeln('[예문]');
        for (var i = 0; i < d.examples.length; i++) {
          final e = d.examples[i];
          buf.writeln('${i + 1}. ${e.korean}');
          if (e.english.isNotEmpty) buf.writeln('   ${e.english}');
          if (e.explanationKo.isNotEmpty) buf.writeln('   ${e.explanationKo}');
        }
      }
    }
    return buf.toString().trimRight();
  }

  Future<void> _confirmRegenerate() async {
    if (_detail == null) {
      await _generate();
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Write this page again?',
            style: GoogleFonts.playfairDisplay(fontSize: 18)),
        content: Text(
          'The saved explanation and examples will be replaced by a new one.',
          style: GoogleFonts.inter(fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Regenerate')),
        ],
      ),
    );
    if (ok == true) await _generate();
  }

  @override
  Widget build(BuildContext context) {
    // Watch so edits / status changes elsewhere repaint this page.
    final words = ref.watch(vocabProvider);
    VocabWord? found;
    for (final w in words) {
      if (w.id == widget.wordId) {
        found = w;
        break;
      }
    }

    if (found == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Word')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              'This word is no longer in your collection.',
              textAlign: TextAlign.center,
              style: GoogleFonts.playfairDisplay(
                color: AppColors.mutedInk(context),
                fontSize: 18,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ),
      );
    }

    // Captured as a final local so the callbacks below don't need `!`.
    final word = found;
    final d = _detail;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          word.hangul,
          style: GoogleFonts.notoSerifKr(
            color: AppColors.ivory,
            fontSize: 20,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Copy this page',
            icon: const Icon(Icons.copy_outlined, size: 20),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _shareText(word)));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied to clipboard')),
                );
              }
            },
          ),
          IconButton(
            tooltip: 'Share this page',
            icon: const Icon(Icons.ios_share, size: 20),
            onPressed: () => Share.share(
              _shareText(word),
              subject: 'Maldari — ${word.hangul}',
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.pageGradient(context)),
        child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          _WordHeaderCard(
            word: word,
            onCycleStatus: () =>
                ref.read(vocabProvider.notifier).cycleStatus(word.id),
          ),
          const SizedBox(height: 18),
          if (_loading) _LoadingBlock(startingServer: _startingServer),
          if (_error != null) ...[
            _ErrorCard(message: _error!, onRetry: _generate),
            const SizedBox(height: 16),
          ],
          if (d != null) ...[
            // The Korean definition is the reason this page exists, so it
            // gets its own treatment rather than being one prose card among
            // several equals.
            if (d.definitionKo.isNotEmpty) ...[
              _DefinitionCard(text: d.definitionKo),
              const SizedBox(height: 24),
            ],
            if (d.nuanceKo.isNotEmpty) ...[
              const _SectionLabel(
                korean: '쓰임 · 뉘앙스',
                english: 'How it is used',
                color: AppColors.jade,
              ),
              _ProseCard(text: d.nuanceKo),
              const SizedBox(height: 16),
            ],
            if (d.related.isNotEmpty) ...[
              const _SectionLabel(
                korean: '관련 어휘',
                english: 'Related vocabulary',
                color: AppColors.indigo,
              ),
              for (final r in d.related) _RelatedRow(related: r),
              const SizedBox(height: 16),
            ],
            if (d.examples.isNotEmpty) ...[
              _SectionLabel(
                korean: '예문',
                english: 'Examples · ${d.examples.length}',
                color: AppColors.plum,
              ),
              for (final e in d.examples)
                _DetailExampleCard(example: e, target: word.hangul),
            ],
            const SizedBox(height: 20),
            Center(
              child: Text(
                'written ${_formatDate(d.generatedAt)} by your local model',
                style: GoogleFonts.inter(
                  color: AppColors.mutedInk(context),
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (!_loading)
            Center(
              child: GoldOutlinedButton(
                label: d == null ? 'Write this page' : 'Write it again',
                icon: d == null ? Icons.auto_awesome : Icons.refresh,
                onPressed: d == null ? _generate : _confirmRegenerate,
              ),
            ),
        ],
        ),
      ),
    );
  }
}

String _formatDate(DateTime d) {
  final local = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)}';
}

/// The word itself: Hangul, romanization, 해요체, English gloss, part of
/// speech and its learning status.
class _WordHeaderCard extends StatelessWidget {
  const _WordHeaderCard({required this.word, required this.onCycleStatus});

  final VocabWord word;
  final VoidCallback onCycleStatus;

  @override
  Widget build(BuildContext context) {
    final status = _statusColor(word.status);
    final pos = AppColors.forPartOfSpeech(word.partOfSpeech);

    // Gold on black: the word gets a dark hero panel, and everything factual
    // about it (reading, 해요체, part of speech, status) sits in one strip
    // beneath — rather than being spread down the left edge as before.
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 22, 12, 18),
      decoration: BoxDecoration(
        gradient: AppColors.chromeGradient,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.onyxEdge),
        boxShadow: AppColors.floatShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Tapping the headword speaks the dictionary form; the
                    // speaker button beside it speaks what you'd actually
                    // say (the 해요체 form, when the word has one).
                    InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.xs),
                      onTap: () => TtsService.instance.speak(word.hangul),
                      child: Text(
                        word.hangul,
                        style: GoogleFonts.notoSerifKr(
                          color: AppColors.lightGold,
                          fontSize: 40,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                    ),
                    if (word.romanization.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        word.romanization,
                        style: GoogleFonts.inter(
                          color: AppColors.antiqueGold,
                          fontStyle: FontStyle.italic,
                          fontSize: 15,
                        ),
                      ),
                    ],
                    // The polite form sits directly under the headword at
                    // near-equal scale rather than shrunk into the chip strip
                    // below — it's the form the learner actually speaks.
                    if (word.politeForm.trim().isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '해요체',
                            style: GoogleFonts.inter(
                              color: AppColors.cream.withValues(alpha: 0.55),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.6,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              word.politeForm.trim(),
                              style: GoogleFonts.notoSerifKr(
                                color: AppColors.champagne,
                                fontSize: 30,
                                fontWeight: FontWeight.w600,
                                height: 1.25,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                    ],
                    if (word.englishMeaning.trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _HeroGloss(text: word.englishMeaning),
                    ],
                  ],
                ),
              ),
              Tooltip(
                message: '발음 듣기',
                child: IconButton(
                  icon: const Icon(Icons.volume_up_outlined,
                      color: AppColors.lightGold),
                  onPressed: () => TtsService.instance.speakWord(word),
                ),
              ),
              Tooltip(
                message: _statusTooltip(word.status),
                child: IconButton(
                  icon: Icon(_statusIcon(word.status), color: status),
                  onPressed: onCycleStatus,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: AppColors.onyxEdge, height: 1),
          const SizedBox(height: 12),
          // Facts strip.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Pill(label: PartsOfSpeech.label(word.partOfSpeech), color: pos),
              _Pill(label: _statusLabel(word.status), color: status),
            ],
          ),
        ],
      ),
    );
  }
}

/// Two states only: reinforced, or learning (which absorbs the retired
/// `learned` status still present in older data).
bool _isReinforced(WordStatus s) => s == WordStatus.reinforcement;

/// The word's English meaning on the hero panel — hidden behind a tap so the
/// Korean 뜻풀이 below is what you read first.
class _HeroGloss extends StatefulWidget {
  const _HeroGloss({required this.text});
  final String text;

  @override
  State<_HeroGloss> createState() => _HeroGlossState();
}

class _HeroGlossState extends State<_HeroGloss> {
  bool _shown = false;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.xs),
          onTap: () => setState(() => _shown = !_shown),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: _shown
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.visibility_off_outlined,
                            size: 15,
                            color: AppColors.cream.withValues(alpha: 0.55)),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            widget.text,
                            style: GoogleFonts.inter(
                              color: AppColors.cream,
                              fontSize: 15,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.visibility_outlined,
                            size: 15,
                            color: AppColors.cream.withValues(alpha: 0.55)),
                        const SizedBox(width: 8),
                        Text(
                          '영어 뜻 보기',
                          style: GoogleFonts.notoSerifKr(
                            color: AppColors.cream.withValues(alpha: 0.7),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

String _statusLabel(WordStatus s) =>
    _isReinforced(s) ? 'reinforced' : 'learning';

Color _statusColor(WordStatus s) => _isReinforced(s)
    ? AppColors.statusReinforcement
    : AppColors.statusLearning;

IconData _statusIcon(WordStatus s) =>
    _isReinforced(s) ? Icons.autorenew : Icons.add_task;

String _statusTooltip(WordStatus s) => _isReinforced(s)
    ? 'Reinforced — tap to move back to Learning'
    : 'Learning — tap to mark Reinforced';

/// Fact chip on the dark hero panel.
class _Pill extends StatelessWidget {
  const _Pill({required this.label, this.color});
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.antiqueGold;
    // Accents are mixed toward cream so they stay legible on near-black.
    final fg = Color.lerp(c, AppColors.cream, 0.28)!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: fg,
          fontSize: 10,
          letterSpacing: 0.6,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Korean section heading with a small English hint beside it.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.korean,
    required this.english,
    this.color = AppColors.deepGold,
  });
  final String korean;
  final String english;

  /// Each section carries its own accent so the page has landmarks you can
  /// scroll to by colour.
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Container(
            width: 4,
            height: 15,
            margin: const EdgeInsets.only(right: 9),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Text(
            korean,
            style: GoogleFonts.notoSerifKr(
              color: AppColors.onSurfaceAccent(context, color),
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              english.toUpperCase(),
              style: GoogleFonts.inter(
                color: AppColors.mutedInk(context),
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The Korean definition — the page's headline content.
///
/// Deliberately louder than every other block: a gold-washed surface, a gold
/// border, its own header inside the card, and body type several steps up
/// from the prose cards below it.
class _DefinitionCard extends StatelessWidget {
  const _DefinitionCard({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.goldTint(context),
            AppColors.surface(context),
          ],
          stops: const [0, 0.85],
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: AppColors.antiqueGold.withValues(alpha: 0.55),
          width: 1.4,
        ),
        boxShadow: AppColors.cardShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 4,
                height: 20,
                decoration: BoxDecoration(
                  gradient: AppColors.goldGradient,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '뜻풀이',
                style: GoogleFonts.notoSerifKr(
                  color: AppColors.deepGold,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'MEANING · IN KOREAN',
                  style: GoogleFonts.inter(
                    color: AppColors.mutedInk(context),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            text,
            style: GoogleFonts.notoSerifKr(
              color: AppColors.ink(context),
              fontSize: 19,
              height: 1.75,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// A block of supporting Korean prose (the usage note). Flat and quiet by
/// design — the lift is reserved for [_DefinitionCard].
class _ProseCard extends StatelessWidget {
  const _ProseCard({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.hairline(context)),
      ),
      child: Text(
        text,
        style: GoogleFonts.notoSerifKr(
          color: AppColors.ink(context),
          fontSize: 15,
          height: 1.65,
        ),
      ),
    );
  }
}

class _RelatedRow extends StatelessWidget {
  const _RelatedRow({required this.related});
  final RelatedWord related;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.inset(context),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.hairline(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            related.word,
            style: GoogleFonts.notoSerifKr(
              color: AppColors.deepGold,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (related.noteKo.isNotEmpty) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                related.noteKo,
                style: GoogleFonts.notoSerifKr(
                  color: AppColors.ink(context),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ),
          ] else
            const Spacer(),
        ],
      ),
    );
  }
}

/// One example sentence: Korean (target word underlined), romanization,
/// English gloss, and the Korean explanation of the sentence.
class _DetailExampleCard extends StatefulWidget {
  const _DetailExampleCard({required this.example, required this.target});
  final DetailExample example;
  final String target;

  @override
  State<_DetailExampleCard> createState() => _DetailExampleCardState();
}

class _DetailExampleCardState extends State<_DetailExampleCard> {
  /// The English translation stays folded away until asked for — reading the
  /// Korean first is the point of this page.
  bool _showEnglish = false;

  DetailExample get example => widget.example;
  String get target => widget.target;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.hairline(context)),
        boxShadow: AppColors.cardShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _koreanWithHighlight(context),
          if (example.romanization.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              example.romanization,
              style: GoogleFonts.inter(
                color: AppColors.mutedInk(context),
                fontStyle: FontStyle.italic,
                fontSize: 13,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              if (example.english.isNotEmpty)
                _TranslationToggle(
                  expanded: _showEnglish,
                  onTap: () => setState(() => _showEnglish = !_showEnglish),
                ),
              const Spacer(),
              TonalIconButton(
                icon: Icons.volume_up_outlined,
                tooltip: '이 문장 듣기',
                color: AppColors.antiqueGold,
                size: 17,
                onPressed: () => TtsService.instance.speak(example.korean),
              ),
            ],
          ),
          if (example.english.isNotEmpty) ...[
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 180),
              sizeCurve: Curves.easeOutCubic,
              crossFadeState: _showEnglish
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  example.english,
                  style: GoogleFonts.inter(
                    color: AppColors.ink(context),
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
              ),
            ),
          ],
          if (example.explanationKo.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.champagne.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(12),
              ),
              // A left gold stripe as a sibling rather than a Border side —
              // a non-uniform Border and a borderRadius can't coexist in one
              // BoxDecoration.
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: 3,
                      decoration: const BoxDecoration(
                        color: AppColors.antiqueGold,
                        borderRadius: BorderRadius.horizontal(
                          left: Radius.circular(12),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '설명',
                              style: GoogleFonts.inter(
                                color: AppColors.deepGold,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.4,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              example.explanationKo,
                              style: GoogleFonts.notoSerifKr(
                                color: AppColors.ink(context),
                                fontSize: 14,
                                height: 1.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _koreanWithHighlight(BuildContext context) {
    final base = GoogleFonts.notoSerifKr(
      color: AppColors.ink(context),
      fontSize: 19,
      height: 1.5,
      fontWeight: FontWeight.w500,
    );

    // Try the word as written; a conjugated verb (가다 → 가요) only shares its
    // stem, so fall back to that before giving up on the underline.
    final needle = _needle();
    if (needle == null) return Text(example.korean, style: base);

    final spans = <TextSpan>[];
    var rest = example.korean;
    while (rest.isNotEmpty) {
      final idx = rest.indexOf(needle);
      if (idx == -1) {
        spans.add(TextSpan(text: rest));
        break;
      }
      if (idx > 0) spans.add(TextSpan(text: rest.substring(0, idx)));
      spans.add(TextSpan(
        text: needle,
        style: const TextStyle(
          decoration: TextDecoration.underline,
          decorationColor: AppColors.antiqueGold,
          decorationThickness: 2.2,
          color: AppColors.deepGold,
        ),
      ));
      rest = rest.substring(idx + needle.length);
    }
    return RichText(text: TextSpan(style: base, children: spans));
  }

  String? _needle() {
    final t = target.trim();
    if (t.isEmpty) return null;
    if (example.korean.contains(t)) return t;
    // Dictionary-form verb/adjective: drop the trailing 다 and match the stem.
    if (t.length > 2 && t.endsWith('다')) {
      final stem = t.substring(0, t.length - 1);
      if (example.korean.contains(stem)) return stem;
    }
    return null;
  }
}

/// "번역 보기 / 번역 숨기기" — the control that reveals an English line.
class _TranslationToggle extends StatelessWidget {
  const _TranslationToggle({required this.expanded, required this.onTap});
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.xs),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: const Icon(Icons.keyboard_arrow_down,
                      size: 17, color: AppColors.antiqueGold),
                ),
                const SizedBox(width: 5),
                Text(
                  expanded ? '번역 숨기기' : '번역 보기',
                  style: GoogleFonts.notoSerifKr(
                    color: AppColors.deepGold,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingBlock extends StatelessWidget {
  const _LoadingBlock({required this.startingServer});
  final bool startingServer;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          const MugunghwaSpinner(size: 52),
          const SizedBox(height: 12),
          Text(
            startingServer
                ? 'starting the model server…'
                : '한국어로 설명을 쓰는 중…',
            style: GoogleFonts.notoSerifKr(
              color: AppColors.antiqueGold,
              fontStyle: FontStyle.italic,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            startingServer
                ? 'this can take a minute on first launch'
                : 'writing the meaning, usage and examples',
            style: GoogleFonts.inter(
              color: AppColors.mutedInk(context),
              fontSize: 12,
            ),
          ),
        ],
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
