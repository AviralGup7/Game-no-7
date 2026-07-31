/// Puzzle generation.
///
/// PURE DART — no Flutter imports.
///
/// The approach, and why it is backwards from what you might expect:
///
/// You cannot sensibly pick random numbers and hope for a valid Hitori. The
/// three rules together — no duplicates, no touching shaded cells, everything
/// connected — make a random grid almost always unsolvable.
///
/// So we build the ANSWER first:
///   1. Choose a shading pattern that already satisfies rules 2 and 3 (no two
///      shaded cells touch, unshaded cells stay connected).
///   2. Fill the unshaded cells with numbers so no row or column repeats. This
///      makes rule 1 true by construction.
///   3. Fill the shaded cells with numbers that DUPLICATE something in their
///      row or column — that duplicate is the clue that tells the player the
///      cell must be shaded. A shaded cell holding a number nothing else has
///      is unsolvable-by-logic, because nothing points at it.
///   4. Verify the finished grid has EXACTLY ONE solution. If not, discard.
///
/// Step 3 is the part that is easy to get wrong. A first version filled shaded
/// cells with any random number, which produced grids where a shaded cell was
/// indistinguishable from a kept one — technically a puzzle, but only solvable
/// by trial and error.
library;

import 'hitori_engine.dart';

class Generator {
  /// Deterministic PRNG. Same seed anywhere in the world -> same puzzle, with
  /// no server involved. Hand-rolled because `dart:math`'s Random is NOT
  /// guaranteed stable across Dart releases, and the daily puzzle must be.
  int _state;

  Generator(int seed) : _state = (seed == 0 ? 0x2545F491 : seed) & 0x7FFFFFFF;

  int _next(int bound) {
    _state = (_state * 1103515245 + 12345) & 0x7FFFFFFF;
    return _state % bound;
  }

  Puzzle generate(Difficulty d) {
    final n = d.size;

    // Attempts are bounded so a pathological seed cannot hang the UI.
    //
    // The density nudges upward across attempts. Sparse grids are the ones
    // that come out ambiguous (see the measurement table on
    // Difficulty.shadeTarget), so if the target density keeps failing, adding
    // a little more shading is exactly the right thing to try.
    for (var attempt = 0; attempt < 400; attempt++) {
      final density = d.shadeTarget + (attempt ~/ 50) * 0.02;
      final shading = _buildShading(n, density > 0.36 ? 0.36 : density);
      if (shading == null) continue;

      final numbers = _fillNumbers(n, shading);
      if (numbers == null) continue;

      // The grid must actually satisfy all three rules with this shading.
      if (checkComplete(numbers, shading, n) != Violation.none) continue;

      // INVARIANT 1: exactly one solution.
      final solver = Solver(numbers, n);
      final blank = List<int>.filled(n * n, kUnknown);
      if (solver.countSolutions(blank, limit: 2) != 1) continue;

      // INVARIANT 2: solvable by pure logic, with NO guessing.
      //
      // Strictly stronger than uniqueness and the one players actually feel.
      // A puzzle that is technically unique but needs trial and error is, to
      // the person holding the phone, indistinguishable from a broken app.
      final logic = solver.solveByLogic(blank);
      if (logic == null || logic.contains(kUnknown)) continue;

      return Puzzle(
        size: n,
        numbers: numbers,
        solution: shading,
        difficulty: d,
      );
    }

    throw GenerationFailure('No unique Hitori at size $n after 400 attempts');
  }

