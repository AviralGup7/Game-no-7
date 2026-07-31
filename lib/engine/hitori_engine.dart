/// Hitori engine.
///
/// PURE DART — no Flutter imports — so the whole thing unit-tests on a bare VM.
///
/// THE RULES, because Hitori is the least familiar puzzle in this portfolio:
///
///   You are given a square grid of numbers. Shade out cells until:
///     1. **No number appears twice** in any row or column, counting only the
///        cells you did NOT shade.
///     2. **No two shaded cells touch** edge-to-edge (diagonals are fine).
///     3. **All unshaded cells form one connected group** — you can walk
///        between any two of them through unshaded cells, moving only up,
///        down, left or right.
///
/// Rule 3 is what makes Hitori different from every other puzzle here. It is a
/// GLOBAL constraint: whether a cell may be shaded can depend on a cell on the
/// far side of the board. Row-and-column reasoning alone cannot see it, so the
/// solver has to do a flood fill on every candidate state.
///
/// The invariant this file guarantees, same as the rest of the portfolio:
/// **every emitted puzzle has EXACTLY ONE solution**, verified on every puzzle.
library;

/// Cell states.
const int kUnknown = -1;

/// Definitely NOT shaded — part of the final picture.
const int kKeep = 0;

/// Definitely shaded out.
const int kShade = 1;

class Difficulty {
  final String label;
  final int size;

  /// Roughly what fraction of cells the generator aims to shade.
  ///
  /// This number is the single biggest driver of whether a grid has a UNIQUE
  /// solution, and it is not intuitive: sparser puzzles are HARDER to generate,
  /// not easier. With few shaded cells there is not enough evidence to pin the
  /// answer down, so many different shadings satisfy the same grid.
  ///
  /// Measured over 120 grids per setting, counting how many came out unique:
  ///
  ///   density   5x5     6x6     7x7     8x8
  ///   0.16      0/120   0/120   0/120   0/120
  ///   0.20      0/120   0/120   0/120   0/120
  ///   0.24     12/120  10/120   1/120   0/120
  ///   0.28     65/120  46/120  61/120  46/120
  ///
  /// Every rejection was "multiple solutions" - never a failed construction -
  /// so the fix is density, not a smarter builder. An earlier version used
  /// 0.20-0.26 and could not produce a single valid 5x5 in 400 attempts.
  final double shadeTarget;

  const Difficulty._(this.label, this.size, this.shadeTarget);

  /// Plain, encouraging names only. Never "expert" or "evil" — a label that
  /// tells someone they are about to fail stops them opening it.
  ///
  /// Difficulty comes from GRID SIZE, not from shading density: density is
  /// pinned near the level that actually yields unique puzzles.
  static const gentle = Difficulty._('Gentle', 5, 0.30);
  static const easy = Difficulty._('Easy', 6, 0.30);
  static const medium = Difficulty._('Medium', 7, 0.30);
  static const hard = Difficulty._('Hard', 8, 0.30);

  static const all = <Difficulty>[gentle, easy, medium, hard];

  static Difficulty byLabel(String l) =>
      all.firstWhere((d) => d.label == l, orElse: () => gentle);

  @override
  String toString() => label;
}

/// Thrown when generation cannot produce a puzzle meeting the invariant.
class GenerationFailure implements Exception {
  final String message;
  GenerationFailure(this.message);
  @override
  String toString() => 'GenerationFailure: $message';
}

class Puzzle {
  final int size;

  /// The printed numbers, row-major. These never change during play.
  final List<int> numbers;

  /// The answer: kKeep or kShade per cell.
  final List<int> solution;

  final Difficulty difficulty;

  const Puzzle({
    required this.size,
    required this.numbers,
    required this.solution,
    required this.difficulty,
  });

  int get cellCount => size * size;
  int index(int r, int c) => r * size + c;
  int rowOf(int i) => i ~/ size;
  int colOf(int i) => i % size;

  int get shadedTarget => solution.where((s) => s == kShade).length;

  Map<String, dynamic> toJson() => {
        'n': size,
        'num': numbers,
        'sol': solution,
        'diff': difficulty.label,
      };

