import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/vocab_provider.dart';
import '../providers/word_set_provider.dart';
import '../services/word_set_store.dart';
import '../theme/app_colors.dart';

/// The shelf of finished review sets.
///
/// One switch per set decides whether its words are back in the review deck,
/// and any number of sets can be on at once — which is what "choose which
/// group to review again" has to mean once there is more than one.
class WordSetsSheet extends ConsumerWidget {
  const WordSetsSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const WordSetsSheet(),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sets = ref.watch(wordSetsProvider);
    final words = ref.watch(vocabProvider);
    final byId = {for (final w in words) w.id: w};

    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) => Container(
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
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 6),
              child: Row(
                children: [
                  const Icon(Icons.inventory_2_outlined,
                      color: AppColors.antiqueGold, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '보관한 세트',
                          style: GoogleFonts.notoSerifKr(
                            color: AppColors.ink(context),
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '켜면 그 세트의 단어가 복습 카드로 다시 돌아와요.',
                          style: GoogleFonts.notoSerifKr(
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
              child: sets.isEmpty
                  ? _empty(context)
                  : ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                      itemCount: sets.length,
                      itemBuilder: (context, i) => _SetTile(
                        set: sets[i],
                        // A word deleted from the vocabulary simply stops
                        // being part of the set — the id stays, but there is
                        // nothing left to show or to review.
                        preview: [
                          for (final id in sets[i].wordIds)
                            if (byId[id] != null) byId[id]!.hangul,
                        ],
                      ),
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.goldTint(context),
                ),
                child: const Icon(Icons.inventory_2_outlined,
                    color: AppColors.antiqueGold, size: 26),
              ),
              const SizedBox(height: 16),
              Text(
                '아직 보관한 세트가 없어요.\n복습을 한 바퀴 끝내면 그 단어들을 묶어서 보관할 수 있어요.',
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSerifKr(
                  color: AppColors.mutedInk(context),
                  fontSize: 13,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
      );
}

class _SetTile extends ConsumerWidget {
  const _SetTile({required this.set, required this.preview});

  final WordSet set;

  /// The Hangul of the words still in the collection, in set order.
  final List<String> preview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent =
        set.active ? AppColors.deepGold : AppColors.mutedInk(context);
    final missing = set.size - preview.length;
    final meta = StringBuffer('${set.size}개 단어 · ${_stamp(set.createdAt)}');
    if (set.active) meta.write(' · 복습 중');
    if (missing > 0) meta.write(' · $missing개는 삭제됨');

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color:
            set.active ? AppColors.goldTint(context) : AppColors.inset(context),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: set.active
              ? AppColors.antiqueGold.withValues(alpha: 0.4)
              : AppColors.hairline(context),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  set.name,
                  style: GoogleFonts.notoSerifKr(
                    color: AppColors.ink(context),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Switch(
                value: set.active,
                activeThumbColor: AppColors.antiqueGold,
                onChanged: (v) =>
                    ref.read(wordSetsProvider.notifier).setActive(set.id, v),
              ),
              PopupMenuButton<String>(
                tooltip: '세트 관리',
                icon: Icon(Icons.more_vert,
                    size: 18, color: AppColors.mutedInk(context)),
                onSelected: (choice) async {
                  if (choice == 'rename') {
                    await _rename(context, ref);
                  } else if (choice == 'release') {
                    await _release(context, ref);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('이름 바꾸기')),
                  PopupMenuItem(value: 'release', child: Text('세트 해제')),
                ],
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              meta.toString(),
              style: GoogleFonts.notoSerifKr(
                color: accent,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (preview.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final h in preview.take(12))
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.surface(context),
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                        border: Border.all(color: AppColors.hairline(context)),
                      ),
                      child: Text(
                        h,
                        style: GoogleFonts.notoSerifKr(
                          color: AppColors.ink(context),
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  if (preview.length > 12)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        '+${preview.length - 12}',
                        style: GoogleFonts.inter(
                          color: AppColors.mutedInk(context),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: set.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('이름 바꾸기', style: GoogleFonts.notoSerifKr(fontSize: 17)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: GoogleFonts.notoSerifKr(fontSize: 15),
          decoration: const InputDecoration(hintText: '세트 이름'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    await ref.read(wordSetsProvider.notifier).rename(set.id, name);
  }

  /// Dissolving a set never touches the words — it only stops holding them
  /// out of review, so the dialog says exactly that.
  Future<void> _release(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('"${set.name}" 세트를 해제할까요?',
            style: GoogleFonts.notoSerifKr(fontSize: 16)),
        content: Text(
          '단어는 그대로 남고 묶음만 사라져요. ${set.size}개 단어가 다시 일반 복습 카드로 돌아갑니다.',
          style: GoogleFonts.notoSerifKr(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('해제')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(wordSetsProvider.notifier).release(set.id);
  }

  static String _stamp(DateTime d) =>
      '${d.year}.${d.month.toString().padLeft(2, '0')}.'
      '${d.day.toString().padLeft(2, '0')}';
}
