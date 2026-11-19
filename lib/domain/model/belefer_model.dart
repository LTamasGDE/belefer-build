/// A Belefér saját nyelvi modellje: a telefonon fut, internet nélkül.
///
/// Magyar (és banki értesítéseknél angol) pénzügyi szövegekre tanított,
/// betűcsoport-alapú modell, néhány „fejjel”:
/// - `category`: melyik kategória (szövegből, kereskedőből, blokkból);
/// - `intent`: rögzítés, új ismétlődő tétel, lemondás vagy módosítás;
/// - `status`: a banki értesítés kiadás, bevétel, sikertelen fizetés, saját
///   számlák közötti mozgás vagy egyéb;
/// - `title`: a mondat mely szavai alkotják a megnevezést.
///
/// A tanítás a `tool/model/train.py`-jal történik; a súlyok az
/// `assets/model/belefer_model.bin` fájlban vannak.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'features.dart';

/// Az alkalmazás által használt modell (`null`: csak a szabályalapú
/// értelmező dolgozik, pl. a tesztekben).
BeleferModel? currentModel;

/// Egy előrejelzés: címkék és valószínűségek.
class ModelPrediction {
  ModelPrediction(this.labels, this.probabilities);

  final List<String> labels;
  final List<double> probabilities;

  int get _bestIndex {
    var best = 0;
    for (var i = 1; i < probabilities.length; i++) {
      if (probabilities[i] > probabilities[best]) best = i;
    }
    return best;
  }

  String get best => labels[_bestIndex];
  double get confidence =>
      probabilities.isEmpty ? 0 : probabilities[_bestIndex];

  double probabilityOf(String label) {
    final index = labels.indexOf(label);
    return index < 0 ? 0 : probabilities[index];
  }

  /// Csak a megengedett címkék közül, újranormálva.
  ModelPrediction restrictedTo(Set<String> allowed) {
    final kept = <String>[];
    final probs = <double>[];
    for (var i = 0; i < labels.length; i++) {
      if (allowed.contains(labels[i])) {
        kept.add(labels[i]);
        probs.add(probabilities[i]);
      }
    }
    final total = probs.fold<double>(0, (sum, p) => sum + p);
    return ModelPrediction(kept, [
      for (final p in probs) total > 0 ? p / total : 0,
    ]);
  }
}

/// Egy fej: lineáris modell a hash-elt jellemzőkön (kvantált súlyokkal).
class ModelHead {
  ModelHead._({
    required this.name,
    required this.perToken,
    required this.labels,
    required this.scale,
    required this.bias,
    required this.columns,
    required this.labelIndexes,
    required this.weights,
  });

  final String name;

  /// Szavanként (a megnevezés-jelölő), nem a teljes szövegre.
  final bool perToken;
  final List<String> labels;
  final double scale;
  final Float64List bias;

  /// Rendezett oszlopindexek; egy oszlophoz több címke is tartozhat.
  final Int32List columns;
  final Uint8List labelIndexes;
  final Int8List weights;

  int _firstAtOrAfter(int column) {
    var low = 0;
    var high = columns.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (columns[middle] < column) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  /// Valószínűségek a hash-indexekből.
  List<double> probabilities(List<int> buckets, double weight) {
    final sums = List<int>.filled(labels.length, 0);
    for (final column in buckets) {
      for (
        var k = _firstAtOrAfter(column);
        k < columns.length && columns[k] == column;
        k++
      ) {
        sums[labelIndexes[k]] += weights[k];
      }
    }
    final logits = [
      for (var c = 0; c < labels.length; c++)
        bias[c] + scale * weight * sums[c],
    ];
    final top = logits.reduce(math.max);
    final exps = [for (final logit in logits) math.exp(logit - top)];
    final total = exps.fold<double>(0, (sum, value) => sum + value);
    return [for (final value in exps) value / total];
  }
}

class BeleferModel {
  BeleferModel._(this.version, this.dimBits, this.flags, this.heads);

  final int version;
  final int dimBits;

  /// Szólisták a megnevezés-jelölőhöz (töltelékszavak, igék, dátumszavak).
  final Map<String, Set<String>> flags;
  final Map<String, ModelHead> heads;