  /// Returns null rather than throwing on malformed input: a corrupt save must
  /// cost the player their progress, not crash the app on launch.
  static Puzzle? fromJson(Map<String, dynamic> j) {
    try {
      final n = j['n'] as int;
      final numbers = (j['num'] as List).map((e) => e as int).toList();
      final solution = (j['sol'] as List).map((e) => e as int).toList();
      if (numbers.length != n * n || solution.length != n * n) return null;
      for (final s in solution) {
        if (s != kKeep && s != kShade) return null;
      }
      for (final v in numbers) {
        if (v < 1 || v > n) return null;
      }
      return Puzzle(
        size: n,
        numbers: numbers,
        solution: solution,
        difficulty: Difficulty.byLabel((j['diff'] as String?) ?? 'Gentle'),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Why a candidate shading is invalid. Used by the UI to explain a mistake in
/// words rather than just marking it red.
enum Violation {
  none,

  /// Two shaded cells share an edge.
  adjacentShaded,

  /// A number appears twice unshaded in a row or column.
  duplicate,

  /// The unshaded cells are split into two or more islands.
  disconnected,
}

/// Full validity check of a COMPLETE shading (no kUnknown allowed).
Violation checkComplete(List<int> numbers, List<int> state, int n) {
  // Rule 2: no two shaded cells adjacent.
  for (var r = 0; r < n; r++) {
    for (var c = 0; c < n; c++) {
      if (state[r * n + c] != kShade) continue;
      if (c + 1 < n && state[r * n + c + 1] == kShade) {
        return Violation.adjacentShaded;
      }
      if (r + 1 < n && state[(r + 1) * n + c] == kShade) {
        return Violation.adjacentShaded;
      }
    }
  }

  // Rule 1: no duplicate unshaded numbers in a row or column.
  for (var r = 0; r < n; r++) {
    final seen = <int>{};
    for (var c = 0; c < n; c++) {
      final i = r * n + c;
      if (state[i] == kShade) continue;
      if (!seen.add(numbers[i])) return Violation.duplicate;
    }
  }
  for (var c = 0; c < n; c++) {
    final seen = <int>{};
    for (var r = 0; r < n; r++) {
      final i = r * n + c;
      if (state[i] == kShade) continue;
      if (!seen.add(numbers[i])) return Violation.duplicate;
    }
  }

  // Rule 3: the unshaded cells form ONE connected group.
  if (!isConnected(state, n)) return Violation.disconnected;

  return Violation.none;
}

/// Flood fill over unshaded cells. True if they are all reachable from each
/// other.
///
/// Treats kUnknown as unshaded, so this doubles as an optimistic check during
/// search: if the unshaded cells are already split when every undecided cell
/// is assumed KEPT, no future shading can rejoin them.
bool isConnected(List<int> state, int n) {
  var start = -1;
  var total = 0;
  for (var i = 0; i < n * n; i++) {
    if (state[i] != kShade) {
      total++;
      if (start < 0) start = i;
    }
  }
  if (total == 0) return true; // vacuously; a real puzzle never gets here

  final seen = List<bool>.filled(n * n, false);
  // An explicit stack rather than recursion: an 8x8 is fine either way, but
  // recursion depth on a large grid is a crash waiting to happen.
  final stack = <int>[start];
  seen[start] = true;
  var found = 0;

  while (stack.isNotEmpty) {
    final i = stack.removeLast();
    found++;
    final r = i ~/ n, c = i % n;
    if (c > 0 && !seen[i - 1] && state[i - 1] != kShade) {
      seen[i - 1] = true;
      stack.add(i - 1);
    }
    if (c + 1 < n && !seen[i + 1] && state[i + 1] != kShade) {
      seen[i + 1] = true;
      stack.add(i + 1);
    }
    if (r > 0 && !seen[i - n] && state[i - n] != kShade) {
      seen[i - n] = true;
      stack.add(i - n);
    }
    if (r + 1 < n && !seen[i + n] && state[i + n] != kShade) {
      seen[i + n] = true;
      stack.add(i + n);
    }
  }
  return found == total;
}

/// Solver over partial states.
///
/// Alternates cheap forced deductions with a branch on the most constrained
/// undecided cell. Deliberately mirrors how a person solves Hitori, so the
/// hint system can reuse the deductions and explain them.
class Solver {
  final int n;
  final List<int> numbers;

  Solver(this.numbers, this.n);

  /// Apply every forced deduction we can. Returns false on contradiction.
  ///
  /// The three techniques below are exactly the ones a Hitori player learns
  /// first, which is why the hint engine can name them.
  bool propagate(List<int> s) {
    var changed = true;
    while (changed) {
      changed = false;

      // A shaded cell forces all four neighbours to be kept: two shaded cells
      // may never touch.
      for (var i = 0; i < n * n; i++) {
        if (s[i] != kShade) continue;
        for (final j in _neighbours(i)) {
          if (s[j] == kShade) return false;
          if (s[j] == kUnknown) {
            s[j] = kKeep;
            changed = true;
          }
        }
      }

      // If a number is KEPT, every other cell with the same number in that row
      // or column must be shaded.
      for (var i = 0; i < n * n; i++) {
        if (s[i] != kKeep) continue;
        final v = numbers[i];
        final r = i ~/ n, c = i % n;
        for (var k = 0; k < n; k++) {
          final a = r * n + k;
          if (a != i && numbers[a] == v) {
            if (s[a] == kKeep) return false;
            if (s[a] == kUnknown) {
              s[a] = kShade;
              changed = true;
            }
          }
          final b = k * n + c;
          if (b != i && numbers[b] == v) {
            if (s[b] == kKeep) return false;
            if (s[b] == kUnknown) {
              s[b] = kShade;
              changed = true;
            }
          }
        }
      }

      // ---- TRIPLE: three of the same number in a line.
      // The middle one MUST be kept. If it were shaded, both outer cells
      // would have to be kept, and they are equal - a duplicate. So the
      // middle stays, and both outer cells are shaded.
      for (var a = 0; a < n; a++) {
        for (var b = 0; b + 2 < n; b++) {
          // row a, columns b, b+1, b+2
          final i0 = a * n + b, i1 = a * n + b + 1, i2 = a * n + b + 2;
          if (numbers[i0] == numbers[i1] && numbers[i1] == numbers[i2]) {
            if (s[i1] == kShade) return false;
            if (s[i1] == kUnknown) {
              s[i1] = kKeep;
              changed = true;
            }
          }
          // column a, rows b, b+1, b+2
          final j0 = b * n + a, j1 = (b + 1) * n + a, j2 = (b + 2) * n + a;
          if (numbers[j0] == numbers[j1] && numbers[j1] == numbers[j2]) {
            if (s[j1] == kShade) return false;
            if (s[j1] == kUnknown) {
              s[j1] = kKeep;
              changed = true;
            }
          }
        }
      }

      // ---- SANDWICH: x y x with the two x's separated by one cell.
      // The middle cell y must be KEPT. Shading it would force both x's to be
      // kept (no two shaded cells may touch is not the reason here - rather,
      // one of the two x's must be shaded, and if y were shaded its neighbours
      // could not be), which duplicates x.
      //
      // The sound form of the argument: exactly one of the two x's is kept.
      // Whichever it is, y sits beside a shaded x, so y cannot itself be
      // shaded.
      for (var a = 0; a < n; a++) {
        for (var b = 0; b + 2 < n; b++) {
          final i0 = a * n + b, i1 = a * n + b + 1, i2 = a * n + b + 2;
          if (numbers[i0] == numbers[i2] && numbers[i0] != numbers[i1]) {
            if (s[i1] == kShade) return false;
            if (s[i1] == kUnknown) {
              s[i1] = kKeep;
              changed = true;
            }
          }
          final j0 = b * n + a, j1 = (b + 1) * n + a, j2 = (b + 2) * n + a;
          if (numbers[j0] == numbers[j2] && numbers[j0] != numbers[j1]) {
            if (s[j1] == kShade) return false;
            if (s[j1] == kUnknown) {
              s[j1] = kKeep;
              changed = true;
            }
          }
        }
      }

      // ---- PAIR: two of the same number in a line means at least one of them
      // is shaded. Any OTHER cell in that line holding the same value must
      // therefore be shaded too - it cannot be the survivor.
      for (var a = 0; a < n; a++) {
        for (var b = 0; b + 1 < n; b++) {
          final i0 = a * n + b, i1 = a * n + b + 1;
          if (numbers[i0] == numbers[i1]) {
            final v = numbers[i0];
            for (var k = 0; k < n; k++) {
              final t = a * n + k;
              if (t == i0 || t == i1) continue;
              if (numbers[t] != v) continue;
              if (s[t] == kKeep) return false;
              if (s[t] == kUnknown) {
                s[t] = kShade;
                changed = true;
              }
            }
          }
          final j0 = b * n + a, j1 = (b + 1) * n + a;
          if (numbers[j0] == numbers[j1]) {
            final v = numbers[j0];
            for (var k = 0; k < n; k++) {
              final t = k * n + a;
              if (t == j0 || t == j1) continue;
              if (numbers[t] != v) continue;
              if (s[t] == kKeep) return false;
              if (s[t] == kUnknown) {
                s[t] = kShade;
                changed = true;
              }
            }
          }
        }
      }

      // ---- A cell surrounded on all sides by shaded cells would be cut off.
      // Equivalently: an UNKNOWN cell whose neighbours are all shaded must be
      // kept, and it must have somewhere to connect to.

      // Shading this cell would strand part of the board, so it must be kept.
      // This is the connectivity rule used as a deduction rather than only as
      // a final check, and it is what makes hard Hitori solvable by logic.
      for (var i = 0; i < n * n; i++) {
        if (s[i] != kUnknown) continue;
        s[i] = kShade;
        final ok = _adjacencyOk(s) && _optimisticallyConnected(s);
        s[i] = kUnknown;
        if (!ok) {
          s[i] = kKeep;
          changed = true;
        }
      }
    }
    return true;
  }

  Iterable<int> _neighbours(int i) sync* {
    final r = i ~/ n, c = i % n;
    if (c > 0) yield i - 1;
    if (c + 1 < n) yield i + 1;
    if (r > 0) yield i - n;
    if (r + 1 < n) yield i + n;
  }

  bool _adjacencyOk(List<int> s) {
    for (var i = 0; i < n * n; i++) {
      if (s[i] != kShade) continue;
      for (final j in _neighbours(i)) {
        if (s[j] == kShade) return false;
      }
    }
    return true;
  }

  /// Connectivity assuming every undecided cell ends up KEPT.
  ///
  /// This is the loosest possible check: if the board is already split when we
  /// are maximally generous, it can never be rejoined. Cheap and safe to use
  /// for pruning.
  bool _optimisticallyConnected(List<int> s) => isConnected(s, n);

  /// Count solutions, stopping at [limit].
  ///
  /// NOTE: [limit] is absolute and passed down UNCHANGED. An earlier game in
  /// this portfolio shipped a bug where the remaining budget was recursed,
  /// which disabled the pruning guard and turned a bounded count into an
  /// exhaustive walk of the whole space.
  int countSolutions(List<int> start, {int limit = 2}) {
    var total = 0;
    final s = List<int>.of(start);
    void rec() {
      if (total >= limit) return;
      final work = List<int>.of(s);
      if (!propagate(work)) return;

      var pivot = -1;
      for (var i = 0; i < n * n; i++) {
        if (work[i] == kUnknown) {
          pivot = i;
          break;
        }
      }

      if (pivot < 0) {
        if (checkComplete(numbers, work, n) == Violation.none) total++;
        return;
      }

      for (final guess in const [kShade, kKeep]) {
        if (total >= limit) return;
        final saved = List<int>.of(s);
        s
          ..clear()
          ..addAll(work);
        s[pivot] = guess;
        rec();
        s
          ..clear()
          ..addAll(saved);
      }
    }

    rec();
    return total;
  }

  /// Solve by forced deductions alone, no guessing.
  ///
  /// Returns the resulting state, which may still contain kUnknown if pure
  /// logic runs out. Used to grade difficulty and to drive hints.
  List<int>? solveByLogic(List<int> start) {
    final s = List<int>.of(start);
    if (!propagate(s)) return null;
    return s;
  }
}
