import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/storage_service.dart';
import '../theme/app_colors.dart';

/// What happens to your words when the app dies badly.
///
/// Every claim on this page describes code that actually runs — the flush
/// timer in [StorageService], the four shutdown hooks in main.dart, and the
/// quarantine-instead-of-delete recovery path. Keep them in step: a promise
/// here that the code stopped keeping is worse than no page at all.
class DataSafetySheet extends StatelessWidget {
  const DataSafetySheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const DataSafetySheet(),
      );

  @override
  Widget build(BuildContext context) {
    final storage = StorageService.instance;
    final notes = storage.recoveryNotes;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.94,
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
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.goldTint(context),
                    ),
                    child: const Icon(Icons.shield_outlined,
                        color: AppColors.antiqueGold, size: 21),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '데이터 안전',
                          style: GoogleFonts.notoSerifKr(
                            color: AppColors.ink(context),
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '앱이 갑자기 꺼져도 단어가 사라지지 않는 이유',
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
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
                children: [
                  _StatusCard(notes: notes),
                  const SizedBox(height: 16),
                  _sectionLabel(context, '저장 방식'),
                  const _Point(
                    icon: Icons.save_outlined,
                    title: '0.4초마다 자동 저장',
                    body: '단어를 추가하거나 고치면 0.4초 뒤 디스크에 기록돼요. '
                        '저장 버튼은 없고, 누를 필요도 없어요. 여러 번 고쳐도 '
                        '기록은 한 번으로 묶여서 느려지지 않아요.',
                  ),
                  const _Point(
                    icon: Icons.power_settings_new,
                    title: '종료 경로마다 안전장치',
                    body: '창을 닫을 때, 엔진이 떨어져 나갈 때, 창이 비활성화될 때 '
                        '— 각각 따로 저장을 실행해요. 한 가지 방법으로는 모든 '
                        '종료를 잡을 수 없어서 네 군데에 걸어 뒀어요.',
                  ),
                  const _Point(
                    icon: Icons.laptop_chromebook_outlined,
                    title: '노트북을 덮어도',
                    body: '앱이 화면 뒤로 가는 순간에도 저장이 한 번 실행돼요. '
                        '그다음에 강제 종료돼도 이미 디스크에 있어요.',
                  ),
                  const SizedBox(height: 10),
                  _sectionLabel(context, '망가졌을 때'),
                  const _Point(
                    icon: Icons.healing_outlined,
                    title: '켤 때마다 검사하고 스스로 고쳐요',
                    body: '전원이 끊겨 파일 끝이 잘려도, 시작할 때 잘린 부분만 '
                        '떼어내고 나머지는 그대로 살려서 엽니다.',
                  ),
                  const _Point(
                    icon: Icons.inventory_2_outlined,
                    title: '무슨 일이 있어도 지우지 않아요',
                    body: '고칠 수 없을 만큼 손상된 파일도 삭제하지 않고 '
                        '.corrupt-(시각).hive 라는 이름으로 옆에 남겨 둡니다. '
                        '나중에 손으로 되살릴 수 있어요.',
                  ),
                  const _Point(
                    icon: Icons.lock_outline,
                    title: '파일이 잠겨 있어도 열려요',
                    body: 'OneDrive 동기화처럼 다른 프로그램이 파일을 붙잡고 '
                        '있으면, 임시 저장소로 실행해서 원본은 건드리지 않아요.',
                  ),
                  const SizedBox(height: 10),
                  _sectionLabel(context, '보호 범위'),
                  const _Point(
                    icon: Icons.folder_copy_outlined,
                    title: '단어만이 아니라 전부',
                    body: '단어, 이야기, 보관한 세트, 블록, 문법, 단어 페이지 '
                        '캐시까지 모두 같은 방식으로 저장되고 복구돼요.',
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '모든 데이터는 이 컴퓨터에만 저장돼요. 서버로 보내지 않습니다.',
                    style: GoogleFonts.notoSerifKr(
                      color: AppColors.mutedInk(context),
                      fontSize: 11.5,
                      height: 1.5,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 6, 0, 8),
        child: Text(
          text,
          style: GoogleFonts.notoSerifKr(
            color: AppColors.antiqueGold,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
      );
}

/// Live state, so the page reports rather than only promises.
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.notes});

  final List<String> notes;

  @override
  Widget build(BuildContext context) {
    final storage = StorageService.instance;
    final clean = notes.isEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        color: clean ? AppColors.goldTint(context) : AppColors.inset(context),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: clean
              ? AppColors.antiqueGold.withValues(alpha: 0.35)
              : AppColors.vermilion.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                clean ? Icons.verified_outlined : Icons.build_outlined,
                size: 17,
                color: clean ? AppColors.antiqueGold : AppColors.vermilion,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  clean ? '이번 실행: 이상 없음' : '이번 실행: 복구가 있었어요',
                  style: GoogleFonts.notoSerifKr(
                    color: AppColors.ink(context),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '단어 ${_count(() => storage.box.length)}개 · '
            '이야기 ${_count(() => storage.storiesBox.length)}개 · '
            '보관 세트 ${_count(() => storage.setsBox.length)}개',
            style: GoogleFonts.notoSerifKr(
              color: AppColors.mutedInk(context),
              fontSize: 12,
            ),
          ),
          if (!clean) ...[
            const SizedBox(height: 10),
            for (final n in notes)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• $n',
                  style: GoogleFonts.inter(
                    color: AppColors.mutedInk(context),
                    fontSize: 11,
                    height: 1.45,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// The boxes throw if the app somehow reaches here before init — a status
  /// readout must never be the thing that crashes the app.
  static String _count(int Function() read) {
    try {
      return '${read()}';
    } catch (_) {
      return '—';
    }
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 16, color: AppColors.antiqueGold),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.notoSerifKr(
                    color: AppColors.ink(context),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: GoogleFonts.notoSerifKr(
                    color: AppColors.mutedInk(context),
                    fontSize: 12,
                    height: 1.65,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
