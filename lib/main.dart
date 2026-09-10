import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'providers/theme_provider.dart';
import 'screens/home_screen.dart';
import 'screens/locked_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/llm_launcher.dart';
import 'providers/vocab_provider.dart';
import 'services/inbox_service.dart';
import 'services/single_instance.dart';
import 'services/storage_service.dart';
import 'services/tray_service.dart';
import 'services/vocab_export_service.dart';
import 'services/tts_service.dart';
import 'theme/app_theme.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Claim the slot BEFORE storage is touched. A tray app holds the data files
  // open for as long as it lives, so a second copy would find every box
  // locked; turning it away here means it never reaches them.
  final only = await SingleInstance.claim(
    onSecondLaunch: () => TrayService.instance.show(),
  );
  if (!only) {
    exit(0);
  }

  _startedAtLogin = args.contains(TrayService.startedAtLoginFlag);

  await windowManager.ensureInitialized();
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

  // Start the model server with the app, so the first story or example does
  // not wait on a model load. Fire-and-forget: the UI never blocks on it, and
  // LlmConfig.load still calls ensureRunning before any request, which covers
  // a request made while the server is stopped.
  //
  // It still stops when the window hides and starts again when it returns —
  // that is what keeps a tray app from holding a model resident all day.
  unawaited(LlmLauncher.instance.ensureRunning());

  // Probe the platform speech engine for a Korean voice. Fire-and-forget:
  // the first `speak()` awaits init anyway, this just gets the answer ready
  // so Settings can report it without a pause.
  unawaited(TtsService.instance.init());

  // The return leg: the collection is written into the same synced folder so
  // the phone can read it. Debounced on box changes, so it tracks the app.
  VocabExportService.instance.armAutoExport();
  unawaited(VocabExportService.instance.exportNow());

  _start();
}

/// Wires the tray to the things only main can reach, then raises it.
Future<void> _startTray() async {
  final tray = TrayService.instance;

  // Wire the callbacks unconditionally, even when the tray is switched off.
  // Turning it on later calls start() from Settings, and a tray whose menu
  // items did nothing because main had returned early would be worse than no
  // tray at all.
  tray.onImport = () async => _backgroundImport();
  // Hiding is the moment nothing is being looked at: a good time to let the
  // model server go.
  tray.onShow = () async => LlmLauncher.instance.ensureRunning();
  tray.onHide = () async {
    // Closing the window is often the last thing done before walking away or
    // shutting the machine down. Get everything on disk now rather than
    // trusting the 400 ms timer to win a race against a session ending.
    await StorageService.instance.flushAll();
    await LlmLauncher.instance.stop();
  };
  tray.onQuit = () async {
    // Data first and alone: if stopping the model server hangs, the words are
    // already safely closed. The rest can go at once — none of it depends on
    // the others, and serialising them only makes the wait longer.
    await StorageService.instance.close();
    await Future.wait([
      TtsService.instance.stop(),
      LlmLauncher.instance.stop(),
      SingleInstance.release(),
    ]);
  };
  // The folder tells us the moment something lands, so the timer above is a
  // safety net rather than the way words arrive.
  await InboxService.instance.armWatch(() async {
    await _backgroundImport();
    // A file landed, so more may be landing. Let the poll speed up too.
    await TrayService.instance.quicken();
  });

  if (await tray.runInTray()) await tray.start();

  // Launched by Windows at login: come up in front. A window started behind
  // everything else is easy to miss entirely, and a vocabulary app you do not
  // see is a vocabulary app you do not use — being in view at the start of
  // the day is the point of starting with Windows at all.
  if (_startedAtLogin) await tray.show();
}

/// True when Windows started us at login rather than a person did.
bool _startedAtLogin = false;

/// The timed import. Runs with no window on screen, so it says nothing and
/// leaves its account in the import history instead.
Future<bool> _backgroundImport() async {
  if (InboxService.instance.autoImportPaused) return false;
  final result = await InboxService.instance.importNow();
  if (!result.changedAnything) return false;
  _rootContainer?.read(vocabProvider.notifier).refresh();
  return true;
}

/// The provider container behind the running app, so a timer firing while the
/// window is hidden can still refresh what the list will show.
ProviderContainer? _rootContainer;

/// Lets the inbox report what it picked up, from outside any Scaffold.
final _messengerKey = GlobalKey<ScaffoldMessengerState>();

/// Starts the app, or the locked-out screen when the data is held elsewhere.
///
/// Deliberately a function rather than a branch inside a widget: the retry
/// button re-runs startup, and this is the one place that decides which of
/// the two the app is.
void _start() {
  if (StorageService.instance.lockedOut) {
    runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildDarkAppTheme(),
      home: const LockedScreen(onRetry: _start),
    ));
    return;
  }
  final container = ProviderContainer();
  _rootContainer = container;
  runApp(UncontrolledProviderScope(
    container: container,
    child: const MaldariApp(),
  ));
  unawaited(_startTray());
}

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

    // And again shortly after. A file the phone saved a moment ago may still
    // be on its way down when the app opens, and the sync client gives no
    // signal when it lands — a second look costs nothing and saves you
    // wondering where your words went.
    Timer(const Duration(seconds: 10), () {
      if (mounted) unawaited(_importInbox());
    });
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

  /// Windows asking the app to exit — a session ending, most often.
  ///
  /// The tray makes this the likely shutdown path rather than an unusual one:
  /// the window being closed no longer ends the process, so a machine going
  /// down meets a running app. window_manager holds the window open on our
  /// behalf, which could otherwise swallow the close entirely and leave the
  /// OS to kill us; answering here means the data is closed properly first
  /// and Windows is not kept waiting.
  @override
  Future<ui.AppExitResponse> didRequestAppExit() async {
    await _shutdown();
    return ui.AppExitResponse.exit;
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
