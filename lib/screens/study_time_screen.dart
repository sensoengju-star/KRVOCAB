import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/study_time_service.dart';
import '../theme/app_colors.dart';

/// This week's study time: the daily average, today so far, and a bar per
/// day against the 30-minute goal.
class StudyTimeScreen extends StatelessWidget {
  const StudyTimeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final svc = StudyTimeService.instance;
    // Rebuilds each counted second, so the numbers move while you work — the
    // point of looking at this is to see it happen.
    return ListenableBuilder(
      listenable: svc,
      builder: (context, _) {
        final avg = svc.averagePerDay;
        final week = svc.week();
        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 110),
          children: [
            _AverageCard(
              average: avg,
              days: svc.daysTracked,
              today: svc.today,
              counting: svc.isCounting,
            ),
            const SizedBox(height: 14),
            if (svc.meetsGoal) const _Encouragement(),
            if (svc.meetsGoal) const SizedBox(height: 14),
            _WeekChart(week: week, goal: StudyTimeService.dailyGoal),
            const SizedBox(height: 18),
            _Footnote(),
          ],
        );
      },
    );
  }
}

String _format(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  if (h > 0) return m == 0 ? '${h}h' : '${h}h ${m}m';
  if (d.inMinutes > 0) return '${d.inMinutes} min';
  return d.inSeconds > 0 ? '<1 min' : '0 min';
}

class _AverageCard extends StatelessWidget {
  const _AverageCard({
    required this.average,
    required this.days,
    required this.today,
    required this.counting,
  });

  final Duration average;
  final int days;
  final Duration today;
  final bool counting;

  @override
  Widget build(BuildContext context) {
    const goal = StudyTimeService.dailyGoal;
    final progress =
        (average.inSeconds / goal.inSeconds).clamp(0.0, 1.0).toDouble();

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
      decoration: BoxDecoration(
        gradient: AppColors.chromeGradient,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppColors.cardShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'AVERAGE PER DAY',
            style: GoogleFonts.inter(
              color: AppColors.antiqueGold,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _format(average),
            style: GoogleFonts.playfairDisplay(
              color: AppColors.ivory,
              fontSize: 44,
              fontWeight: FontWeight.w600,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            days == 1
                ? 'over today — tracking began today'
                : 'over the last $days days',
            style: GoogleFonts.inter(
              color: AppColors.mutedCream,
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: AppColors.onyxEdge,
              valueColor: const AlwaysStoppedAnimation(AppColors.antiqueGold),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            progress >= 1
                ? 'Past the ${goal.inMinutes}-minute daily goal'
                : '${_format(goal - average)} a day short of '
                    '${goal.inMinutes} minutes',
            style: GoogleFonts.inter(
              color: AppColors.mutedCream,
              fontSize: 11.5,
            ),
          ),
          const Divider(height: 28, color: AppColors.onyxEdge),
          Row(
            children: [
              // A live dot, so it is obvious whether this very moment counts.
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: counting
                      ? const Color(0xFF6FBF8B)
                      : AppColors.mutedCream.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Today  ',
                style: GoogleFonts.inter(
                  color: AppColors.mutedCream,
                  fontSize: 13,
                ),
              ),
              Text(
                _format(today),
                style: GoogleFonts.inter(
                  color: AppColors.ivory,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                counting ? 'counting' : 'paused',
                style: GoogleFonts.inter(
                  color: AppColors.mutedCream,
                  fontSize: 11.5,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Encouragement extends StatelessWidget {
  const _Encouragement();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.goldTint(context),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border:
            Border.all(color: AppColors.antiqueGold.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Text('🔥', style: TextStyle(fontSize: 26)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Keep up the good work!',
                  style: GoogleFonts.playfairDisplay(
                    color: AppColors.ink(context),
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'You are averaging more than 30 minutes a day. That is '
                  'the kind of steady practice that makes words stick.',
                  style: GoogleFonts.inter(
                    color: AppColors.mutedInk(context),
                    fontSize: 12.5,
                    height: 1.45,
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

class _WeekChart extends StatelessWidget {
  const _WeekChart({required this.week, required this.goal});

  final List<({DateTime day, Duration time})> week;
  final Duration goal;

  static const _names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    // Scale to whichever is larger, the goal or the best day, so the goal line
    // always sits on the chart and a big day never runs off the top.
    final most = week.fold<int>(0, (m, d) => d.time.inSeconds > m ? d.time.inSeconds : m);
    final ceiling = (most > goal.inSeconds ? most : goal.inSeconds) * 1.12;
    const chartHeight = 170.0;
    final goalY = chartHeight * (goal.inSeconds / ceiling);

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.hairline(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This week',
            style: GoogleFonts.playfairDisplay(
              color: AppColors.ink(context),
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: chartHeight + 34,
            child: Stack(
              children: [
                // The goal, drawn across every bar.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 34 + goalY,
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 1,
                          color: AppColors.antiqueGold.withValues(alpha: 0.55),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${goal.inMinutes}m',
                        style: GoogleFonts.inter(
                          color: AppColors.antiqueGold,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < week.length; i++)
                      Expanded(
                        child: _Bar(
                          label: _names[week[i].day.weekday - 1],
                          time: week[i].time,
                          height: chartHeight *
                              (week[i].time.inSeconds / ceiling),
                          isToday: i == week.length - 1,
                          metGoal: week[i].time >= goal,
                        ),
                      ),
                    const SizedBox(width: 28),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.label,
    required this.time,
    required this.height,
    required this.isToday,
    required this.metGoal,
  });

  final String label;
  final Duration time;
  final double height;
  final bool isToday;
  final bool metGoal;

  @override
  Widget build(BuildContext context) {
    final color = metGoal
        ? AppColors.antiqueGold
        : AppColors.antiqueGold.withValues(alpha: isToday ? 0.55 : 0.32);

    return Tooltip(
      message: _format(time),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (time.inMinutes > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${time.inMinutes}',
                style: GoogleFonts.inter(
                  color: AppColors.mutedInk(context),
                  fontSize: 10,
                ),
              ),
            ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            // A sliver even at zero, so an empty day reads as "nothing" rather
            // than as a missing column.
            height: height < 3 ? 3 : height,
            margin: const EdgeInsets.symmetric(horizontal: 7),
            decoration: BoxDecoration(
              color: color,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(6)),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.inter(
              color: isToday ? AppColors.ink(context) : AppColors.mutedInk(context),
              fontSize: 11,
              fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _Footnote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Text(
      'Counted only while this window is in front and you are using it — the '
      'clock stops after ${StudyTimeService.idleAfter.inMinutes} minutes '
      'without a click, scroll or key, and never runs while the app sits in '
      'the tray. Each day is kept for a week, then deleted.',
      style: GoogleFonts.inter(
        color: AppColors.mutedInk(context),
        fontSize: 11.5,
        height: 1.55,
      ),
    );
  }
}
