/// Widget + state tests. These assert the ACCESSIBILITY and CORRECTNESS
/// guarantees, not just that widgets render.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:large_print_hitori/engine/hitori_engine.dart';
import 'package:large_print_hitori/engine/generator.dart';
import 'package:large_print_hitori/models/game_state.dart';
import 'package:large_print_hitori/services/settings.dart';
import 'package:large_print_hitori/services/progress.dart';
import 'package:large_print_hitori/services/daily_puzzle.dart';
import 'package:large_print_hitori/services/ads.dart';
import 'package:large_print_hitori/services/audio.dart';
import 'package:large_print_hitori/widgets/app_theme.dart';
import 'package:large_print_hitori/widgets/hitori_board.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Settings defaults', () {
    test('opens large with the helpers on', () async {
      final s = Settings();
      await s.load();
      // The app OPENS large. Shipping at 1.0 and expecting people to find a
      // settings screen is the mistake every competitor makes.
      expect(s.fontScale, 1.15);
      expect(s.showMistakes, isTrue);
      expect(s.highlightLine, isTrue);
      expect(s.autoCircle, isTrue);
      expect(s.seenTutorial, isFalse);
    });

    test('font scale clamps to a legible range', () async {
      final s = Settings();
      await s.load();
      await s.setFontScale(9.0);
      expect(s.fontScale, 1.6);
      await s.setFontScale(0.0);
      expect(s.fontScale, 0.85);
    });

    test('preferences survive a reload', () async {
      final s = Settings();
      await s.load();
      await s.setAutoCircle(false);
      await s.setDarkMode(true);
      await s.setFontScale(1.35);
      final again = Settings();
      await again.load();
      expect(again.autoCircle, isFalse);
      expect(again.darkMode, isTrue);
      expect(again.fontScale, 1.35);
    });
  });

  group('Audio', () {
    test('music is opt-in, sound effects are on', () async {
      final s = Settings();
      await s.load();
      expect(s.music, isFalse);
      expect(s.sound, isTrue);
    });

    test('audio preferences persist', () async {
      final s = Settings();
      await s.load();
      await s.setMusic(true);
      await s.setSound(false);
      final again = Settings();
      await again.load();
      expect(again.music, isTrue);
      expect(again.sound, isFalse);
    });

    test('the silent fallback never throws without a platform', () {
      final a = AudioService.silent();
      expect(a.isReady, isFalse);
      for (final s in Sfx.values) {
        a.play(s);
      }
      expect(a.playShade, returnsNormally);
      expect(a.dispose, returnsNormally);
    });

    test('every sound maps to a declared asset path', () {
      for (final s in Sfx.values) {
        expect(s.path, startsWith('sfx/'));
        expect(s.path, endsWith('.ogg'));
      }
      for (final m in Music.values) {
        expect(m.path, startsWith('music/'));
        expect(m.path, endsWith('.ogg'));
      }
    });

    test('a paid-up player is never shown a rewarded ad', () async {
      final s = Settings();
      await s.load();
      await s.setAdFree(true);
      final ads = AdService(s);
      expect(await ads.showRewarded(), isTrue);
    });
  });

  group('Progress', () {
    test('streak counts consecutive days and persists', () async {
      final p = Progress();
      await p.load();
      final today = DateTime.now();
      await p.markComplete(today, seconds: 120, difficultyKey: 'Easy');
      await p.markComplete(today.subtract(const Duration(days: 1)),
          seconds: 100, difficultyKey: 'Easy');
      expect(p.currentStreak, 2);

      final again = Progress();
      await again.load();
      expect(again.currentStreak, 2);
      expect(again.totalPuzzles, 2);
    });

    test('a gap breaks the streak', () async {
      final p = Progress();
      await p.load();
      final today = DateTime.now();
      await p.markComplete(today, seconds: 10, difficultyKey: 'Easy');
      await p.markComplete(today.subtract(const Duration(days: 4)),
          seconds: 10, difficultyKey: 'Easy');
      expect(p.currentStreak, 1);
    });

    test('best times only improve', () async {
      final p = Progress();
      await p.load();
      await p.recordPractice(300, 'Medium');
      await p.recordPractice(500, 'Medium');
      expect(p.bestTimes['Medium'], 300);
      await p.recordPractice(200, 'Medium');
      expect(p.bestTimes['Medium'], 200);
    });
  });

  group('GameState', () {
    GameState fresh([Difficulty d = Difficulty.gentle]) =>
        GameState(Generator(4242).generate(d));

    test('a new game starts unmarked', () {
      final g = fresh();
      expect(g.marks.every((m) => m == kMarkNone), isTrue);
      expect(g.canUndo, isFalse);
      expect(g.isSolved, isFalse);
    });

    test('shading a cell that should stay is a mistake', () {
      final g = fresh();
      final keep = List.generate(g.puzzle.cellCount, (i) => i)
          .firstWhere((i) => g.puzzle.solution[i] == kKeep);
      g.tool = Tool.shade;
      expect(g.apply(keep), isTrue);
      expect(g.mistakes, 1);
      expect(g.isWrong(keep), isTrue);
    });

    test('ringing a cell that should be shaded is a mistake', () {
      final g = fresh();
      final shade = List.generate(g.puzzle.cellCount, (i) => i)
          .firstWhere((i) => g.puzzle.solution[i] == kShade);
      g.tool = Tool.circle;
      expect(g.apply(shade), isTrue);
      expect(g.mistakes, 1);
    });

    test('tapping the same cell twice clears it', () {
      final g = fresh();
      g.tool = Tool.shade;
      g.apply(0);
      expect(g.marks[0], kMarkShade);
      g.apply(0);
      expect(g.marks[0], kMarkNone);
    });

    test('shading exactly the right cells solves the puzzle', () {
      final g = fresh();
      for (var i = 0; i < g.puzzle.cellCount; i++) {
        if (g.puzzle.solution[i] == kShade) g.setMark(i, kMarkShade);
      }
      expect(g.isSolved, isTrue);
      expect(g.mistakes, 0);
    });

    test('leaving cells un-ringed still counts as solved', () {
      // Demanding bookkeeping the player did not need is the kind of pedantry
      // that gets an app uninstalled.
      final g = fresh();
      for (var i = 0; i < g.puzzle.cellCount; i++) {
        if (g.puzzle.solution[i] == kShade) g.setMark(i, kMarkShade);
      }
      expect(g.marks.any((m) => m == kMarkNone), isTrue);
      expect(g.isSolved, isTrue);
    });

    test('auto-ringing neighbours never marks a wrong cell', () {
      // The no-touching rule makes these forced, so they can never be wrong.
      final g = fresh(Difficulty.medium);
      for (var i = 0; i < g.puzzle.cellCount; i++) {
        if (g.puzzle.solution[i] == kShade) g.setMark(i, kMarkShade);
      }
      final marked = g.autoCircleNeighbours();
      expect(marked, isNotEmpty);
      for (final i in marked) {
        expect(g.isWrong(i), isFalse,
            reason: 'auto-ring marked a cell that should be shaded');
      }
    });

    test('auto-ringing undoes as ONE action', () {
      final g = fresh(Difficulty.medium);
      final shadeAt = List.generate(g.puzzle.cellCount, (i) => i)
          .firstWhere((i) => g.puzzle.solution[i] == kShade);
      final before = List<int>.of(g.marks);
      g.setMark(shadeAt, kMarkShade);
      final ringed = g.autoCircleNeighbours();
      expect(ringed.length, greaterThanOrEqualTo(2));
      g.groupWithPrevious(ringed);
      g.undo();
      expect(g.marks, before,
          reason: 'one undo press did not clear the whole action');
    });

    test('clearing mistakes removes only the wrong marks', () {
      final g = fresh();
      final keep = List.generate(g.puzzle.cellCount, (i) => i)
          .firstWhere((i) => g.puzzle.solution[i] == kKeep);
      final shade = List.generate(g.puzzle.cellCount, (i) => i)
          .firstWhere((i) => g.puzzle.solution[i] == kShade);
      g.setMark(shade, kMarkShade); // right
      g.setMark(keep, kMarkShade); // wrong
      expect(g.hasMistakes, isTrue);
      final n = g.clearMistakes();
      expect(n, 1);
      expect(g.marks[shade], kMarkShade);
      expect(g.marks[keep], kMarkNone);
      expect(g.hasMistakes, isFalse);
    });

    test('save and restore round-trips exactly', () {
      final g = fresh();
      g.tool = Tool.circle;
      g.setMark(0, kMarkCircle);
      g.elapsedSeconds = 321;
      g.hintsUsed = 2;

      final back = GameState.decode(g.encode());
      expect(back, isNotNull);
      expect(back!.marks, g.marks);
      expect(back.elapsedSeconds, 321);
      expect(back.hintsUsed, 2);
      expect(back.tool, Tool.circle);
      expect(back.puzzle.numbers, g.puzzle.numbers);
    });

    test('a corrupt save returns null instead of throwing', () {
      expect(GameState.decode('not json'), isNull);
      expect(GameState.decode('{"v":1}'), isNull);
      expect(GameState.decode('{"v":1,"p":{"n":3},"m":[0]}'), isNull);
    });
  });

  group('Daily puzzle', () {
    test('is the same all day regardless of the clock', () {
      final a = DailyPuzzle.forDate(DateTime(2026, 7, 30, 0, 1));
      final b = DailyPuzzle.forDate(DateTime(2026, 7, 30, 23, 58));
      expect(a.numbers, b.numbers);
      expect(a.solution, b.solution);
    });

    test('consecutive days differ', () {
      final a = DailyPuzzle.forDate(DateTime(2026, 7, 30));
      final b = DailyPuzzle.forDate(DateTime(2026, 7, 31));
      expect(a.numbers == b.numbers, isFalse);
    });

    test('weekday ramp follows newspaper convention', () {
      expect(DailyPuzzle.difficultyForDate(DateTime(2026, 7, 27)).label,
          'Gentle'); // Monday
      expect(DailyPuzzle.difficultyForDate(DateTime(2026, 8, 1)).label,
          'Hard'); // Saturday
      expect(DailyPuzzle.difficultyForDate(DateTime(2026, 8, 2)).label,
          'Easy'); // Sunday eases off
    });

    test('a month of dailies all generate and stay unique', () {
      for (var day = 1; day <= 28; day++) {
        final p = DailyPuzzle.forDate(DateTime(2026, 3, day));
        final n = Solver(p.numbers, p.size)
            .countSolutions(List<int>.filled(p.cellCount, kUnknown));
        expect(n, 1, reason: 'March $day has $n solutions');
      }
    });
  });

  group('Theme accessibility', () {
    test('buttons meet a 56dp minimum target', () {
      final t = AppTheme.light();
      final size =
          t.filledButtonTheme.style?.minimumSize?.resolve({}) ?? Size.zero;
      expect(size.height, greaterThanOrEqualTo(56));
    });

    test('high contrast is pure black on white', () {
      final t = AppTheme.light(highContrast: true);
      expect(t.colorScheme.surface, Colors.white);
      expect(t.colorScheme.onSurface, const Color(0xFF000000));
    });

    test('the number on a shaded cell stays readable', () {
      // Players re-check what they shaded constantly. If the number vanishes
      // they have to undo just to look, which is a design failure.
      for (final scheme in [
        AppTheme.light().colorScheme,
        AppTheme.dark().colorScheme,
      ]) {
        final ratio = _contrast(
            AppTheme.onShaded(scheme), AppTheme.shadedCell(scheme));
        expect(ratio, greaterThan(4.5),
            reason: 'number on shaded cell is only '
                '${ratio.toStringAsFixed(1)}:1');
      }
    });

    test('the keep ring differs in HUE from the shading', () {
      // Not just in lightness: the two states must survive colour-blindness.
      final s = AppTheme.light().colorScheme;
      final shade = HSLColor.fromColor(AppTheme.shadedCell(s));
      final ring = HSLColor.fromColor(AppTheme.circleColour(s));
      expect((shade.hue - ring.hue).abs(), greaterThan(40));
    });
  });

  group('Board widget', () {
    testWidgets('renders and reports the tapped cell', (tester) async {
      final g = GameState(Generator(5).generate(Difficulty.gentle));
      int? tapped;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              height: 360,
              child: HitoriBoard(game: g, onCell: (i) => tapped = i),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(HitoriBoard), findsOneWidget);
      final box = tester.getRect(find.byType(HitoriBoard));
      await tester.tapAt(box.center);
      await tester.pump();
      expect(tapped, isNotNull);
      expect(tapped, inInclusiveRange(0, g.puzzle.cellCount - 1));
    });

    testWidgets('renders in high contrast without throwing', (tester) async {
      final g = GameState(Generator(9).generate(Difficulty.hard));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 340,
            height: 340,
            child: HitoriBoard(
                game: g,
                highContrast: true,
                onCell: (_) {}),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}

/// WCAG relative luminance contrast ratio.
double _contrast(Color a, Color b) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();

  double lum(Color c) =>
      0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);

  final la = lum(a), lb = lum(b);
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
