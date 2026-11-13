import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

class DosyaUretici {
  static String _turkceAsciiDonustur(String metin) {
    return metin
        .replaceAll('ğ', 'g')
        .replaceAll('Ğ', 'G')
        .replaceAll('ü', 'u')
        .replaceAll('Ü', 'U')
        .replaceAll('ş', 's')
        .replaceAll('Ş', 'S')
        .replaceAll('ı', 'i')
        .replaceAll('İ', 'I')
        .replaceAll('ö', 'o')
        .replaceAll('Ö', 'O')
        .replaceAll('ç', 'c')
        .replaceAll('Ç', 'C');
  }

  static Future<void> pdfOlusturVePaylas(String baslik, String icerik) async {
    final pdf = pw.Document();
    final temizBaslik = _turkceAsciiDonustur(baslik);
    final temizIcerik = _turkceAsciiDonustur(icerik);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Text(
                temizBaslik,
                style: const pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 12),
            pw.Text(
              temizIcerik,
              style: const pw.TextStyle(fontSize: 12, lineSpacing: 1.5),
            ),
          ];
        },
      ),
    );

    final dir = await getTemporaryDirectory();
    final dosyaAdi = "OSIS_Belge_${DateTime.now().millisecondsSinceEpoch}.pdf";
    final file = File("${dir.path}/$dosyaAdi");
    await file.writeAsBytes(await pdf.save());

    await Share.shareXFiles([XFile(file.path)], text: baslik);
  }

  static String _xmlKacis(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  static Future<void> wordOlusturVePaylas(String baslik, String icerik) async {
    final archive = Archive();

    const contentTypes =
        '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-package.wordprocessingml.document.main+xml"/>
</Types>''';

    const rels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''';

    final satirlar = icerik.split('\n');
    final paragrafXml = StringBuffer();
    paragrafXml.writeln(
      '<w:p><w:r><w:rPr><w:b/><w:sz w:val="32"/></w:rPr><w:t>${_xmlKacis(baslik)}</w:t></w:r></w:p>',
    );
    for (final satir in satirlar) {
      paragrafXml.writeln(
        '<w:p><w:r><w:rPr><w:sz w:val="24"/></w:rPr><w:t xml:space="preserve">${_xmlKacis(satir)}</w:t></w:r></w:p>',
      );
    }

    final documentXml =
        '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    $paragrafXml
  </w:body>
</w:document>''';

    void ekle(String yol, String icerikStr) {
      final bytes = utf8.encode(icerikStr);
      archive.addFile(ArchiveFile(yol, bytes.length, bytes));
    }

    ekle('[Content_Types].xml', contentTypes);
    ekle('_rels/.rels', rels);
    ekle('word/document.xml', documentXml);

    final zipBytes = ZipEncoder().encode(archive);
    final dir = await getTemporaryDirectory();
    final dosyaAdi = "OSIS_Belge_${DateTime.now().millisecondsSinceEpoch}.docx";
    final file = File("${dir.path}/$dosyaAdi");
    await file.writeAsBytes(zipBytes);

    await Share.shareXFiles([XFile(file.path)], text: baslik);
  }
}
