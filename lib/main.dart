import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers/theme_provider.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/llm_launcher.dart';
import 'providers/vocab_provider.dart';
import 'services/inbox_service.dart';
import 'services/storage_service.dart';
import 'services/tts_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StorageService.instance.init();

  // Front-load the three runtime-fetched fonts in parallel with the rest of
  // startup. They're cached to disk after the first run; pre-warming them
  // here avoids the visible re-layout "pop" when each font first resolves
  // while the user is mid-interaction. Fire-and-forget so launch never blocks.
  unawaited(GoogleFonts.pendingFonts([
    GoogleFonts.inter(),
    GoogleFonts.playfairDisplay(),
    GoogleFonts.notoSerifKr(),
  ]));

  // Autostart the local LLM server on app launch — fire-and-forget so the
  // UI never blocks on model load. Lighter flags (-ngl 20, -c 2048) keep
  // laptops responsive. Shutdown is wired through four lifecycle hooks
  // (onExitRequested / onDetach / didChangeAppLifecycleState / dispose) so
  // the process always dies with the app.
  unawaited(LlmLauncher.instance.ensureRunning());

  // Probe the platform speech engine for a Korean voice. Fire-and-forget:
  // the first `speak()` awaits init anyway, this just gets the answer ready
  // so Settings can report it without a pause.
  unawaited(TtsService.instance.init());

  runApp(const ProviderScope(child: MaldariApp()));
}

/// Lets the inbox report what it picked up, from outside any Scaffold.
final _messengerKey = GlobalKey<ScaffoldMessengerState>();

class MaldariApp extends ConsumerStatefulWidget {
  const MaldariApp({super.key});

  @override
  ConsumerState<MaldariApp> createState() => _MaldariAppState();
}

class _MaldariAppState extends ConsumerState<MaldariApp>
    with WidgetsBindingObserver {
  late final AppLifecycleListener _lifecycle;
  bool? _seenOnboarding;
  bool _shutdownStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Multiple shutdown hooks, because no single one covers every path:
    //
    //  - onExitRequested → desktop close-button (graceful)
    //  - onDetach        → engine detaches from runtime (works on most kills)
    //  - didChangeAppLifecycleState(detached) → mobile background→kill
    //  - dispose()       → hot restart, last-resort fallback
    //
    // In Flutter 3.41+ AppExitResponse lives in dart:ui, NOT services.
    _lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        await _shutdown();
        return ui.AppExitResponse.exit;
      },
      // Windows/macOS fire this when the OS is about to end the session. It
      // is not guaranteed to complete, so it only flushes — the durable state
      // is already on disk by this point.
      onInactive: () => unawaited(StorageService.instance.flushAll()),
      onDetach: () {
        unawaited(_shutdown());
      },
    );
    _loadOnboarding();

    // Words captured on the phone land here on the way in. After the first
    // frame, so a slow or cloud-backed folder can never hold up startup.
    WidgetsBinding.instance.addPostFrameCallback((_) => _importInbox());
  }

  /// Pulls in anything the phone dropped in the synced folder.
  ///
  /// Runs at launch and whenever the window is focused again, so switching
  /// back from the phone is enough to see the new words — there is nothing to
  /// press. Silent when there is nothing to report.
  Future<void> _importInbox() async {
    if (_importing || InboxService.instance.autoImportPaused) return;
    _importing = true;
    try {
      final result = await InboxService.instance.importNow();
      if (!mounted || !result.changedAnything) return;
      // The list reads the box at construction, so it needs telling.
      ref.read(vocabProvider.notifier).refresh();
      _messengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text('Imported from your phone — ${result.summary}'),
          duration: const Duration(seconds: 4),
          showCloseIcon: true,
        ),
      );
    } finally {
      _importing = false;
    }
  }

  bool _importing = false;

  Future<void> _shutdown() async {
    if (_shutdownStarted) return;
    _shutdownStarted = true;
    // Data first: if killing the model server hangs (or the OS pulls the rug
    // mid-shutdown), the user's words are already safely on disk.
    await StorageService.instance.close();
    await TtsService.instance.stop();
    await LlmLauncher.instance.stop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      unawaited(_shutdown());
      return;
    }
    // Anything other than "resumed" means the app could be killed without
    // another chance to run code — the OS backgrounding it, the user hitting
    // shut down, a laptop lid closing. Get pending writes onto disk now
    // rather than trusting that we'll be asked politely later.
    if (state != AppLifecycleState.resumed) {
      unawaited(StorageService.instance.flushAll());
      return;
    }
    // Back in the foreground — check whether the phone sent anything while we
    // were away.
    unawaited(_importInbox());
  }

  Future<void> _loadOnboarding() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _seenOnboarding = p.getBool('seen_onboarding') ?? false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lifecycle.dispose();
    // Last-resort fallback — none of the proper lifecycle hooks fired.
    unawaited(_shutdown());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'Maldari',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      darkTheme: buildDarkAppTheme(),
      themeMode: mode,
      scaffoldMessengerKey: _messengerKey,
      home: _seenOnboarding == null
          ? const _Splash()
          : (_seenOnboarding!
              ? const HomeScreen()
              : OnboardingScreen(
                  onDone: () => setState(() => _seenOnboarding = true),
                )),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
