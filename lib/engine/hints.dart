/// Hints that teach the technique.
///
/// PURE DART — no Flutter imports.
///
/// A hint that just shades a cell teaches nothing: the player is equally stuck
/// next time. Every hint here names the cell, says what to do, and names the
/// PATTERN that proves it — because Hitori is a small set of recurring
/// patterns, and once you can see them the puzzle opens up.
///
/// The order below is the order a person learns them.
library;

import 'hitori_engine.dart';

class Hint {
  final int index;

  /// kShade or kKeep.
  final int value;

  /// Plain-language reasoning, naming the pattern.
  final String message;

  const Hint(this.index, this.value, this.message);
}

String _where(int i, int n) =>
    'row ${i ~/ n + 1}, column ${i % n + 1}';

/// The next deduction available, with its reasoning.
///
/// [marks] is what the player has already decided, mapped into engine terms
/// (kUnknown / kKeep / kShade).
Hint? nextHint(Puzzle p, List<int> known) {
  final n = p.size;
  final nums = p.numbers;

  // 0. A mistake beats every other hint: everything built on it is wrong.
  for (var i = 0; i < p.cellCount; i++) {
    if (known[i] == kUnknown) continue;
    final shouldShade = p.solution[i] == kShade;
    if ((known[i] == kShade) != shouldShade) {
      return Hint(
        i,
        shouldShade ? kShade : kKeep,
        'The cell at ${_where(i, n)} is marked the wrong way. Everything you '
        'work out from here will be wrong too, so it is worth fixing first.',
      );
    }
  }

  // 1. TRIPLE — three identical numbers in a line.
  for (var a = 0; a < n; a++) {
    for (var b = 0; b + 2 < n; b++) {
      final row = [a * n + b, a * n + b + 1, a * n + b + 2];
      final col = [b * n + a, (b + 1) * n + a, (b + 2) * n + a];
      for (final line in [row, col]) {
        if (nums[line[0]] != nums[line[1]]) continue;
        if (nums[line[1]] != nums[line[2]]) continue;
        final mid = line[1];
        if (known[mid] != kUnknown) continue;
        return Hint(
          mid,
          kKeep,
          'Three ${nums[mid]}s in a row here. The middle one at '
          '${_where(mid, n)} must STAY. If you shaded it, the two either side '
          'would both have to stay — and they are both ${nums[mid]}s, which is '
          'not allowed. So the middle stays and the outer two get shaded.',
        );
      }
    }
  }

  // 2. SANDWICH — x y x.
  for (var a = 0; a < n; a++) {
    for (var b = 0; b + 2 < n; b++) {
      final row = [a * n + b, a * n + b + 1, a * n + b + 2];
      final col = [b * n + a, (b + 1) * n + a, (b + 2) * n + a];
      for (final line in [row, col]) {
        if (nums[line[0]] != nums[line[2]]) continue;
        if (nums[line[0]] == nums[line[1]]) continue;
        final mid = line[1];
        if (known[mid] != kUnknown) continue;
        return Hint(
          mid,
          kKeep,
          'Look at ${nums[line[0]]}, ${nums[mid]}, ${nums[line[0]]} here. One '
          'of the two ${nums[line[0]]}s must be shaded. Whichever it is, it '
          'sits right next to ${_where(mid, n)} — and two shaded cells can '
          'never touch. So the ${nums[mid]} in the middle must stay.',
        );
      }
    }
  }

  // 3. PAIR — a duplicate pair shades every other copy in that line.
  for (var a = 0; a < n; a++) {
    for (var b = 0; b + 1 < n; b++) {
      final rowPair = [a * n + b, a * n + b + 1];
      final colPair = [b * n + a, (b + 1) * n + a];
      for (var axis = 0; axis < 2; axis++) {
        final pair = axis == 0 ? rowPair : colPair;
        if (nums[pair[0]] != nums[pair[1]]) continue;
        final v = nums[pair[0]];
        for (var k = 0; k < n; k++) {
          final t = axis == 0 ? a * n + k : k * n + a;
          if (t == pair[0] || t == pair[1]) continue;
          if (nums[t] != v) continue;
          if (known[t] != kUnknown) continue;
          final line = axis == 0 ? 'row ${a + 1}' : 'column ${a + 1}';
          return Hint(
            t,
            kShade,
            'There is a pair of ${v}s side by side in $line, so one of THOSE '
            'two has to survive. That means the other $v at ${_where(t, n)} '
            'cannot — shade it.',
          );
        }
      }
    }
  }

  // 4. NEIGHBOUR OF A SHADED CELL — forced by the no-touching rule.
  for (var i = 0; i < p.cellCount; i++) {
    if (known[i] != kShade) continue;
    final r = i ~/ n, c = i % n;
    for (final j in [
      if (c > 0) i - 1,
      if (c + 1 < n) i + 1,
      if (r > 0) i - n,
      if (r + 1 < n) i + n,
    ]) {
      if (known[j] != kUnknown) continue;
      return Hint(
        j,
        kKeep,
        'You have shaded ${_where(i, n)}, and two shaded cells may never touch '
        'side by side. So ${_where(j, n)} next to it must stay.',
      );
    }
  }

  // 5. DUPLICATE OF A KEPT CELL.
  for (var i = 0; i < p.cellCount; i++) {
    if (known[i] != kKeep) continue;
    final v = nums[i];
    final r = i ~/ n, c = i % n;
    for (var k = 0; k < n; k++) {
      for (final t in [r * n + k, k * n + c]) {
        if (t == i || nums[t] != v || known[t] != kUnknown) continue;
        return Hint(
          t,
          kShade,
          'You have kept the $v at ${_where(i, n)}. No number may appear twice '
          'unshaded in the same line, so the other $v at ${_where(t, n)} has '
          'to be shaded.',
        );
      }
    }
  }

  // 6. CONNECTIVITY — shading this would cut the grid in two.
  for (var i = 0; i < p.cellCount; i++) {
    if (known[i] != kUnknown) continue;
    final probe = List<int>.of(known);
    probe[i] = kShade;
    if (!isConnected(probe, n)) {
      return Hint(
        i,
        kKeep,
        'If you shaded ${_where(i, n)}, part of the grid would be cut off from '
        'the rest. Every unshaded cell has to stay joined to all the others, '
        'so this one must stay.',
      );
    }
  }

  // 7. Fall back to the answer, still saying which rule is at work.
  for (var i = 0; i < p.cellCount; i++) {
    if (known[i] != kUnknown) continue;
    final shade = p.solution[i] == kShade;
    return Hint(
      i,
      shade ? kShade : kKeep,
      shade
          ? 'The cell at ${_where(i, n)} needs shading — its number is repeated '
              'in this line.'
          : 'The cell at ${_where(i, n)} stays.',
    );
  }

  return null;
}
