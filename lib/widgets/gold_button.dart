import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';

/// Shared press behaviour: a small, quick scale-down while held. Modern
/// touch UI reads as "physical" mostly because of this one detail.
class _PressScale extends StatefulWidget {
  const _PressScale({
    required this.onPressed,
    required this.borderRadius,
    required this.child,
  });

  final VoidCallback? onPressed;
  final BorderRadius borderRadius;
  final Widget child;

  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale> {
  bool _down = false;

  void _set(bool v) {
    if (widget.onPressed == null || _down == v) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _down ? 0.972 : 1.0,
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOut,
      child: Material(
        color: Colors.transparent,
        borderRadius: widget.borderRadius,
        child: InkWell(
          borderRadius: widget.borderRadius,
          onTap: widget.onPressed,
          onTapDown: (_) => _set(true),
          onTapUp: (_) => _set(false),
          onTapCancel: () => _set(false),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Filled gold-gradient CTA.
class GoldButton extends StatelessWidget {
  const GoldButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expanded = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    final radius = BorderRadius.circular(AppRadius.sm);
    // Disabled used to be champagne-on-white with white text — unreadable.
    // Now it's a flat inset surface with muted ink, like every other
    // disabled control in the app.
    final fg = disabled ? AppColors.mutedInk(context) : Colors.white;

    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 15),
      decoration: BoxDecoration(
        gradient: disabled ? null : AppColors.goldGradient,
        color: disabled ? AppColors.inset(context) : null,
        borderRadius: radius,
        border: disabled
            ? Border.all(color: AppColors.hairline(context))
            : null,
        boxShadow: disabled
            ? null
            : const [
                BoxShadow(
                  color: Color(0x2EA8873E),
                  blurRadius: 16,
                  offset: Offset(0, 6),
                ),
              ],
      ),
      child: Row(
        mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, color: fg, size: 18),
            const SizedBox(width: 9),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                color: fg,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
                fontSize: 14.5,
              ),
            ),
          ),
        ],
      ),
    );

    return _PressScale(
      onPressed: onPressed,
      borderRadius: radius,
      child: content,
    );
  }
}

/// Outlined secondary button — now a soft tonal button: gold text on a faint
/// gold wash, with a hairline instead of a heavy 1.2 px gold outline.
class GoldOutlinedButton extends StatelessWidget {
  const GoldOutlinedButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    final radius = BorderRadius.circular(AppRadius.sm);
    final fg = disabled ? AppColors.mutedInk(context) : AppColors.deepGold;

    return _PressScale(
      onPressed: onPressed,
      borderRadius: radius,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        decoration: BoxDecoration(
          color: disabled
              ? AppColors.inset(context)
              : AppColors.goldTint(context),
          borderRadius: radius,
          border: Border.all(
            color: disabled
                ? AppColors.hairline(context)
                : AppColors.antiqueGold.withValues(alpha: 0.55),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, color: fg, size: 17),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  color: fg,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.1,
                  fontSize: 13.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hairline divider with a central ◆.
class GoldDiamondDivider extends StatelessWidget {
  const GoldDiamondDivider({super.key, this.padding = 16});
  final double padding;

  @override
  Widget build(BuildContext context) {
    final line = AppColors.hairline(context);
    // Fades out towards the ends so the rule doesn't box the content in.
    Widget rule(bool leftToRight) => Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: leftToRight ? Alignment.centerLeft : Alignment.centerRight,
                end: leftToRight ? Alignment.centerRight : Alignment.centerLeft,
                colors: [line.withValues(alpha: 0), line],
              ),
            ),
          ),
        );

    return Padding(
      padding: EdgeInsets.symmetric(vertical: padding),
      child: Row(
        children: [
          rule(true),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              '◆',
              style: TextStyle(color: AppColors.antiqueGold, fontSize: 9),
            ),
          ),
          rule(false),
        ],
      ),
    );
  }
}

/// Compact circular icon button used for card-level actions. Reads as a
/// modern tonal icon button instead of a bare Material IconButton.
class TonalIconButton extends StatelessWidget {
  const TonalIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.color,
    this.size = 18,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.mutedInk(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: size, color: c),
          ),
        ),
      ),
    );
  }
}
