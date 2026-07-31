library;

import 'package:flutter/material.dart';
import '../engine/hitori_engine.dart';
import '../models/game_state.dart';
import '../services/daily_puzzle.dart';
import '../services/settings.dart';
import '../services/progress.dart';
import '../services/ads.dart';
import '../services/iap.dart';
import '../services/audio.dart';
import 'game_screen.dart';
import 'settings_screen.dart';
import 'how_to_play.dart';

class HomeScreen extends StatefulWidget {
  final Settings settings;
  final Progress progress;
  final AdService ads;
  final IapService iap;
  const HomeScreen({
    super.key,
    required this.settings,
    required this.progress,
    required this.ads,
    required this.iap,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // First run: show how-to-play. Hitori's rules are genuinely unfamiliar,
    // and a grid of numbers with no explanation is an immediate uninstall.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      AudioService.instance.playMusic(Music.menu);
      if (!widget.settings.seenTutorial && mounted) {
        await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => HowToPlayScreen(settings: widget.settings)));
        await widget.settings.markTutorialSeen();
      }
    });
  }

  Future<void> _open(GameState g, String title, {DateTime? daily}) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GameScreen(
        game: g,
        settings: widget.settings,
        progress: widget.progress,
        ads: widget.ads,
        title: title,
        dailyDate: daily,
      ),
    ));
    if (!mounted) return;
    AudioService.instance.playMusic(Music.menu);
    setState(() {});
  }

  Future<void> _playDaily() async {
    if (_busy) return;
    setState(() => _busy = true);
    final today = DateTime.now();
    try {
      final p = DailyPuzzle.forDate(today);
      if (!mounted) return;
      setState(() => _busy = false);
      await _open(GameState(p), "Today's Puzzle", daily: today);
    } on GenerationFailure {
      if (!mounted) return;
      setState(() => _busy = false);
      _fail();
    }
  }

  Future<void> _playPractice(Difficulty d) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final seed = DateTime.now().millisecondsSinceEpoch & 0x7FFFFFFF;
      final p = DailyPuzzle.practice(difficulty: d, seed: seed);
      if (!mounted) return;
      setState(() => _busy = false);
      await _open(GameState(p), d.label);
    } on GenerationFailure {
      if (!mounted) return;
      setState(() => _busy = false);
      _fail();
    }
  }

  void _fail() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not build that puzzle. Please try again.',
            style: TextStyle(fontSize: 17))));
  }

  Future<void> _resume() async {
    final raw = widget.progress.loadGame();
    if (raw == null) return;
    final g = GameState.decode(raw);
    if (g == null) {
      // Corrupt save: drop it quietly rather than showing an error nobody can
      // act on.
      await widget.progress.clearSavedGame();
      if (mounted) setState(() {});
      return;
    }
    await _open(g, 'Continue');
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    final fs = s.fontScale;
    final scheme = Theme.of(context).colorScheme;
    final today = DateTime.now();
    final doneToday = widget.progress.isComplete(today);
    final streak = widget.progress.currentStreak;
    final saved = widget.progress.loadGame() != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hitori'),
        actions: [
          IconButton(
            iconSize: 28,
            tooltip: 'How to play',
            icon: const Icon(Icons.help_outline),
            onPressed: () {
              AudioService.instance.play(Sfx.buttonTap);
              Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => HowToPlayScreen(settings: s)));
            },
          ),
          IconButton(
            iconSize: 28,
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () async {
              AudioService.instance.play(Sfx.buttonTap);
              await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => SettingsScreen(
                      settings: s,
                      progress: widget.progress,
                      iap: widget.iap)));
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Text(
              'Shade out the repeated numbers.',
              style: TextStyle(fontSize: 18 * fs, height: 1.35),
            ),
            const SizedBox(height: 18),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text("Today's puzzle",
                        style: TextStyle(
                            fontSize: 22 * fs, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(_prettyDate(today),
                        style: TextStyle(fontSize: 16 * fs)),
                    const SizedBox(height: 14),
                    if (doneToday)
                      Row(
                        children: [
                          Icon(Icons.check_circle,
                              size: 30, color: scheme.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('Finished — well done',
                                style: TextStyle(fontSize: 18 * fs)),
                          ),
                        ],
                      )
                    else
                      FilledButton(
                        onPressed: _busy ? null : _playDaily,
                        child:
                            Text('Play', style: TextStyle(fontSize: 20 * fs)),
                      ),
                    if (doneToday) ...[
                      const SizedBox(height: 10),
                      OutlinedButton(
                        onPressed: _busy ? null : _playDaily,
                        child: Text('Play again',
                            style: TextStyle(fontSize: 18 * fs)),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            if (saved) ...[
              const SizedBox(height: 14),
              FilledButton.tonal(
                onPressed: _resume,
                child: Text('Continue where you left off',
                    style: TextStyle(fontSize: 19 * fs)),
              ),
            ],

            const SizedBox(height: 26),
            Text('Practice',
                style:
                    TextStyle(fontSize: 21 * fs, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('No clock pressure — take as long as you like.',
                style: TextStyle(fontSize: 15.5 * fs)),
            const SizedBox(height: 12),
            ...Difficulty.all.map((d) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => _playPractice(d),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(d.label, style: TextStyle(fontSize: 19 * fs)),
                        Text('${d.size} × ${d.size}',
                            style: TextStyle(
                                fontSize: 16 * fs,
                                color:
                                    scheme.onSurface.withValues(alpha: .7))),
                      ],
                    ),
                  ),
                )),

            const SizedBox(height: 22),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _stat('Streak', '$streak', 'days', fs),
                    _stat('Solved', '${widget.progress.totalPuzzles}', '', fs),
                    _stat('Best streak', '${widget.progress.bestStreak}',
                        'days', fs),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value, String unit, double fs) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              style:
                  TextStyle(fontSize: 27 * fs, fontWeight: FontWeight.w700)),
          Text(label, style: TextStyle(fontSize: 14.5 * fs)),
          if (unit.isNotEmpty)
            Text(unit, style: TextStyle(fontSize: 13 * fs)),
        ],
      );

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];
  static const _days = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday', 'Sunday'
  ];

  /// Written out in full — abbreviations like "Tue 3 Sep" are harder to read
  /// at a glance and save nothing on a screen this size.
  String _prettyDate(DateTime d) =>
      '${_days[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';
}
