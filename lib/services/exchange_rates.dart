import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Devizaárfolyamok forintra (az Európai Központi Bank napi árfolyamai az
/// ingyenes Frankfurter szolgáltatáson keresztül), napi gyorsítótárral.
abstract class ExchangeRates {
  /// 1 egység [currency] hány forint; `null`, ha nem érhető el.
  Future<double?> hufPer(String currency);
}

class FrankfurterRates implements ExchangeRates {
  FrankfurterRates({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;
  final Map<String, (DateTime, double)> _cache = {};

  @override
  Future<double?> hufPer(String currency) async {
    final code = currency.toUpperCase();
    if (code == 'HUF') return 1;
    final cached = _cache[code];
    if (cached != null &&
        DateTime.now().difference(cached.$1) < const Duration(hours: 12)) {
      return cached.$2;
    }
    for (final url in [
      'https://api.frankfurter.dev/v1/latest?base=$code&symbols=HUF',
      'https://api.frankfurter.app/latest?from=$code&to=HUF',
    ]) {
      try {
        final response = await _http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 10));
        if (response.statusCode != 200) continue;
        final decoded = jsonDecode(response.body);
        final rate = ((decoded as Map)['rates'] as Map?)?['HUF'];
        if (rate is num && rate > 0) {
          _cache[code] = (DateTime.now(), rate.toDouble());
          return rate.toDouble();
        }
      } on Object {
        continue;
      }
    }
    return null;
  }
}

/// Árfolyam nélküli változat (tesztekhez).
class NoExchangeRates implements ExchangeRates {
  const NoExchangeRates();

  @override
  Future<double?> hufPer(String currency) async =>
      currency.toUpperCase() == 'HUF' ? 1 : null;
}
