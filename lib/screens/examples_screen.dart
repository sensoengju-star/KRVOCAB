import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../models/vocab_word.dart';
import '../providers/vocab_provider.dart';
import '../services/llm_launcher.dart';
import '../services/llm_service.dart';
import '../services/story_store.dart';
import '../theme/app_colors.dart';
import '../widgets/gold_button.dart';
import '../widgets/story_card.dart';
import '../widgets/mugunghwa_spinner.dart';
import 'saved_stories_screen.dart';

/// "Stories" tab — generates several short Korean stories that weave in the
/// learner's vocabulary words. Replaces the old per-word example sentences.
class ExamplesScreen extends ConsumerStatefulWidget {
  const ExamplesScreen({super.key});

  @override
  ConsumerState<ExamplesScreen> createState() => _ExamplesScreenState();
}

class _ExamplesScreenState extends ConsumerState<ExamplesScreen> {
  StreamSubscription<String>? _sub;
  final StringBuffer _buffer = StringBuffer();
  bool _loading = false;
  bool _startingServer = false;
  String? _error;
  /// The batch on screen. Written to the library once the stream finishes,
  /// but kept visible here — the library is browsed on its own page.
  List<VocabStory> _stories = const [];

  /// How many stories are in the library — the library itself has its own
  /// page, this is just for the button's badge.
  int _savedCount = 0;
  int _storyCount = 5;

