/// Mutable in-progress game: marks, undo, save/resume.
///
/// PURE DART — no Flutter imports, so it unit-tests on a bare VM.
///
/// Hitori has THREE player states per cell, and the third is the one that
/// matters most:
///
///   * unmarked   — undecided
///   * SHADED     — you have decided this cell is shaded out
///   * CIRCLED    — you have decided this cell stays
///
/// The circle is not decoration. On paper, Hitori players ring the cells they
/// have proven must stay, because "not yet shaded" and "definitely stays" are
/// completely different pieces of information, and confusing them is how you
/// lose track. Most digital Hitori apps offer only shade/unshade and are much
/// harder to hold in your head as a result.
library;

import 'dart:convert';
import '../engine/hitori_engine.dart';

/// What the player has marked on a cell.
const int kMarkNone = -1;

/// Player says: this cell stays (ringed on paper).
const int kMarkCircle = 0;

/// Player says: this cell is shaded out.
const int kMarkShade = 1;

/// What tapping a cell does.
enum Tool {
  /// Shade a cell out.
  shade('Shade'),

  /// Ring a cell you have proved must stay.
  circle('Keep');

  final String label;
  const Tool(this.label);
}

class _Move {
  final int index;
  final int before;
  final int after;

  /// True when this entry belongs to the SAME player action as the one before
  /// it, so a single action that touches many cells undoes in one press.
  final bool grouped;

  const _Move(this.index, this.before, this.after, {this.grouped = false});
}

class GameState {
  final Puzzle puzzle;

  /// One of kMarkNone / kMarkCircle / kMarkShade per cell.
  late List<int> marks;

  int selected = -1;
  Tool tool = Tool.shade;
  int elapsedSeconds = 0;
  int mistakes = 0;
  int hintsUsed = 0;

  final List<_Move> _undo = [];

  GameState(this.puzzle) {
    marks = List<int>.filled(puzzle.cellCount, kMarkNone);
  }

  /// True when every cell that should be shaded IS shaded, and nothing else
  /// is.
  ///
  /// Deliberately ignores circles: a player who worked out the shading without
  /// ringing every kept cell has finished. Demanding bookkeeping they did not
  /// need is the kind of pedantry that gets an app uninstalled.
  bool get isSolved {
    for (var i = 0; i < puzzle.cellCount; i++) {
      final shouldShade = puzzle.solution[i] == kShade;
      final didShade = marks[i] == kMarkShade;
      if (shouldShade != didShade) return false;
    }
    return true;
  }

  int get shadedCount => marks.where((m) => m == kMarkShade).length;

  /// Remaining cells to shade — plain progress, never a countdown.
  int get remaining => puzzle.shadedTarget - shadedCount;

  bool isWrong(int i) {
    final m = marks[i];
    if (m == kMarkNone) return false;
    final shouldShade = puzzle.solution[i] == kShade;
    if (m == kMarkShade && !shouldShade) return true;
    if (m == kMarkCircle && shouldShade) return true;
    return false;
  }

  bool get hasMistakes {
    for (var i = 0; i < puzzle.cellCount; i++) {
      if (isWrong(i)) return true;
    }
    return false;
  }

  /// Apply the current tool. Tapping a cell that already carries that mark
  /// clears it, so one finger both sets and unsets.
  ///
  /// Returns true if the move was WRONG so the UI can shake and underline it.
  bool apply(int i) {
    final want = tool == Tool.shade ? kMarkShade : kMarkCircle;
    final next = (marks[i] == want) ? kMarkNone : want;
    _push(i, next);
    if (next == kMarkNone) return false;
    final wrong = isWrong(i);
    if (wrong) mistakes++;
    return wrong;
  }

  /// Set a mark directly. Used by hints and by drag-painting.
  bool setMark(int i, int mark, {bool grouped = false}) {
    if (marks[i] == mark) return false;
    _push(i, mark, grouped: grouped);
    if (mark == kMarkNone) return false;
    final wrong = isWrong(i);
    if (wrong) mistakes++;
    return wrong;
  }

  void erase(int i) {
    if (marks[i] == kMarkNone) return;
    _push(i, kMarkNone);
  }

  void _push(int i, int next, {bool grouped = false}) {
    _undo.add(_Move(i, marks[i], next, grouped: grouped));
    marks[i] = next;
    if (_undo.length > 500) _undo.removeAt(0);
  }

