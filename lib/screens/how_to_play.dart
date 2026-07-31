library;

import 'package:flutter/material.dart';
import '../services/settings.dart';

/// Plain language, no jargon, worked example.
///
/// Hitori is the least familiar puzzle in this portfolio. Almost nobody has
/// played one, and a grid of numbers with no explanation is an immediate
/// uninstall — so this is shown automatically on first run and is always one
/// tap away.
class HowToPlayScreen extends StatelessWidget {
  final Settings settings;
  const HowToPlayScreen({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    final fs = settings.fontScale;
    final scheme = Theme.of(context).colorScheme;

    TextStyle h() =>
        TextStyle(fontSize: 21 * fs, fontWeight: FontWeight.w700, height: 1.3);
    TextStyle b() => TextStyle(fontSize: 17 * fs, height: 1.45);

    return Scaffold(
      appBar: AppBar(title: const Text('How to play')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Text('The idea', style: h()),
            const SizedBox(height: 6),
            Text(
              'You are given a grid of numbers. Some of them are repeated. '
              'Your job is to shade out the extra ones until no number appears '
              'twice in any row or column.',
              style: b(),
            ),
            const SizedBox(height: 22),

            Text('The three rules', style: h()),
            const SizedBox(height: 6),
            Text(
              '1. Once you have finished, no number may appear twice in the '
              'same row or column — counting only the squares you have NOT '
              'shaded.\n\n'
              '2. Two shaded squares may never sit side by side. Corner to '
              'corner is fine.\n\n'
              '3. All the squares you leave unshaded must join up into one '
              'single group. You should be able to travel between any two of '
              'them by stepping up, down, left or right without crossing a '
              'shaded square.',
              style: b(),
            ),
            const SizedBox(height: 22),

            _example(context, fs, scheme),
            const SizedBox(height: 22),

            Text('The pattern that gets you started', style: h()),
            const SizedBox(height: 6),
            Text(
              'If you see the same number three times in a row, like 4 4 4:\n\n'
              'The MIDDLE one always stays. If you shaded it, the two on '
              'either side would both have to stay — and they are both 4s, '
              'which rule 1 forbids.\n\n'
              'So the middle 4 stays, and the two outer 4s get shaded.',
              style: b(),
            ),
            const SizedBox(height: 22),

            Text('Another useful pattern', style: h()),
            const SizedBox(height: 6),
            Text(
              'If you see a number, then a different one, then the first again '
              '— like 3 5 3 — the one in the MIDDLE always stays.\n\n'
              'One of the two 3s has to be shaded. Whichever it turns out to '
              'be, it sits right next to the 5 — and rule 2 says two shaded '
              'squares cannot touch. So the 5 is safe.',
              style: b(),
            ),
            const SizedBox(height: 22),

            Text('Use the Keep button', style: h()),
            const SizedBox(height: 6),
            Text(
              'When you have worked out that a square definitely stays, press '
              'Keep and tap it. A ring appears around it.\n\n'
              'This is the real skill. "I have not decided yet" and "I have '
              'proved this one stays" are completely different, and trying to '
              'hold the difference in your head is what makes Hitori feel '
              'hard.\n\n'
              'The app will also ring the squares next to anything you shade, '
              'since rule 2 makes those automatic.',
              style: b(),
            ),
            const SizedBox(height: 22),

            Text('Drag to work faster', style: h()),
            const SizedBox(height: 6),
            Text(
              'You do not have to tap each square. Press and drag across '
              'several squares to mark them all at once.',
              style: b(),
            ),
            const SizedBox(height: 22),

            Text('If you get stuck', style: h()),
            const SizedBox(height: 6),
            Text(
              'Press Hint. It marks one square AND names the pattern that '
              'proves it, so next time you can spot it yourself.\n\n'
              'Press Fix to clear anything you have marked wrongly.\n\n'
              'Undo goes back as far as you like, and there is never a time '
              'limit.',
              style: b(),
            ),
            const SizedBox(height: 22),

            Text('Every puzzle can be solved by thinking', style: h()),
            const SizedBox(height: 6),
            Text(
              'You will never have to guess. Every puzzle in this app has been '
              'checked by computer: it has exactly one answer, and that answer '
              'can always be reached by working through the patterns above.',
              style: b(),
            ),
            const SizedBox(height: 28),

            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Start playing',
                  style: TextStyle(fontSize: 19 * fs)),
            ),
          ],
        ),
      ),
    );
  }

  /// A tiny worked board, drawn with widgets rather than an image so it scales
  /// with the text-size setting and needs no asset.
  Widget _example(BuildContext context, double fs, ColorScheme scheme) {
    // A real 3x3 Hitori, VERIFIED by the engine to have exactly one
    // solution. An earlier version of this example was a valid shading but
    // the grid had THREE solutions - fine as a picture, useless as a teaching
    // aid, because the reasoning shown would not actually be forced.
    //
    //   3 3 1      # . #      row 1: two 3s, so one goes
    //   3 2 1      . . .
    //   1 1 1      # . #      row 3: three 1s - the middle one always stays
    const nums = [
      [3, 3, 1],
      [3, 2, 1],
      [1, 1, 1],
    ];
    const shaded = [
      [true, false, true],
      [false, false, false],
      [true, false, true],
    ];
    final cellSize = 46.0 * fs.clamp(0.9, 1.2);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('A finished 3 × 3',
                style:
                    TextStyle(fontSize: 18 * fs, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            ...List.generate(3, (r) {
              return Row(
                children: List.generate(3, (c) {
                  final on = shaded[r][c];
                  return Container(
                    width: cellSize,
                    height: cellSize,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: on ? scheme.onSurface : Colors.transparent,
                      border: Border.all(
                          color: scheme.outline.withValues(alpha: .7)),
                    ),
                    child: Text(
                      '${nums[r][c]}',
                      style: TextStyle(
                        fontSize: cellSize * 0.46,
                        fontWeight: FontWeight.w700,
                        color: on
                            ? scheme.surface.withValues(alpha: .55)
                            : scheme.onSurface,
                      ),
                    ),
                  );
                }),
              );
            }),
            const SizedBox(height: 12),
            Text(
              'The bottom row is 1 1 1 — three the same, so the middle one '
              'stays and the outer two are shaded. Nothing shaded touches '
              'anything else shaded, and all the pale squares still join up '
              'through the middle.',
              style: TextStyle(fontSize: 15.5 * fs, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