  @override
  void initState() {
    super.initState();
    _savedCount = StoryStore.instance.count;
    // The Review tab's "see examples" button still pushes a word here and
    // switches to this tab — treat that as a request to (re)generate stories.
    Future.microtask(() {
      if (!mounted) return;
      ref.listenManual<VocabWord?>(pendingExampleWordProvider, (_, next) {
        if (next == null) return;
        Future.microtask(
            () => ref.read(pendingExampleWordProvider.notifier).state = null);
        _generate();
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _generate() async {
    final words =
        ref.read(storyWordsProvider).map((w) => w.hangul).toList();
    if (words.isEmpty) return;

    _sub?.cancel();
    _buffer.clear();
    setState(() {
      _loading = true;
      _startingServer = false;
      _error = null;
      _stories = const [];
    });

    // Make sure the model server is up first. If it's still booting (e.g. the
    // app just launched), wait for it rather than failing immediately.
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
              'The model server is still starting. Give it a moment and try '
                  'again.';
        });
        return;
      }
    }

    void parseInto({required bool done}) {
      final list = LlmService.parsePartialArray(_buffer.toString(), 'stories');
      if (list.isEmpty) return;
      final parsed =
          list.map(VocabStory.fromJson).where((s) => s.isRenderable).toList();
      if (parsed.isNotEmpty || done) {
        setState(() => _stories = parsed);
      }
    }

    try {
      final stream = await LlmService.instance
          .generateStories(words, storyCount: _storyCount);
      _sub = stream.listen(
        (chunk) {
          _buffer.write(chunk);
          parseInto(done: false);
        },
        onError: (e) {
          setState(() {
            _loading = false;
            _error = e is LlmException ? e.message : 'Stream error.';
          });
        },
        onDone: () async {
          parseInto(done: true);
          // Save only once the stream has finished: a half-written story
          // parsed mid-flight shouldn't end up in the library. The batch
          // stays on screen here; the library is browsed on its own page.
          if (_stories.isNotEmpty) {
            await StoryStore.instance.addAll(_stories);
          }
          if (!mounted) return;
          setState(() {
            _loading = false;
            _savedCount = StoryStore.instance.count;
          });
        },
      );
    } on LlmException catch (e) {
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Could not reach the model server. Is llama-server running?';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final source = ref.watch(storySourceProvider);
    final storyWords = ref.watch(storyWordsProvider);
    final learningCount = ref.watch(learningGroupWordsProvider).length;
    final reinforcedCount = ref.watch(reinforcementGroupWordsProvider).length;

    final targets = {for (final w in storyWords) w.hangul.trim()};
    final glossary = {
      for (final w in storyWords) w.hangul.trim(): w.englishMeaning.trim(),
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      children: [
        Text(
          'Stories from your words',
          style: GoogleFonts.playfairDisplay(
            color: AppColors.ink(context),
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          storyWords.isEmpty
              ? 'Pick a source below, then add or mark some words in the '
                  'Vocabulary tab to weave stories from.'
              : 'Short TOPIK I–II stories woven from the ${storyWords.length} '
                  'word${storyWords.length == 1 ? '' : 's'} in your '
                  '${_sourceDescription(source)}.',
          style: GoogleFonts.inter(
            color: AppColors.mutedInk(context),
            fontSize: 13,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 14),
        _SourceSelector(
          source: source,
          learningCount: learningCount,
          reinforcedCount: reinforcedCount,
          onChanged: _loading
              ? null
              : (s) => ref.read(storySourceProvider.notifier).state = s,
        ),
        const SizedBox(height: 16),
        _StoryCountSelector(
          value: _storyCount,
          onChanged: _loading
              ? null
              : (v) => setState(() => _storyCount = v),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: GoldButton(
                label: _savedCount == 0 ? 'Generate Stories' : 'Write more',
                icon: Icons.auto_stories,
                onPressed: (_loading || storyWords.isEmpty) ? null : _generate,
                expanded: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        GoldOutlinedButton(
          label: _savedCount == 0
              ? 'Saved stories'
              : 'Saved stories  ·  $_savedCount',
          icon: Icons.bookmarks_outlined,
          onPressed: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SavedStoriesScreen()),
            );
            // The library page can delete stories — refresh the badge.
            if (mounted) {
              setState(() => _savedCount = StoryStore.instance.count);
            }
          },
        ),
        if (storyWords.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              _emptySourceMessage(source),
              style: GoogleFonts.inter(
                color: AppColors.mutedInk(context),
                fontSize: 12,
                fontStyle: FontStyle.italic,
                height: 1.4,
              ),
            ),
          ),
        if (_stories.isNotEmpty) ...[
          const SizedBox(height: 12),
          _ShareStoriesRow(stories: _stories),
        ],
        const SizedBox(height: 24),
        if (_loading && _stories.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Column(
                children: [
                  const MugunghwaSpinner(size: 56),
                  const SizedBox(height: 12),
                  Text(
                    _startingServer
                        ? 'starting the model server…'
                        : 'weaving your stories…',
                    style: const TextStyle(
                      color: AppColors.antiqueGold,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  if (_startingServer) ...[
                    const SizedBox(height: 4),
                    Text(
                      'this can take a minute on first launch',
                      style: GoogleFonts.inter(
                        color: AppColors.mutedInk(context),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        if (_error != null)
          _ErrorCard(message: _error!, onRetry: _generate),
        // Streaming batch first (it isn't in the library until it finishes),
        // then everything saved, newest first.
        for (final story in _stories)
          StoryCard(story: story, targets: targets, glossary: glossary),
        if (_loading && _stories.isNotEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: MugunghwaSpinner(size: 36)),
          ),
      ],
    );
  }
}

String _sourceDescription(StorySource s) => switch (s) {
      StorySource.both => 'Learning and Reinforced groups',
      StorySource.learning => 'Learning group',
      StorySource.reinforcement => 'Reinforced group',
    };

String _emptySourceMessage(StorySource s) => switch (s) {
      StorySource.both =>
        'No words yet — add some in the Vocabulary tab to weave stories from.',
      StorySource.learning =>
        'No learning words yet — add some in the Vocabulary tab.',
      StorySource.reinforcement =>
        'No reinforced words yet — tap the ↻ icon on a card in the Vocabulary '
            'tab to keep it in rotation.',
    };

/// Chooses which pool the stories are woven from. Both Learning and
/// Reinforced words are fair game — separately or together.
class _SourceSelector extends ConsumerWidget {
  const _SourceSelector({
    required this.source,
    required this.learningCount,
    required this.reinforcedCount,
    required this.onChanged,
  });

  final StorySource source;
  final int learningCount;
  final int reinforcedCount;
  final ValueChanged<StorySource>? onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.inset(context),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.hairline(context)),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(
            child: _SourceTab(
              label: 'Both',
              count: learningCount + reinforcedCount,
              color: AppColors.plum,
              active: source == StorySource.both,
              onTap: onChanged == null
                  ? null
                  : () => onChanged!(StorySource.both),
            ),
          ),
          Expanded(
            child: _SourceTab(
              label: 'Learning',
              count: learningCount,
              color: AppColors.statusLearning,
              active: source == StorySource.learning,
              onTap: onChanged == null
                  ? null
                  : () => onChanged!(StorySource.learning),
            ),
          ),
          Expanded(
            child: _SourceTab(
              label: 'Reinforced',
              count: reinforcedCount,
              color: AppColors.statusReinforcement,
              active: source == StorySource.reinforcement,
              onTap: onChanged == null
                  ? null
                  : () => onChanged!(StorySource.reinforcement),
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceTab extends StatelessWidget {
  const _SourceTab({
    required this.label,
    required this.count,
    required this.color,
    required this.active,
    required this.onTap,
  });

  final String label;
  final int count;
  final Color color;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.xs);
    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: radius,
            color: active ? AppColors.surface(context) : null,
            boxShadow: active
                ? const [
                    BoxShadow(
                      color: Color(0x1F2C2825),
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    color: active
                        ? AppColors.onSurfaceAccent(context, color)
                        : AppColors.mutedInk(context),
                    fontSize: 11.5,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                  color:
                      active ? AppColors.tintOf(context, color) : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$count',
                  style: GoogleFonts.inter(
                    color: active
                        ? AppColors.onSurfaceAccent(context, color)
                        : AppColors.mutedInk(context).withValues(alpha: 0.75),
                    fontSize: 10.5,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _buildStoriesText(List<VocabStory> stories) {
  final buf = StringBuffer();
  for (var i = 0; i < stories.length; i++) {
    final s = stories[i];
    if (s.title.trim().isNotEmpty) {
      buf.writeln('${i + 1}. ${s.title}');
    } else {
      buf.writeln('Story ${i + 1}');
    }
    buf.writeln(s.korean.trim());
    if (s.english.trim().isNotEmpty) buf.writeln(s.english.trim());
    if (i != stories.length - 1) buf.writeln();
  }
  return buf.toString().trimRight();
}

class _ShareStoriesRow extends StatelessWidget {
  const _ShareStoriesRow({required this.stories});
  final List<VocabStory> stories;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: GoldOutlinedButton(
            label: 'Copy stories',
            icon: Icons.copy_outlined,
            onPressed: () async {
              await Clipboard.setData(
                  ClipboardData(text: _buildStoriesText(stories)));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Stories copied to clipboard')),
                );
              }
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GoldOutlinedButton(
            label: 'Share',
            icon: Icons.ios_share,
            onPressed: () async {
              await Share.share(
                _buildStoriesText(stories),
                subject: 'Maldari — Korean stories',
              );
            },
          ),
        ),
      ],
    );
  }
}

class _StoryCountSelector extends StatelessWidget {
  const _StoryCountSelector({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'How many',
          style: GoogleFonts.inter(
            color: AppColors.mutedInk(context),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 12),
        for (final n in const [2, 3, 4, 5])
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _CountChip(
              n: n,
              selected: n == value,
              onTap: onChanged == null ? null : () => onChanged!(n),
            ),
          ),
      ],
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.n, required this.selected, this.onTap});
  final int n;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected
                ? AppColors.champagne.withValues(alpha: 0.5)
                : AppColors.surface(context),
            border: Border.all(
              color: selected
                  ? AppColors.deepGold
                  : AppColors.hairline(context),
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Text(
            '$n',
            style: GoogleFonts.inter(
              color: selected ? AppColors.deepGold : AppColors.ink(context),
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
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
      margin: const EdgeInsets.symmetric(vertical: 8),
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
