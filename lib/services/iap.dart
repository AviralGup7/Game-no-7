/// Single non-consumable purchase: remove ads. One-time, never a subscription.
///
/// LIMITATION, stated plainly: there is NO server-side receipt verification.
/// The app trusts the purchase stream, so a rooted device can spoof ad removal.
///
/// That is a deliberate trade for a one-off unlock at this price point — the
/// alternative is a backend, which means running a server, holding user data,
/// and breaking the app's "works completely offline" promise. The downside is
/// bounded: the worst case is someone gets an ad-free app for free, not a
/// revenue leak that scales.
///
/// If this ever guards anything of real value, verify with the Play Developer
/// API before granting the entitlement.
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'settings.dart';

class IapService extends ChangeNotifier {
  static const productId = 'remove_ads';
  final Settings settings;
  IapService(this.settings);

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  ProductDetails? _product;
  bool _available = false;

  String? get priceString => _product?.price;
  bool get available => _available;

  Future<void> init() async {
    try {
      _available = await _iap.isAvailable();
      if (!_available) return;
      final r = await _iap.queryProductDetails({productId});
      if (r.productDetails.isNotEmpty) _product = r.productDetails.first;
      _sub = _iap.purchaseStream.listen(_onPurchases, onError: (_) {});
      notifyListeners();
    } catch (_) {/* store unavailable: app still works */}
  }

  void _onPurchases(List<PurchaseDetails> list) {
    for (final p in list) {
      if (p.status == PurchaseStatus.purchased ||
          p.status == PurchaseStatus.restored) {
        if (p.productID == productId) settings.setAdFree(true);
      }
      if (p.pendingCompletePurchase) _iap.completePurchase(p);
    }
    notifyListeners();
  }

  Future<void> buyRemoveAds() async {
    final p = _product;
    if (p == null) return;
    await _iap.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: p));
  }

  Future<void> restore() => _iap.restorePurchases();

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
