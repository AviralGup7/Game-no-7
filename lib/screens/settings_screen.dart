library;

import 'package:flutter/material.dart';
import '../services/settings.dart';
import '../services/progress.dart';
import '../services/iap.dart';
import '../services/audio.dart';

class SettingsScreen extends StatelessWidget {
  final Settings settings;
  final Progress progress;
  final IapService iap;
  const SettingsScreen({
    super.key,
    required this.settings,
    required this.progress,
    required this.iap,
  });

  String _fmt(int s) {
    if (s < 60) return '${s}s';
    final m = s ~/ 60;
    return m < 60 ? '${m}m' : '${m ~/ 60}h ${m % 60}m';
  }

  @override
  Widget build(BuildContext context) {
    final s = settings;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([s, iap, progress]),
          builder: (context, _) {
            final fs = s.fontScale;
            TextStyle label() =>
                TextStyle(fontSize: 19 * fs, fontWeight: FontWeight.w600);
            TextStyle sub() => TextStyle(fontSize: 14.5 * fs);

            return ListView(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
              children: [
                Text('Text size', style: label()),
                // Live preview: the effect is visible while dragging, so the
                // slider is not a guess.
                Center(
                  child: Text('7',
                      style: TextStyle(
                          fontSize: 42 * fs, fontWeight: FontWeight.bold)),
                ),
                Slider(
                  value: s.fontScale,
                  min: 0.85,
                  max: 1.6,
                  divisions: 15,
                  label: '${(s.fontScale * 100).round()}%',
                  onChanged: s.setFontScale,
                ),
                const Divider(height: 28),

                SwitchListTile(
                  title: Text('Highlight row and column', style: label()),
                  subtitle: Text(
                      'Shade the lines through the square you tapped',
                      style: sub()),
                  value: s.highlightLine,
                  onChanged: s.setHighlightLine,
                ),
                SwitchListTile(
                  title: Text('Show mistakes', style: label()),
                  subtitle:
                      Text('Mark a wrong square straight away', style: sub()),
                  value: s.showMistakes,
                  onChanged: s.setShowMistakes,
                ),
                SwitchListTile(
                  title: Text('Ring squares next to shaded ones',
                      style: label()),
                  subtitle: Text(
                      'Two shaded squares can never touch, so these are '
                      'automatic',
                      style: sub()),
                  value: s.autoCircle,
                  onChanged: s.setAutoCircle,
                ),
                SwitchListTile(
                  title: Text('Extra contrast', style: label()),
                  subtitle: Text('Stronger black and white', style: sub()),
                  value: s.highContrast,
                  onChanged: s.setHighContrast,
                ),
                SwitchListTile(
                  title: Text('Dark background', style: label()),
                  value: s.darkMode,
                  onChanged: s.setDarkMode,
                ),
                SwitchListTile(
                  title: Text('Vibration', style: label()),
                  value: s.haptics,
                  onChanged: s.setHaptics,
                ),
                SwitchListTile(
                  title: Text('Sound effects', style: label()),
                  subtitle: Text('Quiet taps and chimes', style: sub()),
                  value: s.sound,
                  onChanged: (v) {
                    s.setSound(v);
                    if (v) AudioService.instance.play(Sfx.buttonTap);
                  },
                ),
                SwitchListTile(
                  title: Text('Background music', style: label()),
                  subtitle: Text('Off unless you turn it on', style: sub()),
                  value: s.music,
                  onChanged: (v) {
                    s.setMusic(v);
                    AudioService.instance
                        .onMusicSettingChanged(v, Music.menu);
                  },
                ),

                const Divider(height: 28),
                if (!s.adFree)
                  Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      title: Text('Remove ads', style: label()),
                      subtitle: Text(
                          'One payment, no subscription. Hints still work.',
                          style: sub()),
                      trailing: FilledButton(
                        onPressed: iap.available ? iap.buyRemoveAds : null,
                        child: Text(iap.priceString ?? 'Buy'),
                      ),
                    ),
                  )
                else
                  ListTile(
                    leading: const Icon(Icons.check_circle, size: 30),
                    title: Text('Ads removed — thank you', style: label()),
                  ),
                TextButton(
                  onPressed: iap.restore,
                  child: Text('Restore purchase',
                      style: TextStyle(fontSize: 16.5 * fs)),
                ),

                const Divider(height: 28),
                Text('Your progress', style: label()),
                const SizedBox(height: 8),
                _stat('Current streak', '${progress.currentStreak} days', fs),
                _stat('Best streak', '${progress.bestStreak} days', fs),
                _stat('Puzzles solved', '${progress.totalPuzzles}', fs),
                _stat('Time played', _fmt(progress.totalSeconds), fs),
                if (progress.bestTimes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Best times', style: label()),
                  const SizedBox(height: 6),
                  ...progress.bestTimes.entries.map((e) => _stat(
                      e.key,
                      '${(e.value ~/ 60).toString().padLeft(2, '0')}:'
                          '${(e.value % 60).toString().padLeft(2, '0')}',
                      fs)),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _stat(String k, String v, double fs) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(child: Text(k, style: TextStyle(fontSize: 17 * fs))),
            Text(v,
                style:
                    TextStyle(fontSize: 17 * fs, fontWeight: FontWeight.bold)),
          ],
        ),
      );
}
