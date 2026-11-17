import 'package:flutter/material.dart';

/// Egy kategória színe és ikonja.
class CategoryStyle {
  const CategoryStyle(this.color, this.icon);

  final Color color;
  final IconData icon;
}

const CategoryStyle _fallback = CategoryStyle(
  Color(0xFF8C93AE),
  Icons.more_horiz_rounded,
);

const Map<String, CategoryStyle> _styles = {
  // Kiadások: egymástól jól elkülönülő, mindkét témában olvasható színek.
  'housing': CategoryStyle(Color(0xFF4C6FFF), Icons.home_rounded),
  'utilities': CategoryStyle(Color(0xFF9A6BFF), Icons.electric_bolt_rounded),
  'groceries': CategoryStyle(Color(0xFF14B8A6), Icons.shopping_basket_rounded),
  'dining': CategoryStyle(Color(0xFFF2A516), Icons.restaurant_rounded),
  'transport': CategoryStyle(Color(0xFF1EA7E8), Icons.directions_bus_rounded),
  'health': CategoryStyle(Color(0xFFEF5A5A), Icons.favorite_rounded),
  'clothing': CategoryStyle(Color(0xFFE85AA6), Icons.checkroom_rounded),
  'entertainment': CategoryStyle(Color(0xFFFF7A2F), Icons.celebration_rounded),
  'subscriptions': CategoryStyle(
    Color(0xFF6E73F0),
    Icons.subscriptions_rounded,
  ),
  'education': CategoryStyle(Color(0xFF7CB82F), Icons.school_rounded),
  'gifts': CategoryStyle(Color(0xFFC855E0), Icons.card_giftcard_rounded),
  'other_expense': _fallback,
  // Bevételek
  'salary': CategoryStyle(Color(0xFF12A37F), Icons.payments_rounded),
  'side_income': CategoryStyle(Color(0xFF14B8A6), Icons.handyman_rounded),
  'scholarship': CategoryStyle(Color(0xFF6E73F0), Icons.school_rounded),
  'gift_income': CategoryStyle(Color(0xFFC855E0), Icons.redeem_rounded),
  'refund': CategoryStyle(Color(0xFF1EA7E8), Icons.replay_rounded),
  'other_income': _fallback,
};

CategoryStyle categoryStyle(String id) => _styles[id] ?? _fallback;
