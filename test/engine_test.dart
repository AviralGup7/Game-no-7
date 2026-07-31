/// Engine tests.
///
/// The first group asserts the two invariants the whole product rests on. If
/// either fails, the app is shipping puzzles that are unfair or unsolvable,
/// which is worse than shipping nothing.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:large_print_hitori/engine/hitori_engine.dart';
import 'package:large_print_hitori/engine/generator.dart';
import 'package:large_print_hitori/engine/hints.dart';

List<int> _blank(int cells) => List<int>.filled(cells, kUnknown);

void main() {
  group('the two critical invariants', () {
    test('every generated puzzle has EXACTLY one solution', () {
      for (final d in Difficulty.all) {
        for (var seed = 1; seed <= 10; seed++) {
          final p = Generator(seed * 7919).generate(d);
          final n =
              Solver(p.numbers, p.size).countSolutions(_blank(p.cellCount));
          expect(n, 1, reason: '${d.label} seed $seed has $n solutions');
        }
      }
    });

    test('every generated puzzle is solvable WITHOUT guessing', () {
      // Strictly stronger than uniqueness, and the one players feel. A puzzle
      // that needs trial and error is, to the person holding the phone,
      // indistinguishable from a broken app.
      for (final d in Difficulty.all) {
        for (var seed = 1; seed <= 10; seed++) {
          final p = Generator(seed * 104729).generate(d);
          final s = Solver(p.numbers, p.size).solveByLogic(_blank(p.cellCount));
          expect(s, isNotNull, reason: '${d.label} seed $seed contradicts');
          expect(s!.contains(kUnknown), isFalse,
              reason: '${d.label} seed $seed needs guessing');
        }
      }
    });

    test('logic reaches the intended solution, not a different one', () {
      for (final d in Difficulty.all) {
        final p = Generator(31337).generate(d);
        final s = Solver(p.numbers, p.size).solveByLogic(_blank(p.cellCount))!;
        for (var i = 0; i < p.cellCount; i++) {
          expect(s[i], p.solution[i], reason: 'cell $i of ${d.label}');
        }
      }
    });

    test('the stored solution satisfies all three rules', () {
      for (final d in Difficulty.all) {
        for (var seed = 1; seed <= 8; seed++) {
          final p = Generator(seed * 6151).generate(d);
          expect(checkComplete(p.numbers, p.solution, p.size), Violation.none,
              reason: '${d.label} seed $seed');
        }
      }
    });
  });

  group('rule checking', () {
    test('two shaded cells side by side is rejected', () {
      final nums = [1, 2, 1, 2];
      final state = [kShade, kShade, kKeep, kKeep];
      expect(checkComplete(nums, state, 2), Violation.adjacentShaded);
    });

    test('shaded cells touching only at a corner are allowed', () {
      // 2x2 with shading on one diagonal: corners touch, edges do not.
      // Both unshaded cells are on the other diagonal, which is NOT connected
      // by edges, so this must fail on connectivity - not on adjacency.
      final nums = [1, 2, 2, 1];
      final state = [kShade, kKeep, kKeep, kShade];
      expect(checkComplete(nums, state, 2), Violation.disconnected);
    });

    test('a duplicate unshaded number is rejected', () {
      final nums = [1, 1, 2, 3];
      final state = [kKeep, kKeep, kKeep, kKeep];
      expect(checkComplete(nums, state, 2), Violation.duplicate);
    });

    test('a split grid is rejected', () {
      // Shading the middle column of a 3x3 cuts left from right.
      final nums = [1, 2, 3, 4, 5, 6, 7, 8, 9];
      final state = [
        kKeep, kShade, kKeep,
        kKeep, kShade, kKeep,
        kKeep, kShade, kKeep,
      ];
      // Adjacency fires first because the shaded column touches itself.
      expect(checkComplete(nums, state, 3), Violation.adjacentShaded);
    });

    test('connectivity is detected independently of adjacency', () {
      // Corner cell isolated by two non-touching shaded cells.
      final nums = List<int>.generate(9, (i) => i + 1);
      final state = [
        kKeep, kShade, kKeep,
        kShade, kKeep, kKeep,
        kKeep, kKeep, kKeep,
      ];
      expect(isConnected(state, 3), isFalse,
          reason: 'the top-left cell is cut off');
    });

    test('an all-kept grid is trivially connected', () {
      expect(isConnected(List<int>.filled(16, kKeep), 4), isTrue);
    });
  });

  group('solver techniques', () {
    test('TRIPLE: three in a line forces the middle to stay', () {
      // 4 4 4 across the top row.
      final nums = [4, 4, 4, 1, 2, 3, 2, 3, 1];
      final s = Solver(nums, 3);
      final state = _blank(9);
      expect(s.propagate(state), isTrue);
      expect(state[1], kKeep, reason: 'middle of a triple must be kept');
      expect(state[0], kShade);
      expect(state[2], kShade);
    });

    test('SANDWICH: x y x forces the middle to stay', () {
      final nums = [3, 5, 3, 1, 2, 4, 2, 4, 1];
      final s = Solver(nums, 3);
      final state = _blank(9);
      expect(s.propagate(state), isTrue);
      expect(state[1], kKeep, reason: 'the filling of a sandwich stays');
    });

    test('a shaded cell forces its neighbours to stay', () {
      // Use a REAL generated puzzle. A hand-made grid of 1,2,3 repeating is
      // unsatisfiable, and propagate() correctly reports the contradiction -
      // which would test the fixture, not the rule.
      final p = Generator(77).generate(Difficulty.gentle);
      final s = Solver(p.numbers, p.size);
      final state = _blank(p.cellCount);
      final shadeAt = List.generate(p.cellCount, (i) => i)
          .firstWhere((i) => p.solution[i] == kShade);
      state[shadeAt] = kShade;
      expect(s.propagate(state), isTrue);

      final n = p.size;
      final r = shadeAt ~/ n, c = shadeAt % n;
      for (final j in [
        if (c > 0) shadeAt - 1,
        if (c + 1 < n) shadeAt + 1,
        if (r > 0) shadeAt - n,
        if (r + 1 < n) shadeAt + n,
      ]) {
        expect(state[j], kKeep, reason: 'neighbour of a shaded cell');
      }
    });

    test('two shaded neighbours is reported as a contradiction', () {
      final p = Generator(77).generate(Difficulty.gentle);
      final s = Solver(p.numbers, p.size);
      final state = _blank(p.cellCount);
      state[0] = kShade;
      state[1] = kShade;
      expect(s.propagate(state), isFalse);
    });

    test('countSolutions respects its limit', () {
      // A grid with many solutions must stop at the limit, not run forever.
      final nums = List<int>.filled(16, 1);
      final s = Solver(nums, 4);
      expect(s.countSolutions(_blank(16), limit: 2), lessThanOrEqualTo(2));
    });
  });

  group('generation', () {
    test('numbers are always within 1..n', () {
      for (final d in Difficulty.all) {
        final p = Generator(2024).generate(d);
        for (final v in p.numbers) {
          expect(v, inInclusiveRange(1, p.size));
        }
      }
    });

    test('a sensible fraction of cells is shaded', () {
      // Too few and the puzzle is trivial; too many and it stops being a grid.
      for (final d in Difficulty.all) {
        for (var seed = 1; seed <= 8; seed++) {
          final p = Generator(seed * 977).generate(d);
          final frac = p.shadedTarget / p.cellCount;
          expect(frac, greaterThan(0.10), reason: '${d.label} barely shaded');
          expect(frac, lessThan(0.45), reason: '${d.label} over-shaded');
        }
      }
    });

    test('the same seed gives the same puzzle', () {
      for (final d in Difficulty.all) {
        final a = Generator(9001).generate(d);
        final b = Generator(9001).generate(d);
        expect(a.numbers, b.numbers);
        expect(a.solution, b.solution);
      }
    });

    test('different seeds give different puzzles', () {
      final a = Generator(1).generate(Difficulty.easy);
      final b = Generator(2).generate(Difficulty.easy);
      expect(a.numbers == b.numbers, isFalse);
    });

    test('generation stays fast enough for the UI thread', () {
      final sw = Stopwatch()..start();
      for (var seed = 1; seed <= 12; seed++) {
        Generator(seed * 7919).generate(Difficulty.hard);
      }
      sw.stop();
      final per = sw.elapsedMilliseconds / 12;
      // Measured around 10-20 ms. 120 ms leaves wide margin for a slow phone
      // while still catching a real regression.
      expect(per, lessThan(120),
          reason: '${per}ms per puzzle would drop frames');
    });

    test('every difficulty produces a puzzle without throwing', () {
      for (final d in Difficulty.all) {
        for (var seed = 1; seed <= 20; seed++) {
          expect(() => Generator(seed * 31).generate(d), returnsNormally,
              reason: '${d.label} seed $seed');
        }
      }
    });
  });

  group('difficulty', () {
    test('names are plain and encouraging', () {
      expect(Difficulty.all.map((d) => d.label).toList(),
          ['Gentle', 'Easy', 'Medium', 'Hard']);
      for (final d in Difficulty.all) {
        expect(d.label.toLowerCase(),
            isNot(anyOf('expert', 'evil', 'insane', 'impossible')));
      }
    });

    test('grid size increases with difficulty', () {
      for (var i = 1; i < Difficulty.all.length; i++) {
        expect(Difficulty.all[i].size,
            greaterThan(Difficulty.all[i - 1].size));
      }
    });

    test('shade density stays in the range that yields unique puzzles', () {
      // Measured: below ~0.24 almost nothing comes out unique. See the table
      // on Difficulty.shadeTarget.
      for (final d in Difficulty.all) {
        expect(d.shadeTarget, greaterThanOrEqualTo(0.28), reason: d.label);
      }
    });
  });

  group('hints', () {
    test('a hint is offered from the opening position of every size', () {
      for (final d in Difficulty.all) {
        final p = Generator(555).generate(d);
        final h = nextHint(p, _blank(p.cellCount));
        expect(h, isNotNull, reason: d.label);
        expect(h!.message.length, greaterThan(40),
            reason: 'a hint must explain itself: ${h.message}');
      }
    });

    test('a hint is always correct', () {
      for (final d in Difficulty.all) {
        for (var seed = 1; seed <= 6; seed++) {
          final p = Generator(seed * 13).generate(d);
          final known = _blank(p.cellCount);
          for (var step = 0; step < 15; step++) {
            final h = nextHint(p, known);
            if (h == null) break;
            expect(h.value, p.solution[h.index],
                reason: 'hint contradicted the answer: ${h.message}');
            known[h.index] = h.value;
          }
        }
      }
    });

    test('hints can finish a whole puzzle', () {
      final p = Generator(1234).generate(Difficulty.gentle);
      final known = _blank(p.cellCount);
      var guard = 0;
      while (known.contains(kUnknown) && guard++ < 200) {
        final h = nextHint(p, known);
        if (h == null) break;
        known[h.index] = h.value;
      }
      expect(known.contains(kUnknown), isFalse);
      for (var i = 0; i < p.cellCount; i++) {
        expect(known[i], p.solution[i]);
      }
    });

    test('a mistake is pointed out before anything else', () {
      final p = Generator(88).generate(Difficulty.gentle);
      final known = _blank(p.cellCount);
      // Mark a cell the wrong way round.
      final target =
          List.generate(p.cellCount, (i) => i).firstWhere((i) => p.solution[i] == kKeep);
      known[target] = kShade;
      final h = nextHint(p, known);
      expect(h, isNotNull);
      expect(h!.index, target);
      expect(h.message.toLowerCase(), contains('wrong'));
    });

    test('returns null on a finished grid', () {
      final p = Generator(1234).generate(Difficulty.gentle);
      expect(nextHint(p, List<int>.of(p.solution)), isNull);
    });

    test('hints name the pattern, not just the answer', () {
      // The value of a hint is the technique. Check the vocabulary is there.
      final p = Generator(42).generate(Difficulty.medium);
      final h = nextHint(p, _blank(p.cellCount));
      expect(h, isNotNull);
      expect(
          h!.message.toLowerCase(),
          anyOf(contains('three'), contains('shaded'), contains('stay'),
              contains('pair'), contains('cut off')));
    });
  });

  group('serialisation', () {
    test('a puzzle round-trips exactly', () {
      final p = Generator(2024).generate(Difficulty.medium);
      final back = Puzzle.fromJson(p.toJson());
      expect(back, isNotNull);
      expect(back!.numbers, p.numbers);
      expect(back.solution, p.solution);
      expect(back.size, p.size);
      expect(back.difficulty.label, p.difficulty.label);
    });

    test('malformed data returns null instead of throwing', () {
      expect(Puzzle.fromJson({'nonsense': true}), isNull);
      expect(Puzzle.fromJson({'n': 4, 'num': [1, 2], 'sol': [0, 1]}), isNull);
    });

    test('an out-of-range number is rejected', () {
      final p = Generator(7).generate(Difficulty.gentle);
      final j = p.toJson();
      (j['num'] as List)[0] = 99;
      expect(Puzzle.fromJson(j), isNull);
    });
  });
}
