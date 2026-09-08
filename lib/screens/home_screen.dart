import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/vocab_provider.dart';
import '../services/inbox_service.dart';
import '../theme/app_colors.dart';
import '../widgets/data_safety_sheet.dart';
import 'blocks_screen.dart';
import 'examples_screen.dart';
import 'grammar_screen.dart';
import 'review_screen.dart';
import 'settings_screen.dart';
import 'vocab_list_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static const _titles = [
    'Review',
    'Vocabulary',
    'Stories',
    'Blocks',
    'Grammar',
  ];

  /// Shown under each English title in the header band.
  static const _koreanTitles = [
    '복습',
    '단어장',
    '이야기',
    '블록',
    '문법',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(activeTabProvider);

    // The header band is black in both themes, so the status bar always wants
    // light icons.
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);

    return Scaffold(
      // Deliberately NOT extendBody: the floating bar keeps its own slot in
      // the layout, so every tab's existing bottom padding still clears it.
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(74),
        child: AppBar(
          toolbarHeight: 74,
          backgroundColor: Colors.transparent,
          // Black band with softly rounded bottom corners — the content below
          // reads as sliding out from under it.
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: AppColors.chromeGradient,
              borderRadius:
                  BorderRadius.vertical(bottom: Radius.circular(AppRadius.lg)),
            ),
          ),
          // Title is left-aligned and bilingual now: the English section name
          // over its Korean counterpart, instead of a centred word with a rule
          // underneath.
          centerTitle: false,
          titleSpacing: 20,
          title: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.25),
                  end: Offset.zero,
                ).animate(anim),
                child: child,
              ),
            ),
            child: Column(
              key: ValueKey(tab),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _titles[tab],
                  style: GoogleFonts.playfairDisplay(
                    color: AppColors.ivory,
                    fontSize: 21,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Container(
                      width: 14,
                      height: 2,
                      decoration: BoxDecoration(
                        gradient: AppColors.goldGradient,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _koreanTitles[tab],
                      style: GoogleFonts.notoSerifKr(
                        color: AppColors.lightGold,
                        fontSize: 12,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            // Importing is a thing you do, not a thing you configure, so it
            // lives in the header rather than three taps deep in Settings.
            _CircleAction(
              icon: Icons.download_outlined,
              tooltip: 'Import words from phone',
              onTap: () => _importFromPhone(context, ref),
            ),
            const SizedBox(width: 8),
            // Next to Settings, and deliberately not inside it: the one
            // question this answers — "will I lose my words?" — is asked
            // before anyone goes looking through preferences.
            _CircleAction(
              icon: Icons.shield_outlined,
              tooltip: 'Data safety',
              onTap: () => DataSafetySheet.show(context),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: _CircleAction(
                icon: Icons.settings_outlined,
                tooltip: 'Settings',
                onTap: () => _confirmOpenSettings(context),
              ),
            ),
          ],
        ),
      ),
      // IndexedStack keeps all three tab trees mounted, but the engine
      // only paints the active one (the others get `Offstage`-like
      // treatment). That makes tab switches essentially free — no
      // ReviewScreen rebuild (which would recreate the Flashcard
      // AnimationController), no relayout of the vocab tiles, no
      // recomposition of the examples picker. State within each tab
      // (text controllers, scroll positions, expanded breakdowns) also
      // survives.
      body: Container(
        // Barely-there warm wash so large empty areas aren't flat ivory.
        decoration: BoxDecoration(gradient: AppColors.pageGradient(context)),
        child: IndexedStack(
          index: tab,
          children: const [
            ReviewScreen(),
            VocabListScreen(),
            ExamplesScreen(),
            BlocksScreen(),
            GrammarScreen(),
          ],
        ),
      ),
      bottomNavigationBar: _BottomNav(
        index: tab,
        onChanged: (i) => ref.read(activeTabProvider.notifier).state = i,
      ),
    );
  }
}

