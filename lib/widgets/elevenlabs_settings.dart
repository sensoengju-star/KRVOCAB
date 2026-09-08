import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/tts_settings_provider.dart';
import '../services/elevenlabs_service.dart';
import '../services/narration_service.dart';
import '../theme/app_colors.dart';
import 'gold_button.dart';

/// Settings block for story narration: how much plays per press, and the
/// ElevenLabs credentials that narration runs on.
///
/// The key is held in SharedPreferences on this machine only. It is never
/// written into the project, so it cannot end up in the public repo.
class ElevenLabsSettings extends ConsumerStatefulWidget {
  const ElevenLabsSettings({super.key});

  @override
  ConsumerState<ElevenLabsSettings> createState() => _ElevenLabsSettingsState();
}

class _ElevenLabsSettingsState extends ConsumerState<ElevenLabsSettings> {
  final _key = TextEditingController();
  final _voice = TextEditingController();

  bool _obscure = true;
  bool _busy = false;
  String? _status;
  bool _statusIsError = false;
  int _cacheBytes = 0;
  double _speed = ElevenLabsService.defaultSpeed;
  double _stability = ElevenLabsService.defaultStability;
  List<({String id, String name})> _voices = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _key.dispose();
    _voice.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final svc = ElevenLabsService.instance;
    _key.text = await svc.apiKey() ?? '';
    _voice.text = await svc.voiceId();
    final rate = await svc.speed();
    final steadiness = await svc.stability();
    final size = await svc.cacheSize();
    if (mounted) {
      setState(() {
        _cacheBytes = size;
        _speed = rate;
        _stability = steadiness;
      });
    }
  }

  void _report(String message, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _status = message;
      _statusIsError = error;
      _busy = false;
    });
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    await ElevenLabsService.instance.save(
      apiKey: _key.text,
      voiceId: _voice.text,
    );
    _report('Saved.');
  }

  /// Saves, then spends a handful of characters proving the key can actually
  /// synthesize — the failure modes (revoked key, missing scope, no credits)
  /// are otherwise indistinguishable until narration silently fails.
  Future<void> _testKey() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    await ElevenLabsService.instance
        .save(apiKey: _key.text, voiceId: _voice.text);
    try {
      await ElevenLabsService.instance.testKey();
      _report('Key works — 안녕하세요 synthesized and cached.');
    } on ElevenLabsException catch (e) {
      _report(e.message, error: true);
    } catch (e) {
      _report('$e', error: true);
    }
    final size = await ElevenLabsService.instance.cacheSize();
    if (mounted) setState(() => _cacheBytes = size);
  }

  Future<void> _fetchVoices() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    await ElevenLabsService.instance.save(apiKey: _key.text);
    try {
      final list = await ElevenLabsService.instance.listVoices();
      if (!mounted) return;
      setState(() => _voices = list);
      _report('Found ${list.length} voice${list.length == 1 ? '' : 's'}.');
    } on ElevenLabsException catch (e) {
      // A TTS-only key can't list voices; that's fine, the id can be typed.
      _report('${e.message}  Paste a voice ID from the dashboard instead.',
          error: true);
    } catch (e) {
      _report('$e', error: true);
    }
  }

  Future<void> _clearCache() async {
    await ElevenLabsService.instance.clearCache();
    final size = await ElevenLabsService.instance.cacheSize();
    if (mounted) {
      setState(() => _cacheBytes = size);
      _report('Cleared cached narration audio.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(narrationModeProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Stories are narrated by ElevenLabs, which needs the API key below. '
          'This is the ONLY thing that spends credits — tapping a word, the '
          'flashcard answer and the word page all use the free local voice.',
          style: GoogleFonts.inter(
            color: AppColors.mutedInk(context),
            fontSize: 12.5,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        _ModePicker(
          mode: mode,
          onChanged: (m) => ref.read(narrationModeProvider.notifier).set(m),
        ),
        const SizedBox(height: 16),
        TextField(
            controller: _key,
            obscureText: _obscure,
            autocorrect: false,
            enableSuggestions: false,
            style: GoogleFonts.inter(fontSize: 13),
            decoration: InputDecoration(
              labelText: 'ElevenLabs API key',
              hintText: 'sk_…',
              helperText: 'Stored only on this device — never in the project',
              helperStyle: GoogleFonts.inter(fontSize: 11),
              suffixIcon: IconButton(
                tooltip: _obscure ? 'Show' : 'Hide',
                icon: Icon(
                  _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  size: 18,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _voice,
            autocorrect: false,
            style: GoogleFonts.inter(fontSize: 13),
            decoration: const InputDecoration(
              labelText: 'Voice ID',
              helperText: 'Any voice works with a multilingual model',
            ),
          ),
          if (_voices.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final v in _voices)
                  ActionChip(
                    label: Text(v.name),
                    onPressed: () => setState(() => _voice.text = v.id),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          _ModelPicker(onChanged: (m) => ElevenLabsService.instance.save(modelId: m)),
          const SizedBox(height: 8),
          _SpeedSlider(
            value: _speed,
            onChanged: (v) => setState(() => _speed = v),
            onSettled: (v) => ElevenLabsService.instance.save(speed: v),
          ),
          const SizedBox(height: 4),
          _StabilitySlider(
            value: _stability,
            onChanged: (v) => setState(() => _stability = v),
            onSettled: (v) => ElevenLabsService.instance.save(stability: v),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              GoldButton(
                label: _busy ? 'Working…' : 'Save',
                icon: Icons.save_outlined,
                onPressed: _busy ? null : _save,
              ),
              GoldOutlinedButton(
                label: 'Test key',
                icon: Icons.graphic_eq,
                onPressed: _busy ? null : _testKey,
              ),
              GoldOutlinedButton(
                label: 'Fetch voices',
                icon: Icons.record_voice_over_outlined,
                onPressed: _busy ? null : _fetchVoices,
              ),
            ],
          ),
          if (_status != null) ...[
            const SizedBox(height: 12),
            Text(
              _status!,
              style: GoogleFonts.inter(
                color: _statusIsError ? AppColors.softRed : AppColors.softGreen,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Cached narration: ${(_cacheBytes / 1024).toStringAsFixed(0)} KB. '
                  'Clips are reused, so replaying a story is free and works offline.',
                  style: GoogleFonts.inter(
                    color: AppColors.mutedInk(context),
                    fontSize: 11.5,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              TonalIconButton(
                icon: Icons.delete_sweep_outlined,
                tooltip: 'Clear cached audio',
                onPressed: _busy ? null : _clearCache,
              ),
            ],
          ),
      ],
    );
  }
}

/// Whole story vs one sentence at a time. Mirrors the toggle on each story
/// card — same setting, reachable from either place.
class _ModePicker extends StatelessWidget {
  const _ModePicker({required this.mode, required this.onChanged});
  final NarrationMode mode;
  final ValueChanged<NarrationMode> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget tab(NarrationMode value, String label, String sub) {
      final active = value == mode;
      return Expanded(
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.xs),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.xs),
            onTap: () => onChanged(value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              decoration: BoxDecoration(
                color: active ? AppColors.surface(context) : null,
                borderRadius: BorderRadius.circular(AppRadius.xs),
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
                children: [
                  Text(
                    label,
                    style: GoogleFonts.notoSerifKr(
                      color: active
                          ? AppColors.deepGold
                          : AppColors.mutedInk(context),
                      fontSize: 13,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: AppColors.mutedInk(context),
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.inset(context),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.hairline(context)),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          tab(NarrationMode.whole, '전체 재생', 'read straight through'),
          tab(NarrationMode.sentence, '한 문장씩', 'stop after each sentence'),
        ],
      ),
    );
  }
}

class _ModelPicker extends StatefulWidget {
  const _ModelPicker({required this.onChanged});
  final ValueChanged<String> onChanged;

  @override
  State<_ModelPicker> createState() => _ModelPickerState();
}

class _ModelPickerState extends State<_ModelPicker> {
  String? _model;

  @override
  void initState() {
    super.initState();
    ElevenLabsService.instance.modelId().then((m) {
      if (mounted) setState(() => _model = m);
    });
  }

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: _model,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Model'),
      items: [
        for (final e in ElevenLabsService.models.entries)
          DropdownMenuItem(
            value: e.key,
            child: Text(e.value, style: GoogleFonts.inter(fontSize: 13)),
          ),
      ],
      onChanged: (v) {
        if (v == null) return;
        setState(() => _model = v);
        widget.onChanged(v);
      },
    );
  }
}

/// Pace for the narration voice. ElevenLabs treats this as a voice setting
/// rather than a playback rate, so the model performs the line more slowly
/// instead of the audio being stretched.
class _SpeedSlider extends StatelessWidget {
  const _SpeedSlider({
    required this.value,
    required this.onChanged,
    required this.onSettled,
  });

  final double value;
  final ValueChanged<double> onChanged;

  /// Saved only when the drag ends — writing on every tick would spam prefs.
  final ValueChanged<double> onSettled;

  String get _label {
    if (value < 0.8) return 'slow — easiest to follow';
    if (value < 0.95) return 'relaxed';
    if (value <= 1.05) return 'natural — native pace';
    return 'brisk';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Narration speed',
              style: GoogleFonts.inter(
                color: AppColors.ink(context),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${value.toStringAsFixed(2)}×  ·  $_label',
              style: GoogleFonts.inter(
                color: AppColors.mutedInk(context),
                fontSize: 11.5,
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: ElevenLabsService.minSpeed,
          max: ElevenLabsService.maxSpeed,
          divisions: 10,
          onChanged: onChanged,
          onChangeEnd: onSettled,
        ),
        Text(
          'Changing this re-synthesizes each line, since cached clips are '
          'stored per speed.',
          style: GoogleFonts.inter(
            color: AppColors.mutedInk(context),
            fontSize: 11,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

/// How tightly the delivery is pinned between sentences.
///
/// The low end lets the model reinterpret every line, which is what makes a
/// story wander in voice and tone; the high end keeps one performance across
/// the whole thing at the cost of some expressiveness.
class _StabilitySlider extends StatelessWidget {
  const _StabilitySlider({
    required this.value,
    required this.onChanged,
    required this.onSettled,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onSettled;

  String get _label {
    if (value >= 0.85) return 'very steady — least variation';
    if (value >= 0.6) return 'steady — one voice throughout';
    if (value >= 0.35) return 'balanced';
    return 'expressive — tone varies per line';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Voice consistency',
              style: GoogleFonts.inter(
                color: AppColors.ink(context),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '${(value * 100).round()}%  ·  $_label',
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  color: AppColors.mutedInk(context),
                  fontSize: 11.5,
                ),
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          divisions: 10,
          onChanged: onChanged,
          onChangeEnd: onSettled,
        ),
      ],
    );
  }
}
