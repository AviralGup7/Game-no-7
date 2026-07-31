/// The board: a square grid of numbers the player shades out.
///
/// Accessibility decisions baked in here:
///   * The number is the content, so it gets the largest type the cell allows.
///   * A shaded cell is a SOLID dark block with the number still faintly
///     visible — players constantly re-check what they shaded, and hiding it
///     forces them to undo just to look.
///   * A kept cell is ringed, not merely left blank. "Undecided" and
///     "proved it stays" are different facts and must look different.
///   * A mistake gets colour AND a shape change AND a shake from the caller —
///     never colour alone.
///   * Drag to paint: dragging applies the current tool across cells. Precise
///     repeated tapping is exactly what arthritic hands struggle with.
///   * Every cell has a semantic label naming its number and state.
library;

import 'package:flutter/material.dart';
import '../models/game_state.dart';
import 'app_theme.dart';

class HitoriBoard extends StatefulWidget {
  final GameState game;
  final double fontScale;
  final bool highContrast;
  final bool highlightLine;
  final bool showMistakes;

  /// Cell the last hint pointed at, flashed so it can be found.
  final int? hintIndex;

  final void Function(int index) onCell;
  final void Function(int index, int mark)? onPaint;

  const HitoriBoard({
    super.key,
    required this.game,
    required this.onCell,
    this.onPaint,
    this.fontScale = 1.0,
    this.highContrast = false,
    this.highlightLine = true,
    this.showMistakes = true,
    this.hintIndex,
  });

  @override
  State<HitoriBoard> createState() => _HitoriBoardState();
}

class _HitoriBoardState extends State<HitoriBoard> {
  /// Cells already painted during the CURRENT drag, so dragging back and forth
  /// over one cell does not toggle it repeatedly.
  final Set<int> _strokeDone = {};
  int? _strokeMark;
  double _cell = 0;
  Offset _origin = Offset.zero;

  int? _cellAt(Offset p) {
    if (_cell <= 0) return null;
    final n = widget.game.puzzle.size;
    final x = p.dx - _origin.dx;
    final y = p.dy - _origin.dy;
    if (x < 0 || y < 0) return null;
    final c = (x / _cell).floor();
    final r = (y / _cell).floor();
    if (c < 0 || c >= n || r < 0 || r >= n) return null;
    return r * n + c;
  }

