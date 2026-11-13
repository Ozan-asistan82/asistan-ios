import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class SecilenMedya {
  final String dosyaAdi;
  final String mimeType;
  final String base64Veri;
  final bool pdfMi;

  SecilenMedya({
    required this.dosyaAdi,
    required this.mimeType,
    required this.base64Veri,
    required this.pdfMi,
  });
}

class MultimodalAnaliz {
  static final ImagePicker _picker = ImagePicker();

  static Future<SecilenMedya?> kameradanCek() async {
    final XFile? foto = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (foto == null) return null;
    final bytes = await File(foto.path).readAsBytes();
    return SecilenMedya(
      dosyaAdi: foto.name,
      mimeType: "image/jpeg",
      base64Veri: base64Encode(bytes),
      pdfMi: false,
    );
  }

  static Future<SecilenMedya?> dosyaVeyaGaleriSec() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
    );
    if (result.isEmpty || result.single.path == null) return null;

    final file = File(result.single.path!);
    final bytes = await file.readAsBytes();
    final ext = (result.single.extension ?? "").toLowerCase();
    final bool isPdf = ext == 'pdf';
    final String mime = isPdf
        ? "application/pdf"
        : (ext == 'png' ? "image/png" : "image/jpeg");

    return SecilenMedya(
      dosyaAdi: result.single.name,
      mimeType: mime,
      base64Veri: base64Encode(bytes),
      pdfMi: isPdf,
    );
  }

  static String _temizle(String metin) {
    String temiz = metin.replaceAll('**', '').replaceAll('###', '');
    while (temiz.contains('([') && temiz.contains('))')) {
      int bas = temiz.indexOf('([');
      int son = temiz.indexOf('))', bas);
      if (bas != -1 && son != -1) {
        temiz = temiz.replaceRange(bas, son + 2, '');
      } else {
        break;
      }
    }
    return temiz.trim();
  }

  static Future<String> medyaAnalizEt({
    required String apiKey,
    required SecilenMedya medya,
    required String kullaniciSorusu,
    required String sistemTalimati,
  }) async {
    final uri = Uri.parse(
      utf8.decode(base64Decode("aHR0cHM6Ly9hcGkub3BlbmFpLmNvbS92MS9yZXNwb25zZXM=")),
    );

    final String varsayilanSoru = medya.pdfMi
        ? "Bu belgeyi detaylıca analiz et. Eğer bu bir uçuş planı (OFP) ise kalkış, varış ve yedek meydan ICAO kodlarını, uçuş seviyesini, blok/ekstra yakıt bilgilerini ve tahmini süreyi özetle; ayrıca web arama aracını kullanarak kalkış ve varış meydanlarının anlık METAR/TAF hava durumunu bulup bana kokpit brifingi formatında sesli okunacak şekilde anlat. Başka bir belge ise ana hatlarıyla özetle."
        : "Bu görseldeki kişi, nesne, yazı veya belge nedir? Detaylı şekilde incele, gerekiyorsa web aramasıyla kim veya ne olduğunu doğrula ve bana akıcı bir Türkçe ile anlat.";

    final String soruMetni = kullaniciSorusu.trim().isEmpty ? varsayilanSoru : kullaniciSorusu;

    final Map<String, dynamic> dosyaIcerik = medya.pdfMi
        ? {
            "type": "input_file",
            "filename": medya.dosyaAdi,
            "file_data": "data:application/pdf;base64,${medya.base64Veri}",
          }
        : {
            "type": "input_image",
            "image_url": "data:${medya.mimeType};base64,${medya.base64Veri}",
          };

    final response = await http
        .post(
          uri,
          headers: {
            "Content-Type": "application/json",
            "Authorization": "Bearer ${apiKey.trim()}",
          },
          body: jsonEncode({
            "model": "gpt-4o-mini",
            "instructions": sistemTalimati,
            "tools": [
              {"type": "web_search"}
            ],
            "input": [
              {
                "role": "user",
                "content": [
                  {"type": "input_text", "text": soruMetni},
                  dosyaIcerik,
                ],
              }
            ],
          }),
        )
        .timeout(const Duration(seconds: 35));

    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data['output_text'] != null && data['output_text'].toString().trim().isNotEmpty) {
        return _temizle(data['output_text'].toString());
      }
      final List outputs = data['output'] ?? [];
      for (var item in outputs) {
        if (item['type'] == 'message') {
          final List contents = item['content'] ?? [];
          for (var c in contents) {
            if (c['text'] != null && c['text'].toString().trim().isNotEmpty) {
              return _temizle(c['text'].toString());
            }
          }
        }
      }
      throw Exception("Görsel/belge yanıtı ayrıştırılamadı.");
    } else {
      throw Exception("HTTP ${response.statusCode}: ${response.body}");
    }
  }
}