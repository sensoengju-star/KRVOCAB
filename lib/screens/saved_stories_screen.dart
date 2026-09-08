import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/vocab_provider.dart';
import '../providers/tts_settings_provider.dart';
import '../services/narration_service.dart';
import '../services/story_store.dart';
import '../theme/app_colors.dart';
import '../widgets/story_card.dart';

/// Every story the model has written, kept across restarts.
///
/// Its own page rather than a tail on the Stories tab: the library grows
/// without bound, and burying the generate controls under a hundred saved
/// stories makes the tab worse at the one job it has.
class SavedStoriesScreen extends ConsumerStatefulWidget {
  const SavedStoriesScreen({super.key});

  @override
  ConsumerState<SavedStoriesScreen> createState() => _SavedStoriesScreenState();
}

class _SavedStoriesScreenState extends ConsumerState<SavedStoriesScreen> {
  List<SavedStory> _saved = const [];
  final _search = TextEditingController();

  /// The shared player, watched so finishing a story here records that it
  /// was heard in full.
  NarrationController? _narration;

  @override
  void initState() {
    super.initState();
    _saved = StoryStore.instance.all();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = ref.read(narrationProvider);
      controller.addListener(_onNarration);
      _narration = controller;
    });
  }

  /// A story counts as narrated once EVERY sentence has been played. The
  /// player reports that; here it becomes a flag on disk, which is half of
  /// what deleting the story requires.
  Future<void> _onNarration() async {
    final done = _narration?.value.completedId;
    if (done == null) return;
    final match = _saved.where((s) => _idOf(s) == done);
    if (match.isEmpty || match.first.narrated) return;
    await StoryStore.instance.setFlags(match.first.id, narrated: true);
    if (!mounted) return;
    setState(() => _saved = StoryStore.instance.all());
  }

  /// Same identity the card hands the player.
  String _idOf(SavedStory s) =>
      '${s.story.title}#${s.story.korean.hashCode}';

  @override
  void dispose() {
    _narration?.removeListener(_onNarration);
    _search.dispose();
    super.dispose();
  }

  Future<void> _toggleRead(SavedStory saved) async {
    await StoryStore.instance.setFlags(saved.id, read: !saved.read);
    if (!mounted) return;
    setState(() => _saved = StoryStore.instance.all());
  }

  Future<void> _delete(SavedStory saved) async {
    await StoryStore.instance.delete(saved.id);
    if (!mounted) return;
    setState(() => _saved = StoryStore.instance.all());
  }

  Future<void> _confirmClear() async {
    final removable = _saved.where((s) => s.canDelete).length;
    if (removable == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Nothing to delete — stories unlock once heard in full and marked read'),
        ),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $removable finished ${removable == 1 ? 'story' : 'stories'}?',
            style: GoogleFonts.playfairDisplay(fontSize: 18)),
        content: Text(
          _saved.length == removable
              ? 'They took a while to write, and this cannot be undone.'
              : 'Only stories you have heard in full and marked read are '
                  'removed; the other ${_saved.length - removable} stay.',
          style: GoogleFonts.inter(fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete all',
                style: TextStyle(color: AppColors.softRed)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await StoryStore.instance.clearCompleted();
    if (!mounted) return;
    setState(() => _saved = StoryStore.instance.all());
  }

  @override
  Widget build(BuildContext context) {
    // Highlighting still resolves against the CURRENT vocabulary, so a story
    // keeps marking the words you're studying today.
    final words = ref.watch(vocabProvider);
    final targets = {for (final w in words) w.hangul.trim()};
    final glossary = {
      for (final w in words) w.hangul.trim(): w.englishMeaning.trim(),
    };

    final q = _search.text.trim().toLowerCase();
    final shown = q.isEmpty
        ? _saved
        : [
            for (final s in _saved)
              if (s.story.korean.toLowerCase().contains(q) ||
                  s.story.title.toLowerCase().contains(q) ||
                  s.story.english.toLowerCase().contains(q))
                s,
          ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Saved stories',
          style: GoogleFonts.playfairDisplay(
            color: AppColors.ivory,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          if (_saved.isNotEmpty)
            IconButton(
              tooltip: 'Delete all saved stories',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: _confirmClear,
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.pageGradient(context)),
        child: _saved.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.goldTint(context),
                        ),
                        child: const Icon(Icons.auto_stories_outlined,
                            color: AppColors.antiqueGold, size: 28),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'No saved stories yet — write some in the Stories tab '
                        'and they\'ll be kept here.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.playfairDisplay(
                          color: AppColors.mutedInk(context),
                          fontSize: 17,
                          height: 1.45,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    style: GoogleFonts.notoSerifKr(fontSize: 15),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search,
                          color: AppColors.antiqueGold, size: 19),
                      hintText: '이야기 검색…',
                      hintStyle: GoogleFonts.notoSerifKr(
                        color: AppColors.mutedInk(context),
                        fontSize: 14,
                      ),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: '검색 지우기',
                              icon: Icon(Icons.close,
                                  size: 17,
                                  color: AppColors.mutedInk(context)),
                              onPressed: () {
                                _search.clear();
                                setState(() {});
                              },
                            ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 13),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide:
                            BorderSide(color: AppColors.hairline(context)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    q.isEmpty
                        ? '${_saved.length} '
                            'stor${_saved.length == 1 ? 'y' : 'ies'}'
                        : '${shown.length} of ${_saved.length} match',
                    style: GoogleFonts.inter(
                      color: AppColors.mutedInk(context),
                      fontSize: 11.5,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final saved in shown)
                    StoryCard(
                      key: ValueKey(saved.id),
                      story: saved.story,
                      targets: targets,
                      glossary: glossary,
                      savedAt: saved.createdAt,
                      narrated: saved.narrated,
                      read: saved.read,
                      onToggleRead: () => _toggleRead(saved),
                      onDelete: () => _delete(saved),
                    ),
                  if (shown.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Text(
                        'Nothing matches "$q".',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.notoSerifKr(
                          color: AppColors.mutedInk(context),
                          fontSize: 14,
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
