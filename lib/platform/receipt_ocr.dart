import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';

import '../domain/quick_entry/ocr_layout.dart';
import '../services/platform_services.dart';

/// Blokk- és számlabeolvasás: kép a kamerából vagy a galériából, illetve
/// PDF vagy képfájl; a szövegfelismerés a telefonon fut (ML Kit, internet
/// nélkül).
class MlKitReceiptScanner implements ReceiptScanner {
  final ImagePicker _imagePicker = ImagePicker();

  @override
  Future<ReceiptCapture?> capture(ReceiptSource source) async {
    switch (source) {
      case ReceiptSource.camera:
      case ReceiptSource.gallery:
        final image = await _imagePicker.pickImage(
          source: source == ReceiptSource.camera
              ? ImageSource.camera
              : ImageSource.gallery,
          maxWidth: 2400,
          maxHeight: 3200,
          imageQuality: 92,
        );
        if (image == null) return null;
        return ReceiptCapture(
          text: await _recognizeFile(image.path),
          imagePath: image.path,
        );
      case ReceiptSource.file:
        final file = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: const [
            'pdf',
            'jpg',
            'jpeg',
            'png',
            'heic',
            'webp',
          ],
          dialogTitle: 'Számla vagy blokk kiválasztása',
        );
        if (file == null) return null;
        final extension = file.extension?.toLowerCase();
        if (extension == 'pdf') {
          final bytes = await file.readAsBytes();
          return ReceiptCapture(
            text: await _recognizePdf(bytes),
            fileName: file.name,
          );
        }
        final path =
            file.path ?? await _writeTemp(await file.readAsBytes(), file.name);
        return ReceiptCapture(
          text: await _recognizeFile(path),
          imagePath: path,
          fileName: file.name,
        );
    }
  }

  /// Egy képfájl szövegének felismerése, soronként rendezve.
  Future<String> recognizeImageFile(String path) => _recognizeFile(path);

  Future<String> _recognizeFile(String path) async {
    final recognizer = TextRecognizer();
    try {
      final result = await recognizer.processImage(
        InputImage.fromFilePath(path),
      );
      return arrangeOcrLines([
        for (final block in result.blocks)
          for (final line in block.lines)
            OcrLine(
              line.text,
              line.boundingBox.left,
              line.boundingBox.top,
              line.boundingBox.right,
              line.boundingBox.bottom,
            ),
      ]);
    } finally {
      await recognizer.close();
    }
  }

  /// A PDF első (legfeljebb három) oldala képpé alakítva, majd felismerve.
  Future<String> _recognizePdf(Uint8List bytes) async {
    final texts = <String>[];
    var page = 0;
    try {
      await for (final raster in Printing.raster(bytes, dpi: 220)) {
        final png = await raster.toPng();
        final path = await _writeTemp(png, 'szamla_$page.png');
        texts.add(await _recognizeFile(path));
        page++;
        if (page >= 3) break;
      }
    } on Object {
      if (texts.isEmpty) {
        throw const ReceiptScanException(
          'Ezt a PDF-et nem sikerült megnyitni. Próbáld képernyőképpel.',
        );
      }
    }
    return texts.join('\n');
  }

  Future<String> _writeTemp(Uint8List bytes, String name) async {
    final directory = await getTemporaryDirectory();
    final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final file = File(
      '${directory.path}/belefer_${DateTime.now().millisecondsSinceEpoch}_$safe',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}
