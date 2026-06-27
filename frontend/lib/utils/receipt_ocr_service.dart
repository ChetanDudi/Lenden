import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class ReceiptOcrResult {
  final double? amount;
  final DateTime? date;
  final String? place;
  final String rawText;

  ReceiptOcrResult({this.amount, this.date, this.place, required this.rawText});
}

class ReceiptOcrService {
  static final TextRecognizer _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  static final RegExp _totalLineRegex = RegExp(
    r'(total|amount|grand total|net amount|amount paid|amount due|balance due)[^0-9]{0,15}([₹$]|rs\.?|inr)?\s*([\d,]+\.?\d{0,2})',
    caseSensitive: false,
  );

  static final RegExp _currencyNumberRegex = RegExp(
    r'(?:₹|rs\.?|inr)\s*([\d,]+\.?\d{0,2})',
    caseSensitive: false,
  );

  static final RegExp _bareNumberRegex = RegExp(r'\b\d{1,3}(?:,\d{3})*(?:\.\d{1,2})?\b');

  static final List<RegExp> _dateRegexes = [
    RegExp(r'\b(\d{1,2})[/\-](\d{1,2})[/\-](\d{2,4})\b'),
    RegExp(r'\b(\d{4})[/\-](\d{1,2})[/\-](\d{1,2})\b'),
  ];

  static Future<ReceiptOcrResult> extractFromImage(String imagePath) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    final recognizedText = await _recognizer.processImage(inputImage);
    final text = recognizedText.text;

    return ReceiptOcrResult(
      amount: _extractAmount(text),
      date: _extractDate(text),
      place: _extractPlace(recognizedText),
      rawText: text,
    );
  }

  static double? _parseAmount(String raw) {
    final cleaned = raw.replaceAll(',', '');
    return double.tryParse(cleaned);
  }

  static double? _extractAmount(String text) {
    final totalMatch = _totalLineRegex.firstMatch(text);
    if (totalMatch != null) {
      final value = _parseAmount(totalMatch.group(3) ?? '');
      if (value != null && value > 0) return value;
    }

    final currencyMatches = _currencyNumberRegex.allMatches(text).toList();
    if (currencyMatches.isNotEmpty) {
      final values = currencyMatches
          .map((m) => _parseAmount(m.group(1) ?? ''))
          .whereType<double>()
          .where((v) => v > 0)
          .toList();
      if (values.isNotEmpty) {
        values.sort();
        return values.last;
      }
    }

    final bareMatches = _bareNumberRegex.allMatches(text).toList();
    final bareValues = bareMatches
        .map((m) => _parseAmount(m.group(0) ?? ''))
        .whereType<double>()
        .where((v) => v > 1 && v < 10000000)
        .toList();
    if (bareValues.isEmpty) return null;
    bareValues.sort();
    return bareValues.last;
  }

  static DateTime? _extractDate(String text) {
    for (final regex in _dateRegexes) {
      final match = regex.firstMatch(text);
      if (match == null) continue;
      try {
        final parts = [match.group(1)!, match.group(2)!, match.group(3)!]
            .map((p) => int.parse(p))
            .toList();
        int day, month, year;
        if (parts[0] > 31) {
          year = parts[0];
          month = parts[1];
          day = parts[2];
        } else {
          day = parts[0];
          month = parts[1];
          year = parts[2] < 100 ? 2000 + parts[2] : parts[2];
        }
        if (month < 1 || month > 12 || day < 1 || day > 31) continue;
        return DateTime(year, month, day);
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  static String? _extractPlace(RecognizedText recognizedText) {
    for (final block in recognizedText.blocks) {
      final line = block.text.trim();
      if (line.length < 3) continue;
      if (RegExp(r'^\d').hasMatch(line)) continue;
      if (_totalLineRegex.hasMatch(line) || _currencyNumberRegex.hasMatch(line)) continue;
      return line.length > 60 ? line.substring(0, 60) : line;
    }
    return null;
  }

  static void dispose() {
    _recognizer.close();
  }
}
