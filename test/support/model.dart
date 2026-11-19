import 'dart:io';

import 'package:belefer/domain/model/belefer_model.dart';

BeleferModel? _loaded;

/// A betanított modell a projekt fájljából (a tesztek a projekt gyökeréből
/// futnak).
BeleferModel loadTestModel() => _loaded ??= BeleferModel.parse(
  File('assets/model/belefer_model.bin').readAsBytesSync(),
);