  /// Attach [cells] to the previous action so they all undo together.
  void groupWithPrevious(List<int> cells) {
    if (cells.isEmpty) return;
    for (var k = _undo.length - cells.length; k < _undo.length; k++) {
      if (k < 0) continue;
      final m = _undo[k];
      _undo[k] = _Move(m.index, m.before, m.after, grouped: true);
    }
  }

  bool get canUndo => _undo.isNotEmpty;

  /// Undo one PLAYER ACTION, which may span several cells.
  void undo() {
    if (_undo.isEmpty) return;
    while (_undo.isNotEmpty && _undo.last.grouped) {
      final m = _undo.removeLast();
      marks[m.index] = m.before;
    }
    if (_undo.isEmpty) return;
    final m = _undo.removeLast();
    marks[m.index] = m.before;
  }

  /// Remove every mark that contradicts the answer. Offered explicitly rather
  /// than done automatically — silently undoing someone's work is
  /// disorienting.
  int clearMistakes() {
    final cleared = <int>[];
    for (var i = 0; i < puzzle.cellCount; i++) {
      if (!isWrong(i)) continue;
      _push(i, kMarkNone, grouped: cleared.isNotEmpty);
      cleared.add(i);
    }
    return cleared.length;
  }

  /// Ring every cell adjacent to one the player has shaded.
  ///
  /// Pure bookkeeping: the rule that two shaded cells may never touch makes
  /// these forced, and doing it by hand on an 8x8 is where people give up.
  /// Returns the cells it marked, so the caller can group the undo.
  List<int> autoCircleNeighbours() {
    final n = puzzle.size;
    final done = <int>[];
    for (var i = 0; i < puzzle.cellCount; i++) {
      if (marks[i] != kMarkShade) continue;
      final r = i ~/ n, c = i % n;
      for (final j in [
        if (c > 0) i - 1,
        if (c + 1 < n) i + 1,
        if (r > 0) i - n,
        if (r + 1 < n) i + n,
      ]) {
        if (marks[j] == kMarkNone) {
          setMark(j, kMarkCircle, grouped: true);
          done.add(j);
        }
      }
    }
    return done;
  }

  /// Is this row's unshaded set free of duplicates, given what is marked?
  /// Used to grey out a line the player has finished, as on paper.
  bool isRowResolved(int r) {
    final n = puzzle.size;
    for (var c = 0; c < n; c++) {
      final i = r * n + c;
      final shouldShade = puzzle.solution[i] == kShade;
      if (shouldShade != (marks[i] == kMarkShade)) return false;
    }
    return true;
  }

  bool isColResolved(int c) {
    final n = puzzle.size;
    for (var r = 0; r < n; r++) {
      final i = r * n + c;
      final shouldShade = puzzle.solution[i] == kShade;
      if (shouldShade != (marks[i] == kMarkShade)) return false;
    }
    return true;
  }

  // ------------------------------------------------------------------- save

  Map<String, dynamic> toJson() => {
        'v': 1,
        'p': puzzle.toJson(),
        'm': marks,
        'sel': selected,
        'tool': tool.index,
        't': elapsedSeconds,
        'mis': mistakes,
        'h': hintsUsed,
      };

  String encode() => jsonEncode(toJson());

  /// Returns null on anything malformed. A corrupt save must cost the player
  /// their progress, never crash the app on launch.
  static GameState? decode(String raw) {
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final p = Puzzle.fromJson(j['p'] as Map<String, dynamic>);
      if (p == null) return null;
      final marks = (j['m'] as List).map((e) => e as int).toList();
      if (marks.length != p.cellCount) return null;
      for (final m in marks) {
        if (m != kMarkNone && m != kMarkCircle && m != kMarkShade) return null;
      }
      final g = GameState(p);
      g.marks = marks;
      g.selected = (j['sel'] as int?) ?? -1;
      final ti = (j['tool'] as int?) ?? 0;
      g.tool =
          (ti >= 0 && ti < Tool.values.length) ? Tool.values[ti] : Tool.shade;
      g.elapsedSeconds = (j['t'] as int?) ?? 0;
      g.mistakes = (j['mis'] as int?) ?? 0;
      g.hintsUsed = (j['h'] as int?) ?? 0;
      return g;
    } catch (_) {
      return null;
    }
  }
}
