import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';

/// The one card every settings block sits in.
///
/// Exists because there were four of these, hand-rolled in four files, with
/// slightly different padding, radii and margins. Nothing was wrong with any
/// of them individually; together they read as a page assembled by accident.
/// One card means a new setting cannot drift.
class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.child, this.padding});

  final Widget child;

  /// Override only for a card whose content brings its own edges, such as a
  /// full-width list.
  final EdgeInsets? padding;

  static const EdgeInsets defaultPadding = EdgeInsets.fromLTRB(16, 14, 16, 14);
  static const double radius = 14;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: padding ?? defaultPadding,
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.hairline(context)),
      ),
      child: child,
    );
  }
}

/// A setting's name, and the sentence explaining it.
///
/// Both were written out longhand at every call site, which is how three
/// different title sizes ended up on one page.
class SettingsHeading extends StatelessWidget {
  const SettingsHeading({super.key, required this.title, this.description});

  final String title;
  final String? description;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.inter(
            color: AppColors.ink(context),
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        if (description != null) ...[
          const SizedBox(height: 3),
          Text(
            description!,
            style: GoogleFonts.inter(
              color: AppColors.mutedInk(context),
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ],
    );
  }
}
