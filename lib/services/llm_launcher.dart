import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Spawns and tracks the local `llama-server.exe` process.
class LlmLauncher {
  LlmLauncher._();
  static final LlmLauncher instance = LlmLauncher._();

  Process? _ownedProcess;
  int? _ownedPid;
  bool _starting = false;

  /// Last error message from a start attempt — surfaced in Settings.
  String? lastError;

  static const _kServerPath = 'llm_server_path';
  static const _kModelPath = 'llm_model_path';

  /// PID of the server we spawned, remembered across launches so a process
  /// orphaned by an abrupt exit can still be cleaned up later.
  static const _kOwnedPid = 'llm_owned_pid';

  static String defaultServerPath() {
    if (Platform.isWindows) {
      return r'C:\Users\senso\llama.cpp\llama-server.exe';
    }
    return '/usr/local/bin/llama-server';
  }

  static String defaultModelPath() {
    if (Platform.isWindows) {
      return r'C:\Users\senso\Models\gemma-4-E4B-it\gemma-4-E4B-it-Q4_K_M.gguf';
    }
    return '${Platform.environment['HOME'] ?? ''}/models/gemma-3n-e4b.gguf';
  }

  Future<String> serverPath() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kServerPath) ?? defaultServerPath();
  }

  Future<String> modelPath() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kModelPath) ?? defaultModelPath();
  }

  Future<void> setPaths({String? serverPath, String? modelPath}) async {
    final p = await SharedPreferences.getInstance();
    if (serverPath != null) await p.setString(_kServerPath, serverPath);
    if (modelPath != null) await p.setString(_kModelPath, modelPath);
  }

  Future<bool> isHealthy() async {
    try {
      final res = await http
          .get(Uri.parse('http://127.0.0.1:8080/health'))
          .timeout(const Duration(milliseconds: 1500));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Re-adopts a server left running by a previous session that ended
  /// abruptly (power cut, task-manager kill, OS shutdown).
  ///
  /// Without this the orphan keeps the port and the GPU memory for the rest
  /// of the machine's uptime, because a later clean exit only kills PIDs this
  /// run spawned. The recorded PID is verified to still BE a llama-server
  /// before we adopt it — PIDs get recycled, and force-killing whatever
  /// inherited the number would be far worse than leaking a process.
  Future<void> _adoptOrphan() async {
    if (_ownedPid != null) return;
    final prefs = await SharedPreferences.getInstance();
    final pid = prefs.getInt(_kOwnedPid);
    if (pid == null) return;

    if (!await _isLlamaServer(pid)) {
      _log('Recorded pid=$pid is not a llama-server any more — forgetting it.');
      await prefs.remove(_kOwnedPid);
      return;
    }

    if (await isHealthy()) {
      // Alive and serving: take ownership so it dies with this session.
      _log('Adopted orphaned server pid=$pid.');
      _ownedPid = pid;
      return;
    }

    // Alive but not answering — a wedged process squatting on the port.
    // Clear it out so the fresh start below can bind.
    _log('Orphan pid=$pid is unhealthy — terminating it.');
    _ownedPid = pid;
    await stop();
  }

  /// True if [pid] currently belongs to a llama-server process.
  Future<bool> _isLlamaServer(int pid) async {
    try {
      if (Platform.isWindows) {
        final r = await Process.run(
          'tasklist',
          ['/FI', 'PID eq $pid', '/FO', 'CSV', '/NH'],
        );
        return '${r.stdout}'.toLowerCase().contains('llama-server');
      }
      final r = await Process.run('ps', ['-p', '$pid', '-o', 'comm=']);
      return '${r.stdout}'.toLowerCase().contains('llama-server');
    } catch (_) {
      return false;
    }
  }

  /// Health-check; if not running, spawn and poll for up to 120 s.
  Future<bool> ensureRunning() async {
    await _adoptOrphan();
    if (await isHealthy()) {
      _log('Server already healthy.');
      return true;
    }
    if (_starting) {
      _log('Start already in progress — waiting for it to come up.');
      return _waitForHealth(const Duration(seconds: 120));
    }
    _starting = true;
    lastError = null;

    try {
      final server = await serverPath();
      final model = await modelPath();

      _log('Starting server\n  exe   = $server\n  model = $model');

      if (!File(server).existsSync()) {
        lastError = 'llama-server.exe not found at:\n$server';
        _log(lastError!);
        return false;
      }
      if (!File(model).existsSync()) {
        lastError = 'Model .gguf not found at:\n$model';
        _log(lastError!);
        return false;
      }

      // Args:
      //   -c 8192  → context window. Needs to be large enough to hold the
      //              prompt PLUS the generated output. The Stories tab asks
      //              for ~5 multi-sentence stories (Korean + English) in one
      //              response; at -c 2048 the JSON array was truncated and
      //              only the first 2-3 stories survived parsing. 8192 gives
      //              comfortable headroom.
      //   -ngl 99  → full GPU offload. The Q4_K_M Gemma-4-E4B is ~3 GB
      //              and most discrete GPUs have plenty of room. Partial
      //              offload (e.g. `-ngl 20`) combined with the default
      //              `-fit on` auto-fitter currently triggers an internal
      //              llama.cpp assertion (n_inputs < GGML_SCHED_MAX_SPLIT_INPUTS)
      //              on this model — so we bypass it.
      //   -fit off → skip the (buggy) auto-fit pass entirely.
      //
      // If the user's GPU lacks the VRAM, llama-server will surface an OOM
      // and we'll show it in `lastError` via the stderr pipe.
      //
      // NOTE: `ProcessStartMode.normal` (not detached) so stdout/stderr
      // can be read for diagnostics. The process still outlives this Dart
      // call; we kill it via PID on shutdown.
      _ownedProcess = await Process.start(
        server,
        [
          '-m', model,
          '--host', '127.0.0.1',
          '--port', '8080',
          '-c', '8192',
          '-ngl', '99',
          '-fit', 'off',
          '--jinja',
          '--alias', 'maldari-gemma',
        ],
        mode: ProcessStartMode.normal,
      );
      _ownedPid = _ownedProcess?.pid;
      _log('Spawned pid=$_ownedPid');

      // Persist the PID before waiting for health: if the app dies during the
      // 120 s model load, the next launch can still find and reclaim this
      // process instead of leaving it running forever.
      if (_ownedPid != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_kOwnedPid, _ownedPid!);
      }

      // Pipe stderr to console so model-load errors are visible.
      _ownedProcess!.stderr
          .transform(const SystemEncoding().decoder)
          .listen((line) => _log('[llama] $line'));

      // 120 s gives Gemma 4 plenty of time to load on partial offload.
      final deadline = DateTime.now().add(const Duration(seconds: 120));
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 750));
        if (await isHealthy()) {
          _log('Server is up.');
          return true;
        }
      }
      lastError = 'Server did not respond on /health within 120 s.';
      _log(lastError!);
      return false;
    } catch (e, s) {
      lastError = 'Failed to start: $e';
      _log('Start exception: $e\n$s');
      return false;
    } finally {
      _starting = false;
    }
  }

  /// Poll `/health` until the server answers or [timeout] elapses.
  Future<bool> _waitForHealth(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await isHealthy()) return true;
      await Future<void>.delayed(const Duration(milliseconds: 750));
    }
    return false;
  }

  void _log(String msg) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[LlmLauncher] $msg');
    }
  }

  /// Kill the process — but ONLY if we started it.
  ///
  /// On Windows a `Process.start(..., detached)` child is orphaned at the OS
  /// level. `Process.kill()` is best-effort and frequently fails silently —
  /// the handle gets stale once the child detaches. We fall back to
  /// `taskkill /F /T /PID` which forcibly tears down the process tree.
  Future<void> stop() async {
    final pid = _ownedPid;
    final p = _ownedProcess;
    _ownedProcess = null;
    _ownedPid = null;

    // Forget the recorded PID first — if we're killed halfway through this
    // teardown, the next launch shouldn't chase a process that's already
    // dying (or, after PID reuse, someone else entirely).
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kOwnedPid);
    } catch (_) {}

    if (p != null) {
      try {
        p.kill(ProcessSignal.sigterm);
      } catch (_) {}
    }

    if (pid != null) {
      try {
        if (Platform.isWindows) {
          // /F = force, /T = kill child tree as well.
          await Process.run('taskkill', ['/F', '/T', '/PID', '$pid']);
        } else {
          // POSIX — escalate from SIGTERM to SIGKILL after a brief grace.
          try {
            Process.killPid(pid, ProcessSignal.sigterm);
          } catch (_) {}
          await Future<void>.delayed(const Duration(milliseconds: 300));
          try {
            Process.killPid(pid, ProcessSignal.sigkill);
          } catch (_) {}
        }
      } catch (_) {}
    }
  }
}
