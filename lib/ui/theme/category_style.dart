import 'package:flutter/material.dart';

import '../../domain/categories.dart';

/// Egy kategória színe és ikonja.
class CategoryStyle {
  const CategoryStyle(this.color, this.icon);

  final Color color;
  final IconData icon;
}

/// Az ikonkulcsokhoz tartozó ikonok (a beépített és a saját kategóriákhoz).
const Map<String, IconData> categoryIcons = {
  'home': Icons.home_rounded,
  'bolt': Icons.electric_bolt_rounded,
  'basket': Icons.shopping_basket_rounded,
  'restaurant': Icons.restaurant_rounded,
  'bus': Icons.directions_bus_rounded,
  'heart': Icons.favorite_rounded,
  'checkroom': Icons.checkroom_rounded,
  'celebration': Icons.celebration_rounded,
  'subscriptions': Icons.subscriptions_rounded,
  'school': Icons.school_rounded,
  'gift': Icons.card_giftcard_rounded,
  'more': Icons.more_horiz_rounded,
  'payments': Icons.payments_rounded,
  'handyman': Icons.handyman_rounded,
  'redeem': Icons.redeem_rounded,
  'replay': Icons.replay_rounded,
  'star': Icons.star_rounded,
  'pets': Icons.pets_rounded,
  'fitness': Icons.fitness_center_rounded,
  'games': Icons.sports_esports_rounded,
  'travel': Icons.flight_rounded,
  'car': Icons.directions_car_rounded,
  'phone': Icons.smartphone_rounded,
  'wifi': Icons.wifi_rounded,
  'book': Icons.menu_book_rounded,
  'music': Icons.music_note_rounded,
  'coffee': Icons.local_cafe_rounded,
  'beauty': Icons.spa_rounded,
  'baby': Icons.child_friendly_rounded,
  'sports': Icons.sports_soccer_rounded,
  'savings': Icons.savings_rounded,
  'work': Icons.work_rounded,
};

const CategoryStyle _fallback = CategoryStyle(
  Color(0xFF8C93AE),
  Icons.more_horiz_rounded,
);

IconData categoryIconFor(String iconKey) =>
    categoryIcons[iconKey] ?? Icons.more_horiz_rounded;

CategoryStyle categoryStyle(String id) {
  final category = categoryById(id);
  if (category == null) return _fallback;
  return CategoryStyle(
    Color(category.colorValue),
    categoryIconFor(category.iconKey),
  );
}
