import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/storage_service.dart';
import '../theme/app_colors.dart';

/// Shown instead of the app when the data files are held open elsewhere.
///
/// The alternative — starting on empty stand-in boxes — is indistinguishable
/// from having lost everything, and that is exactly how it feels. Refusing to
/// start, and saying why, is the kinder failure: the words are safe, the app
/// simply cannot have them at this moment.
class LockedScreen extends StatefulWidget {
  const LockedScreen({super.key, required this.onRetry});

  /// Re-runs startup. Called after a successful re-open.
  final VoidCallback onRetry;

  @override
  State<LockedScreen> createState() => _LockedScreenState();
}

class _LockedScreenState extends State<LockedScreen> {
  bool _retrying = false;
  bool _failedAgain = false;

  Future<void> _retry() async {
    setState(() {
      _retrying = true;
      _failedAgain = false;
    });
    await StorageService.instance.init();
    if (!mounted) return;
    if (StorageService.instance.lockedOut) {
      setState(() {
        _retrying = false;
        _failedAgain = true;
      });
      return;
    }
    widget.onRetry();
  }

  @override
  Widget build(BuildContext context) {
    final dir = StorageService.instance.storageDirectory;

    return Scaffold(
      backgroundColor: AppColors.onyx,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.onyxLift,
                      ),
                      child: const Icon(Icons.lock_outline,
                          color: AppColors.antiqueGold, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'Maldari is already open',
                        style: GoogleFonts.playfairDisplay(
                          color: AppColors.ivory,
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Text(
                  'Another copy of the app has your vocabulary open, so this '
                  'one cannot read it.',
                  style: GoogleFonts.inter(
                    color: AppColors.cream,
                    fontSize: 14,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  decoration: BoxDecoration(
                    color: AppColors.onyxLift,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(
                        color: AppColors.antiqueGold.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.verified_outlined,
                              size: 15, color: AppColors.antiqueGold),
                          const SizedBox(width: 8),
                          Text(
                            'Your words are safe',
                            style: GoogleFonts.inter(
                              color: AppColors.ivory,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Nothing has been changed or deleted. This app refuses '
                        'to start on empty files rather than show you an empty '
                        'collection.',
                        style: GoogleFonts.inter(
                          color: AppColors.mutedCream,
                          fontSize: 12,
                          height: 1.55,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'To fix it',
                  style: GoogleFonts.inter(
                    color: AppColors.antiqueGold,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 8),
                _step(context, '1', 'Close every other Maldari window.'),
                _step(context, '2',
                    'If one was launched from an editor, stop it there too — '
                    'closing the editor does not always end the app.'),
                _step(context, '3',
                    'Check Task Manager for a leftover maldari.exe and end it.'),
                _step(context, '4', 'Then press Try again.'),
                if (dir != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Your data lives in\n$dir',
                    style: GoogleFonts.robotoMono(
                      color: AppColors.mutedCream,
                      fontSize: 10.5,
                      height: 1.5,
                    ),
                  ),
                ],
                if (_failedAgain) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Still locked. The other copy is likely still running.',
                    style: GoogleFonts.inter(
                      color: AppColors.softRed,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _retrying ? null : _retry,
                    icon: _retrying
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh, size: 17),
                    label: Text(
                      _retrying ? 'Checking…' : 'Try again',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.antiqueGold,
                      foregroundColor: AppColors.onyx,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 22, vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _step(BuildContext context, String n, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$n.',
              style: GoogleFonts.inter(
                color: AppColors.antiqueGold,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: GoogleFonts.inter(
                  color: AppColors.cream,
                  fontSize: 12.5,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      );
}