  /// Pick a shading pattern satisfying rules 2 and 3.
  ///
  /// Greedy with rejection: try to shade a random cell, undo it if that breaks
  /// adjacency or connectivity. Simple, and fast enough because both checks
  /// are cheap on grids this small.
  List<int>? _buildShading(int n, double target) {
    final s = List<int>.filled(n * n, kKeep);
    final want = (n * n * target).round();
    var placed = 0;

    // Walk cells in a shuffled order so the pattern is not biased toward one
    // corner.
    final order = List<int>.generate(n * n, (i) => i);
    for (var i = order.length - 1; i > 0; i--) {
      final j = _next(i + 1);
      final t = order[i];
      order[i] = order[j];
      order[j] = t;
    }

    for (final i in order) {
      if (placed >= want) break;
      final r = i ~/ n, c = i % n;

      // Rule 2: never touch another shaded cell.
      var touches = false;
      if (c > 0 && s[i - 1] == kShade) touches = true;
      if (c + 1 < n && s[i + 1] == kShade) touches = true;
      if (r > 0 && s[i - n] == kShade) touches = true;
      if (r + 1 < n && s[i + n] == kShade) touches = true;
      if (touches) continue;

      s[i] = kShade;
      if (!isConnected(s, n)) {
        s[i] = kKeep; // rule 3 broken: undo
        continue;
      }
      placed++;
    }

    // A grid with almost nothing shaded is a non-puzzle.
    if (placed < (want * 0.6).floor() || placed == 0) return null;
    return s;
  }

  /// Fill in the numbers, given the shading.
  ///
  /// Unshaded cells get values that keep every row and column duplicate-free.
  /// Shaded cells get values that deliberately DUPLICATE a kept value in the
  /// same row or column, because that duplicate is the player's only evidence
  /// the cell must be shaded.
  List<int>? _fillNumbers(int n, List<int> shading) {
    final numbers = List<int>.filled(n * n, 0);

    // ---- unshaded cells: a Latin-square-style fill, backtracking on failure
    final keptCells = <int>[];
    for (var i = 0; i < n * n; i++) {
      if (shading[i] == kKeep) keptCells.add(i);
    }

    bool assign(int at) {
      if (at == keptCells.length) return true;
      final i = keptCells[at];
      final r = i ~/ n, c = i % n;

      final candidates = List<int>.generate(n, (k) => k + 1);
      for (var k = candidates.length - 1; k > 0; k--) {
        final j = _next(k + 1);
        final t = candidates[k];
        candidates[k] = candidates[j];
        candidates[j] = t;
      }

      for (final v in candidates) {
        var clash = false;
        for (var k = 0; k < n && !clash; k++) {
          final a = r * n + k;
          if (a != i && shading[a] == kKeep && numbers[a] == v) clash = true;
          final b = k * n + c;
          if (b != i && shading[b] == kKeep && numbers[b] == v) clash = true;
        }
        if (clash) continue;
        numbers[i] = v;
        if (assign(at + 1)) return true;
        numbers[i] = 0;
      }
      return false;
    }

    if (!assign(0)) return null;

    // ---- shaded cells: duplicate a kept value from the same row or column
    for (var i = 0; i < n * n; i++) {
      if (shading[i] != kShade) continue;
      final r = i ~/ n, c = i % n;

      final options = <int>[];
      for (var k = 0; k < n; k++) {
        final a = r * n + k;
        if (shading[a] == kKeep) options.add(numbers[a]);
        final b = k * n + c;
        if (shading[b] == kKeep) options.add(numbers[b]);
      }
      if (options.isEmpty) return null; // fully isolated: cannot hint at it
      numbers[i] = options[_next(options.length)];
    }

    return numbers;
  }
}

/// How hard a puzzle is to solve by pure logic, and whether it can be at all.
class PuzzleStats {
  /// True if forced deductions alone finish the grid — no guessing needed.
  final bool logicOnly;

  /// Cells still undecided after logic runs out. 0 means fully solvable.
  final int undecided;

  final int shaded;

  const PuzzleStats(this.logicOnly, this.undecided, this.shaded);
}

PuzzleStats analyse(Puzzle p) {
  final solver = Solver(p.numbers, p.size);
  final s = solver.solveByLogic(List<int>.filled(p.cellCount, kUnknown));
  if (s == null) return PuzzleStats(false, p.cellCount, p.shadedTarget);
  final undecided = s.where((v) => v == kUnknown).length;
  return PuzzleStats(undecided == 0, undecided, p.shadedTarget);
}