/// Floating, rounded navigation bar — detached from the screen edges and
/// resting on a soft shadow instead of sitting in a full-width slab.
class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.index, required this.onChanged});
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          gradient: AppColors.chromeGradient,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: AppColors.onyxEdge),
          boxShadow: AppColors.floatShadow(context),
        ),
        child: SizedBox(
          height: 64,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Row(
              children: [
                _NavItem(
                  icon: Icons.style_outlined,
                  activeIcon: Icons.style,
                  label: '복습',
                  selected: index == 0,
                  onTap: () => onChanged(0),
                ),
                _NavItem(
                  icon: Icons.translate_outlined,
                  activeIcon: Icons.translate,
                  label: '단어',
                  selected: index == 1,
                  onTap: () => onChanged(1),
                ),
                _NavItem(
                  icon: Icons.auto_stories_outlined,
                  activeIcon: Icons.auto_stories,
                  label: '이야기',
                  selected: index == 2,
                  onTap: () => onChanged(2),
                ),
                _NavItem(
                  icon: Icons.grid_view_outlined,
                  activeIcon: Icons.grid_view,
                  label: '블록',
                  selected: index == 3,
                  onTap: () => onChanged(3),
                ),
                _NavItem(
                  icon: Icons.menu_book_outlined,
                  activeIcon: Icons.menu_book,
                  label: '문법',
                  selected: index == 4,
                  onTap: () => onChanged(4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // On the black bar, unselected items are dim ivory rather than the page's
    // muted ink — which would vanish against the chrome.
    final color = selected
        ? Colors.white
        : AppColors.cream.withValues(alpha: 0.55);
    final radius = BorderRadius.circular(AppRadius.md);
    // Expanded → each tab fills its share of the row and the whole area is
    // tappable (huge ergonomic improvement over a tight padding box).
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Material(
          color: Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                borderRadius: radius,
                // The selected tab is a solid gold pill rather than a faint
                // champagne wash — unmistakable at a glance.
                gradient: selected ? AppColors.goldGradient : null,
                boxShadow: selected
                    ? const [
                        BoxShadow(
                          color: Color(0x33A8873E),
                          blurRadius: 10,
                          offset: Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // The icon nudges up as its label bolds — subtle, but it
                  // makes selection feel like a state change, not a repaint.
                  AnimatedSlide(
                    offset: selected ? const Offset(0, -0.04) : Offset.zero,
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    child: Icon(
                      selected ? activeIcon : icon,
                      color: color,
                      size: 21,
                    ),
                  ),
                  const SizedBox(height: 3),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      // Korean labels need the Korean face — Inter has no
                      // Hangul glyphs and would fall back inconsistently.
                      style: GoogleFonts.notoSerifKr(
                        color: color,
                        fontSize: 11,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                        letterSpacing: 0.2,
                      ),
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

/// Pulls in whatever the phone has sent, and always says what happened.
///
/// Deliberately louder than the automatic import: that one runs on its own and
/// stays quiet when there is nothing to report, but a press is a question, and
/// a question deserves an answer even when the answer is "nothing new".
Future<void> _importFromPhone(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final result = await InboxService.instance.importNow();
  if (result.changedAnything) ref.read(vocabProvider.notifier).refresh();
  if (!context.mounted) return;

  messenger.clearSnackBars();
  final bar = messenger.showSnackBar(
    SnackBar(
      content: Text(
        result.configured
            ? result.summary
            : 'No inbox folder set — add one in Settings',
      ),
      duration: const Duration(seconds: 4),
      showCloseIcon: true,
    ),
  );
  Timer(const Duration(seconds: 4), bar.close);
}

/// Asks before opening Settings.
///
/// The gear sits in the app bar on every tab, one stray tap away at all
/// times — and behind it are the API key and the bulk deletes. A confirm
/// makes getting there deliberate.
Future<void> _confirmOpenSettings(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(
        '설정을 열까요?',
        style: GoogleFonts.notoSerifKr(fontSize: 18, fontWeight: FontWeight.w600),
      ),
      content: Text(
        'Settings holds your ElevenLabs key, the model server paths, and the '
        'bulk-delete actions.',
        style: GoogleFonts.inter(fontSize: 13, height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('취소'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('열기'),
        ),
      ],
    ),
  );

  if (ok != true || !context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const _SettingsRoute()),
  );
}

/// Small circular tonal button used for app-bar actions.
class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        // Sits on the black band, so it takes a lifted-onyx fill with a gold
        // hairline rather than the page's champagne tint.
        color: AppColors.onyxLift,
        shape: CircleBorder(
          side: BorderSide(color: AppColors.antiqueGold.withValues(alpha: 0.35)),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: Icon(icon, size: 19, color: AppColors.lightGold),
          ),
        ),
      ),
    );
  }
}

class _SettingsRoute extends StatelessWidget {
  const _SettingsRoute();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: const SettingsScreen(),
    );
  }
}
