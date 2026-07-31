/// The daily puzzle.
///
/// PURE DART — no Flutter imports.
///
/// Derived from a hash of the CALENDAR DATE, so every player worldwide gets
/// the same puzzle with no server, no account and no network. The app stays
/// 100% offline, which for this audience is a feature: patchy wifi, data caps,
/// and a well-founded suspicion of anything asking them to sign in.
library;

import '../engine/hitori_engine.dart';
import '../engine/generator.dart';

class DailyPuzzle {
  /// Stable 31-bit hash of y/m/d.
  ///
  /// Hand-rolled deliberately: `Object.hash` and `String.hashCode` are
  /// explicitly NOT stable across Dart versions or platforms, so either would
  /// silently change everyone's puzzle on an SDK bump.
  static int seedForDate(DateTime d) {
    var h = 2166136261;
    for (final v in [d.year, d.month, d.day]) {
      h ^= v;
      h = (h * 16777619) & 0x7FFFFFFF;
    }
    return h == 0 ? 1 : h;
  }

  /// Newspaper convention: gentle at the start of the week, hardest on
  /// Saturday, and Sunday eases off so a weekly player is not left on a cliff
  /// edge.
  static Difficulty difficultyForDate(DateTime d) {
    switch (d.weekday) {
      case DateTime.monday:
      case DateTime.tuesday:
        return Difficulty.gentle;
      case DateTime.wednesday:
      case DateTime.thursday:
        return Difficulty.easy;
      case DateTime.friday:
        return Difficulty.medium;
      case DateTime.saturday:
        return Difficulty.hard;
      default:
        return Difficulty.easy;
    }
  }

  static Puzzle forDate(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return Generator(seedForDate(d)).generate(difficultyForDate(d));
  }

  static Puzzle practice({required Difficulty difficulty, required int seed}) =>
      Generator(seed).generate(difficulty);
}