  void _handleAt(Offset local, {required bool isDrag}) {
    final i = _cellAt(local);
    if (i == null) return;

    if (!isDrag) {
      widget.onCell(i);
      // Whatever the tap produced becomes the mark the rest of the stroke
      // paints, so a drag is uniform instead of alternating on/off.
      _strokeMark = widget.game.marks[i];
      _strokeDone
        ..clear()
        ..add(i);
      return;
    }

    if (_strokeDone.contains(i)) return;
    _strokeDone.add(i);
    final mark = _strokeMark;
    if (mark == null || widget.onPaint == null) return;
    widget.onPaint!(i, mark);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final n = widget.game.puzzle.size;

    return LayoutBuilder(
      builder: (context, box) {
        final side = box.maxWidth < box.maxHeight ? box.maxWidth : box.maxHeight;
        _cell = side / n;
        _origin = Offset(
          (box.maxWidth - side) / 2,
          (box.maxHeight - side) / 2,
        );

        return Semantics(
          label: 'Puzzle grid, $n by $n. '
              '${widget.game.remaining} cells still to shade.',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => _handleAt(d.localPosition, isDrag: false),
            onPanStart: (d) => _handleAt(d.localPosition, isDrag: false),
            onPanUpdate: (d) => _handleAt(d.localPosition, isDrag: true),
            onPanEnd: (_) {
              _strokeDone.clear();
              _strokeMark = null;
            },
            child: CustomPaint(
              size: Size(box.maxWidth, box.maxHeight),
              painter: _BoardPainter(
                game: widget.game,
                cell: _cell,
                origin: _origin,
                scheme: scheme,
                highContrast: widget.highContrast,
                highlightLine: widget.highlightLine,
                showMistakes: widget.showMistakes,
                hintIndex: widget.hintIndex,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BoardPainter extends CustomPainter {
  final GameState game;
  final double cell;
  final Offset origin;
  final ColorScheme scheme;
  final bool highContrast;
  final bool highlightLine;
  final bool showMistakes;
  final int? hintIndex;

  _BoardPainter({
    required this.game,
    required this.cell,
    required this.origin,
    required this.scheme,
    required this.highContrast,
    required this.highlightLine,
    required this.showMistakes,
    required this.hintIndex,
  });

  Rect _rect(int r, int c) =>
      Rect.fromLTWH(origin.dx + c * cell, origin.dy + r * cell, cell, cell);

  @override
  void paint(Canvas canvas, Size size) {
    final p = game.puzzle;
    final n = p.size;

    final selRow = game.selected >= 0 ? game.selected ~/ n : -1;
    final selCol = game.selected >= 0 ? game.selected % n : -1;

    // ---- line highlight, under everything
    if (highlightLine && game.selected >= 0) {
      final wash = Paint()..color = AppTheme.peerFill(scheme);
      canvas.drawRect(
          Rect.fromLTWH(origin.dx, origin.dy + selRow * cell, cell * n, cell),
          wash);
      canvas.drawRect(
          Rect.fromLTWH(origin.dx + selCol * cell, origin.dy, cell, cell * n),
          wash);
    }

    final shadeFill = Paint()..color = AppTheme.shadedCell(scheme);

    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        final i = r * n + c;
        final rect = _rect(r, c);
        final mark = game.marks[i];
        final wrong = showMistakes && game.isWrong(i);

        if (i == hintIndex) {
          canvas.drawRect(
              rect.deflate(1), Paint()..color = AppTheme.hintFill(scheme));
        }

        if (mark == kMarkShade) {
          canvas.drawRect(rect.deflate(cell * 0.045), shadeFill);
        }

        // The number. Still drawn on a shaded cell, just faintly: players
        // re-check what they shaded constantly, and hiding it would force an
        // undo just to look.
        final onShade = mark == kMarkShade;
        final colour = wrong
            ? AppTheme.wrongText(scheme)
            : onShade
                ? AppTheme.onShaded(scheme)
                : scheme.onSurface;
        _text(canvas, '${p.numbers[i]}', rect.center, cell * 0.46, colour,
            bold: !onShade);

        // A ring means "I have proved this one stays".
        if (mark == kMarkCircle) {
          canvas.drawCircle(
            rect.center,
            cell * 0.40,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = cell * (highContrast ? 0.075 : 0.055)
              ..color = wrong
                  ? AppTheme.wrongText(scheme)
                  : AppTheme.circleColour(scheme),
          );
        }

        if (wrong) {
          // Colour AND a shape: a heavy box around the offending cell.
          canvas.drawRect(
            rect.deflate(2),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3.0
              ..color = AppTheme.wrongText(scheme),
          );
        }
      }
    }

    // ---- grid lines
    final thin = Paint()
      ..color = scheme.outline.withValues(alpha: highContrast ? .85 : .45)
      ..strokeWidth = highContrast ? 1.6 : 1.0;
    final thick = Paint()
      ..color = scheme.outline.withValues(alpha: highContrast ? 1 : .9)
      ..strokeWidth = highContrast ? 3.4 : 2.6;

    for (var k = 0; k <= n; k++) {
      final x = origin.dx + k * cell;
      final y = origin.dy + k * cell;
      final edge = k == 0 || k == n;
      canvas.drawLine(Offset(x, origin.dy), Offset(x, origin.dy + cell * n),
          edge ? thick : thin);
      canvas.drawLine(Offset(origin.dx, y), Offset(origin.dx + cell * n, y),
          edge ? thick : thin);
    }
  }

  void _text(Canvas canvas, String s, Offset centre, double size, Color colour,
      {bool bold = true}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontSize: size,
          color: colour,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, centre - Offset(tp.width / 2, tp.height / 2));
  }

  /// Always repaints.
  ///
  /// GameState is mutated IN PLACE, so `old.game != game` is false even when
  /// every cell has changed. A field-by-field comparison here would look
  /// correct while silently freezing the board. The board only rebuilds when
  /// the parent calls setState, which happens on a real change.
  @override
  bool shouldRepaint(covariant _BoardPainter old) => true;
}
