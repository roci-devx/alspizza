import 'package:flutter/foundation.dart';
import 'package:flutter_stripe/flutter_stripe.dart' as stripe;

/// Native Stripe PaymentSheet (cards + Apple Pay + Google Pay) for iOS/Android.
/// Kept in its own file with a prefixed import because flutter_stripe still
/// builds on package:flutter/material while the app uses material_ui.
Future<bool> presentStripePaymentSheet({
  required String clientSecret,
  required String publishableKey,
  required String merchantName,
  String? appleMerchantId,
  bool testEnv = true,
}) async {
  if (kIsWeb) return false;
  stripe.Stripe.publishableKey = publishableKey;
  if (appleMerchantId != null) stripe.Stripe.merchantIdentifier = appleMerchantId;
  stripe.Stripe.urlScheme = 'alspizza';
  await stripe.Stripe.instance.applySettings();
  await stripe.Stripe.instance.initPaymentSheet(
    paymentSheetParameters: stripe.SetupPaymentSheetParameters(
      paymentIntentClientSecret: clientSecret,
      merchantDisplayName: merchantName,
      applePay: const stripe.PaymentSheetApplePay(merchantCountryCode: 'US'),
      googlePay: stripe.PaymentSheetGooglePay(merchantCountryCode: 'US', currencyCode: 'USD', testEnv: testEnv),
    ),
  );
  try {
    await stripe.Stripe.instance.presentPaymentSheet();
    return true;
  } on stripe.StripeException catch (e) {
    if (e.error.code == stripe.FailureCode.Canceled) return false;
    throw Exception(e.error.localizedMessage ?? 'Your payment didn’t go through. Try another card.');
  }
}
