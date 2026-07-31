/// Ad orchestration.
///
/// Rewarded video only for hints - opt-in, at a moment of real need.
/// Interstitials only AFTER a puzzle completes, never mid-puzzle: a hitori
/// player is holding a half-finished line of deductions in their head, and a
/// full-screen ad destroys that. Capped at 1 per 3 completions with a 150s floor.
///
/// IDs are GOOGLE'S OFFICIAL TEST IDs; replace before release. Real IDs during
/// development risk a policy strike from self-clicks.
library;

import 'dart:io' show Platform;
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'settings.dart';

class AdService {
  final Settings settings;
  AdService(this.settings);

  static const _tInterA = 'ca-app-pub-3940256099942544/1033173712';
  static const _tRewardA = 'ca-app-pub-3940256099942544/5224354917';
  static const _tInterI = 'ca-app-pub-3940256099942544/4411468910';
  static const _tRewardI = 'ca-app-pub-3940256099942544/1712485313';

  String get _interUnit => Platform.isAndroid ? _tInterA : _tInterI;
  String get _rewardUnit => Platform.isAndroid ? _tRewardA : _tRewardI;

  InterstitialAd? _inter;
  RewardedAd? _reward;
  int _sinceAd = 0;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);
  bool _ready = false;

  Future<void> init() async {
    try {
      await MobileAds.instance.initialize();
      _ready = true;
      _loadInter();
      _loadReward();
    } catch (_) {
      _ready = false; // no ads is fine; the game must still work
    }
  }

  void _loadInter() {
    if (!_ready || settings.adFree) return;
    InterstitialAd.load(
      adUnitId: _interUnit,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (a) => _inter = a,
        onAdFailedToLoad: (_) => _inter = null,
      ),
    );
  }

  void _loadReward() {
    if (!_ready) return;
    RewardedAd.load(
      adUnitId: _rewardUnit,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (a) => _reward = a,
        onAdFailedToLoad: (_) => _reward = null,
      ),
    );
  }

  void maybeShowInterstitial() {
    if (settings.adFree) return;
    _sinceAd++;
    if (_sinceAd < 3) return;
    if (DateTime.now().difference(_last).inSeconds < 150) return;
    final a = _inter;
    if (a == null) {
      _loadInter();
      return;
    }
    a.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) { ad.dispose(); _loadInter(); },
      onAdFailedToShowFullScreenContent: (ad, _) { ad.dispose(); _loadInter(); },
    );
    a.show();
    _inter = null;
    _sinceAd = 0;
    _last = DateTime.now();
  }

  /// True if the hint should be granted.
  ///
  /// Two ways this returns true without showing anything:
  ///   * the player BOUGHT ad removal - charging them attention after they
  ///     paid money is the fastest way to make the purchase feel like a con;
  ///   * no ad is loaded - punishing a player for our fill rate earns
  ///     one-star reviews.
  Future<bool> showRewarded() async {
    if (settings.adFree) return true;
    final a = _reward;
    if (a == null) {
      _loadReward();
      return true;
    }
    bool earned = false;
    a.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) { ad.dispose(); _loadReward(); },
      onAdFailedToShowFullScreenContent: (ad, _) { ad.dispose(); _loadReward(); },
    );
    await a.show(onUserEarnedReward: (_, __) => earned = true);
    _reward = null;
    return earned;
  }

  void dispose() {
    _inter?.dispose();
    _reward?.dispose();
  }
}
