import 'package:flutter/material.dart';

/// A Belefér alapszínei. A komponensek a [BeleferColors] témabővítményen
/// és a [ColorScheme]-en keresztül használják őket.
abstract final class Palette {
  // Tintakék
  static const Color ink = Color(0xFF101A3C);
  static const Color ink2 = Color(0xFF1B2754);
  static const Color inkSoft = Color(0xFF555E80);
  static const Color inkMuted = Color(0xFF8A90AA);

  // Meleg törtfehér
  static const Color paper = Color(0xFFF6F1E8);
  static const Color paperRaised = Color(0xFFFFFCF7);
  static const Color paperSunken = Color(0xFFECE4D6);
  static const Color paperLine = Color(0xFFDDD3C2);

  // Éjszakai felületek
  static const Color night = Color(0xFF0A1230);
  static const Color nightRaised = Color(0xFF131C42);
  static const Color nightSunken = Color(0xFF1C275A);
  static const Color nightLine = Color(0xFF2B3770);

  static const Color cream = Color(0xFFF6F0E5);
  static const Color creamSoft = Color(0xFFB5BBD6);

  // Türkiz akcentus
  static const Color teal = Color(0xFF19D3C5);
  static const Color tealBright = Color(0xFF3FE9D9);
  static const Color tealDeep = Color(0xFF007A72);

  // Kiadás és bevétel
  static const Color coral = Color(0xFFD9443C);
  static const Color coralBright = Color(0xFFFF8178);
  static const Color mint = Color(0xFF0E8A66);
  static const Color mintBright = Color(0xFF4FE0A6);

  static const Color danger = Color(0xFFB3261E);
  static const Color dangerBright = Color(0xFFFF8A80);
}
