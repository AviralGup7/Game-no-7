/// Sound effects and background music.
///
/// Policy, derived from the same accessibility thesis as the rest of the app:
///
///   * MUSIC DEFAULTS TO OFF. Audio that begins without being asked for is an
///     uninstall trigger for older players — many are in shared rooms, care
///     settings, or wearing hearing aids. It is opt-in, and the choice sticks.
///   * SFX default ON but are quiet and mono. They confirm an action; they are
///     not the experience.
///   * A wrong entry plays a soft click, never a buzzer. Being scolded by the
///     interface is the fastest way to make someone stop playing.
///   * Every playback call is fire-and-forget and swallows errors. Audio must
///     NEVER be able to break the game — a codec failure on some OEM device
///     should cost silence, not a crash.
///   * `AudioService.instance` falls back to a SILENT no-op service when the
///     app has not installed one (widget tests, or a plugin that failed to
///     register). Nothing in the UI has to null-check.
library;

import 'package:audioplayers/audioplayers.dart';
import 'settings.dart';

enum Sfx {
  /// A cell is shaded out.
  shade('sfx/shade.ogg'),

  /// Alternate shade sound. Alternating two samples stops a run of quick
  /// marks sounding like a machine gun.
  shadeAlt('sfx/shade_alt.ogg'),

  /// A cell is ringed as definitely-stays.
  circle('sfx/circle.ogg'),

  /// A mark is cleared.
  erase('sfx/erase.ogg'),

  /// A mark contradicts the answer. Deliberately a soft click, never a
  /// buzzer - being scolded by the interface is the fastest way to make
  /// someone stop playing.
  wrong('sfx/wrong.ogg'),

  /// Puzzle finished.
  puzzleComplete('sfx/puzzle_complete.ogg'),

  /// Daily streak extended.
  streakUp('sfx/streak_up.ogg'),

  /// A hint was shown.
  hintUsed('sfx/hint_used.ogg'),

  /// Any ordinary button.
  buttonTap('sfx/button_tap.ogg'),

  /// Leaving a screen.
  navigateBack('sfx/navigate_back.ogg');

  final String path;
  const Sfx(this.path);
}

enum Music {
  menu('music/music_menu.ogg'),
  gameplay('music/music_gameplay.ogg');

  final String path;
  const Music(this.path);
}

class AudioService {
  /// Null in the silent fallback used by tests.
  final Settings? settings;

  AudioService(Settings this.settings);
  AudioService.silent() : settings = null;

  static AudioService? _installed;

  /// Never null: returns a silent no-op service until [install] is called.
  static AudioService get instance => _installed ??= AudioService.silent();

  static void install(AudioService s) => _installed = s;

  /// A small pool so overlapping effects (rapid taps) don't cut each other off.
  final List<AudioPlayer> _sfxPool = [];
  AudioPlayer? _music;
  int _next = 0;
  Music? _current;
  bool _ready = false;

  bool get isReady => _ready;

  Future<void> init() async {
    if (settings == null) return; // silent service: stays inert
    try {
      for (var i = 0; i < 3; i++) {
        final p = AudioPlayer(playerId: 'sfx_$i');
        await p.setReleaseMode(ReleaseMode.stop);
        await p.setPlayerMode(PlayerMode.lowLatency);
        await p.setVolume(0.55);
        _sfxPool.add(p);
      }
      final m = AudioPlayer(playerId: 'music');
      await m.setReleaseMode(ReleaseMode.loop);
      await m.setVolume(0.32);
      _music = m;
      _ready = true;
    } catch (_) {
      _ready = false; // audio unavailable: the game still works, silently
    }
  }

  /// Fire-and-forget. Never awaited by the UI, never throws.
  void play(Sfx s) {
    if (!_ready || settings?.sound != true || _sfxPool.isEmpty) return;
    final player = _sfxPool[_next];
    _next = (_next + 1) % _sfxPool.length;
    player.play(AssetSource(s.path)).catchError((_) {});
  }

  int _placeToggle = 0;

  /// Play a shading click, alternating between two samples.
  ///
  /// A run of quick marks played from one sample sounds like a machine gun;
  /// alternating two keeps it soft.
  void playShade() {
    _placeToggle ^= 1;
    play(_placeToggle == 0 ? Sfx.shade : Sfx.shadeAlt);
  }

  Future<void> playMusic(Music m) async {
    if (!_ready || settings?.music != true) return;
    if (_current == m) return;
    _current = m;
    try {
      await _music?.stop();
      await _music?.play(AssetSource(m.path));
    } catch (_) {/* silence on failure */}
  }

  Future<void> stopMusic() async {
    _current = null;
    try {
      await _music?.stop();
    } catch (_) {}
  }

  /// Called when the user toggles the music switch in Settings.
  Future<void> onMusicSettingChanged(bool enabled, Music resume) async {
    if (enabled) {
      _current = null;
      await playMusic(resume);
    } else {
      await stopMusic();
    }
  }

  Future<void> pauseForBackground() async {
    try {
      await _music?.pause();
    } catch (_) {}
  }

  Future<void> resumeFromBackground() async {
    if (settings?.music != true || _current == null) return;
    try {
      await _music?.resume();
    } catch (_) {}
  }

  void dispose() {
    for (final p in _sfxPool) {
      p.dispose();
    }
    _sfxPool.clear();
    _music?.dispose();
    _music = null;
    _ready = false;
  }
}