  /// A modellfájl beolvasása.
  factory BeleferModel.parse(Uint8List bytes) {
    final reader = _Reader(bytes);
    final magic = ascii.decode(reader.bytes(4));
    if (magic != 'BLFM') {
      throw const FormatException('Nem Belefér-modell.');
    }
    final version = reader.uint16();
    final dimBits = reader.uint8();
    final flagCount = reader.uint8();
    final flags = <String, Set<String>>{};
    for (var i = 0; i < flagCount; i++) {
      final name = reader.shortString();
      final raw = ascii.decode(reader.bytes(reader.uint32()));
      flags[name] = raw.isEmpty ? <String>{} : raw.split('\n').toSet();
    }
    final headCount = reader.uint8();
    final heads = <String, ModelHead>{};
    for (var h = 0; h < headCount; h++) {
      final name = reader.shortString();
      final kind = reader.uint8();
      final labelCount = reader.uint8();
      final labels = [
        for (var i = 0; i < labelCount; i++) reader.shortString(),
      ];
      final scale = reader.float32();
      final bias = Float64List(labelCount);
      for (var i = 0; i < labelCount; i++) {
        bias[i] = reader.float32();
      }
      final count = reader.uint32();
      final columns = Int32List(count);
      final labelIndexes = Uint8List(count);
      final weights = Int8List(count);
      var column = 0;
      for (var i = 0; i < count; i++) {
        column += reader.varint();
        columns[i] = column;
        labelIndexes[i] = reader.uint8();
        weights[i] = reader.int8();
      }
      heads[name] = ModelHead._(
        name: name,
        perToken: kind == 1,
        labels: labels,
        scale: scale,
        bias: bias,
        columns: columns,
        labelIndexes: labelIndexes,
        weights: weights,
      );
    }
    return BeleferModel._(version, dimBits, flags, heads);
  }

  /// A szöveg besorolása egy fejjel (`category`, `intent`, `status`).
  ModelPrediction classify(String head, String text) {
    final model = heads[head];
    if (model == null || model.perToken) {
      throw ArgumentError.value(head, 'head');
    }
    final vector = vectorize(sequenceFeatures(modelWords(text)), dimBits);
    return ModelPrediction(
      model.labels,
      model.probabilities(vector.buckets, vector.weight),
    );
  }

  /// Szavanként: mennyire valószínű, hogy a megnevezés része.
  ///
  /// A [tokens] a `tokenize` egyszerűsített (kisbetűs, ékezet nélküli) alakjai.
  List<double> titleProbabilities(List<String> tokens) {
    final model = heads['title'];
    if (model == null) return List<double>.filled(tokens.length, 0);
    final titleIndex = model.labels.indexOf('t');
    return [
      for (var i = 0; i < tokens.length; i++)
        () {
          final vector = vectorize(tokenFeatures(tokens, i, flags), dimBits);
          return model.probabilities(vector.buckets, vector.weight)[titleIndex];
        }(),
    ];
  }

  /// A betanított súlyok száma (a beállításokban látszik).
  int get weightCount =>
      heads.values.fold(0, (sum, head) => sum + head.columns.length);
}

class _Reader {
  _Reader(this._bytes) : _data = ByteData.sublistView(_bytes);

  final Uint8List _bytes;
  final ByteData _data;
  var _offset = 0;

  Uint8List bytes(int count) {
    final result = Uint8List.sublistView(_bytes, _offset, _offset + count);
    _offset += count;
    return result;
  }

  int uint8() => _data.getUint8(_offset++);

  int int8() => _data.getInt8(_offset++);

  int uint16() {
    final value = _data.getUint16(_offset, Endian.little);
    _offset += 2;
    return value;
  }

  int uint32() {
    final value = _data.getUint32(_offset, Endian.little);
    _offset += 4;
    return value;
  }

  double float32() {
    final value = _data.getFloat32(_offset, Endian.little);
    _offset += 4;
    return value;
  }

  int varint() {
    var result = 0;
    var shift = 0;
    while (true) {
      final byte = uint8();
      result |= (byte & 0x7F) << shift;
      if (byte & 0x80 == 0) return result;
      shift += 7;
    }
  }

  String shortString() => ascii.decode(bytes(uint8()));
}
