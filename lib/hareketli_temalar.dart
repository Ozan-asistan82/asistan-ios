import 'dart:math' as math;
import 'package:flutter/material.dart';

class HareketliArkaPlanPainter extends CustomPainter {
  final int temaTipi; // 0: Uzay, 1: Elektronik Devre (LED), 2: Mekanik Saat / Uzay Araci
  final double animasyonDegeri; // 0.0 - 1.0 arasi surekli dongu
  final Color vurguRengi;
  final Color yildizRengi;

  HareketliArkaPlanPainter({
    required this.temaTipi,
    required this.animasyonDegeri,
    required this.vurguRengi,
    required this.yildizRengi,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (temaTipi == 1) {
      _cizElektronikDevre(canvas, size);
    } else if (temaTipi == 2) {
      _cizMekanikSaatMekanizmasi(canvas, size);
    } else {
      _cizUzayYildizlari(canvas, size);
    }
  }

  void _cizUzayYildizlari(Canvas canvas, Size size) {
    final rnd = math.Random(42);
    final paint = Paint()..style = PaintingStyle.fill;
    for (int i = 0; i < 85; i++) {
      final x = rnd.nextDouble() * size.width;
      final y = rnd.nextDouble() * size.height;
      final r = 0.6 + rnd.nextDouble() * 1.4;
      final parilti = 0.5 + 0.5 * math.sin((animasyonDegeri * 2 * math.pi) + i);
      final alpha = (0.15 + rnd.nextDouble() * 0.45) * parilti;
      paint.color = (i % 5 == 0 ? vurguRengi : yildizRengi).withValues(alpha: alpha.clamp(0.05, 0.85));
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  void _cizElektronikDevre(Canvas canvas, Size size) {
    final hatPaint = Paint()
      ..color = vurguRengi.withValues(alpha: 0.16)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    final ledGlowPaint = Paint()..style = PaintingStyle.fill;

    const int sutunSayisi = 7;
    final double adimX = size.width / sutunSayisi;

    for (int i = 0; i <= sutunSayisi; i++) {
      final double x = i * adimX;
      final double kirilimY1 = size.height * (0.22 + (i % 3) * 0.14);
      final double kirilimY2 = size.height * (0.58 + (i % 2) * 0.15);
      final double kayma = (i % 2 == 0 ? 18.0 : -18.0);

      final path = Path()
        ..moveTo(x, 0)
        ..lineTo(x, kirilimY1)
        ..lineTo(x + kayma, kirilimY1 + 24)
        ..lineTo(x + kayma, kirilimY2)
        ..lineTo(x, kirilimY2 + 24)
        ..lineTo(x, size.height);

      canvas.drawPath(path, hatPaint);

      // Devre dugum noktalari (Pad)
      canvas.drawCircle(Offset(x, kirilimY1), 3.0, hatPaint);
      canvas.drawCircle(Offset(x + kayma, kirilimY2), 3.0, hatPaint);

      // Hat uzerinde akan ve yanip sonen LED sinyali
      final double faz = (animasyonDegeri + (i * 0.17)) % 1.0;
      final double ledY = faz * size.height;
      final double ledX = (ledY > kirilimY1 + 24 && ledY < kirilimY2) ? (x + kayma) : x;
      final double nabiz = 0.5 + 0.5 * math.sin((animasyonDegeri * 4 * math.pi) + i);

      ledGlowPaint.color = vurguRengi.withValues(alpha: 0.25 * nabiz);
      canvas.drawCircle(Offset(ledX, ledY), 8.0, ledGlowPaint);

      ledGlowPaint.color = vurguRengi.withValues(alpha: 0.85 * nabiz);
      canvas.drawCircle(Offset(ledX, ledY), 2.8, ledGlowPaint);
    }

    // Yatay veri yollari
    for (int j = 1; j <= 4; j++) {
      final double y = size.height * (j * 0.2);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), hatPaint);
      final double sinyalX = ((animasyonDegeri * 1.3 + j * 0.25) % 1.0) * size.width;
      ledGlowPaint.color = vurguRengi.withValues(alpha: 0.75);
      canvas.drawCircle(Offset(sinyalX, y), 2.5, ledGlowPaint);
    }
  }

  void _cizMekanikSaatMekanizmasi(Canvas canvas, Size size) {
    final carkPaint = Paint()
      ..color = vurguRengi.withValues(alpha: 0.18)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final inceHalkaPaint = Paint()
      ..color = yildizRengi.withValues(alpha: 0.12)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    void disliCiz(Offset merkez, double yaricap, int disSayisi, double aci) {
      canvas.save();
      canvas.translate(merkez.dx, merkez.dy);
      canvas.rotate(aci);

      canvas.drawCircle(Offset.zero, yaricap * 0.82, carkPaint);
      canvas.drawCircle(Offset.zero, yaricap * 0.35, inceHalkaPaint);

      for (int k = 0; k < 4; k++) {
        final kolAci = k * (math.pi / 2);
        canvas.drawLine(
          Offset(math.cos(kolAci) * yaricap * 0.35, math.sin(kolAci) * yaricap * 0.35),
          Offset(math.cos(kolAci) * yaricap * 0.82, math.sin(kolAci) * yaricap * 0.82),
          inceHalkaPaint,
        );
      }

      final double disAciAdimi = (2 * math.pi) / disSayisi;
      for (int i = 0; i < disSayisi; i++) {
        final a = i * disAciAdimi;
        final p1 = Offset(math.cos(a) * yaricap * 0.82, math.sin(a) * yaricap * 0.82);
        final p2 = Offset(math.cos(a) * yaricap, math.sin(a) * yaricap);
        canvas.drawLine(p1, p2, carkPaint);
      }
      canvas.restore();
    }

    final double tamTur = animasyonDegeri * 2 * math.pi;
    disliCiz(Offset(size.width * 0.18, size.height * 0.22), 68, 18, tamTur);
    disliCiz(Offset(size.width * 0.82, size.height * 0.28), 54, 14, -tamTur * 1.2);
    disliCiz(Offset(size.width * 0.50, size.height * 0.42), 115, 28, tamTur * 0.5);
    disliCiz(Offset(size.width * 0.20, size.height * 0.78), 75, 20, -tamTur * 0.8);
    disliCiz(Offset(size.width * 0.84, size.height * 0.82), 62, 16, tamTur * 1.1);
  }

  @override
  bool shouldRepaint(covariant HareketliArkaPlanPainter oldDelegate) => true;
}