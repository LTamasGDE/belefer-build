import 'package:flutter/widgets.dart';

/// A körbevezetés által kiemelt felületelemek kulcsai.
abstract final class TourKeys {
  static final GlobalKey balance = GlobalKey(debugLabel: 'tour-balance');
  static final GlobalKey quickEntry = GlobalKey(debugLabel: 'tour-quick');
  static final GlobalKey forecast = GlobalKey(debugLabel: 'tour-forecast');
  static final GlobalKey breakdown = GlobalKey(debugLabel: 'tour-breakdown');
  static final GlobalKey navigation = GlobalKey(debugLabel: 'tour-nav');
  static final GlobalKey search = GlobalKey(debugLabel: 'tour-search');
}
