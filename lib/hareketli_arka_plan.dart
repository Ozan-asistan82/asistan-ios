import 'dart:math' as math;
import 'package:flutter/material.dart';

class HareketliArkaPlanPainter extends CustomPainter {
  final int temaTipi;
  final double animasyonDegeri;
  final Color vurguRengi;
  final Color yaziRengi;

  HareketliArkaPlanPainter({
    required this.temaTipi,
    required this.animasyonDegeri,
    required this.vurguRengi,
    required this.yaziRengi,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (temaTipi == 1) {
      _elektronikDevreCiz(canvas, size);
    } else if (temaTipi == 2) {
      _mekanikSaatCiz(canvas, size);
    } else {
      _uzayYildizlariCiz(canvas, size);
    }
  }

  void _uzayYildizlariCiz(Canvas canvas, Size size) {
    final rnd = math.Random(42);
    final paint = Paint()..style = PaintingStyle.fill;
    for (int i = 0; i < 85; i++) {
      final x = rnd.nextDouble() * size.width;
      final y = rnd.nextDouble() * size.height;
      final r = 0.6 + rnd.nextDouble() * 1.4;
      final parilti = 0.25 + 0.55 * math.sin((animasyonDegeri * math.pi * 2) + i).abs();
      paint.color = (i % 5 == 0 ? vurguRengi : yaziRengi).withValues(alpha: parilti.clamp(0.15, 0.85));
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  void _elektronikDevreCiz(Canvas canvas, Size size) {
    final hatPaint = Paint()
      ..color = vurguRengi.withValues(alpha: 0.16)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    final ledPaint = Paint()..style = PaintingStyle.fill;
    final rnd = math.Random(108);

    for (int i = 0; i < 16; i++) {
      final startX = rnd.nextDouble() * size.width;
      final startY = rnd.nextDouble() * size.height;
      final midX = startX + (rnd.nextBool() ? 65 : -65);
      final midY = startY + (rnd.nextBool() ? 80 : -80);
      final endX = midX + (rnd.nextBool() ? 70 : -70);

      final path = Path()
        ..moveTo(startX, startY)
        ..lineTo(midX, midY)
        ..lineTo(endX, midY);
      canvas.drawPath(path, hatPaint);

      final nabiz = math.sin((animasyonDegeri * math.pi * 2) + (i * 0.7)).abs();
      ledPaint.color = vurguRengi.withValues(alpha: 0.15 + (nabiz * 0.75));
      canvas.drawCircle(Offset(startX, startY), 2.5 + (nabiz * 1.8), ledPaint);
      canvas.drawCircle(Offset(endX, midY), 2.2, ledPaint);

      final akimOrani = (animasyonDegeri + (i * 0.13)) % 1.0;
      final akimX = startX + (midX - startX) * akimOrani;
      final akimY = startY + (midY - startY) * akimOrani;
      ledPaint.color = yaziRengi.withValues(alpha: 0.65);
      canvas.drawCircle(Offset(akimX, akimY), 2.0, ledPaint);
    }
  }

  void _disliCiz(Canvas canvas, Offset merkez, double yaricap, int disSayisi, double aci, Paint paint) {
    canvas.save();
    canvas.translate(merkez.dx, merkez.dy);
    canvas.rotate(aci);

    canvas.drawCircle(Offset.zero, yaricap * 0.78, paint);
    canvas.drawCircle(Offset.zero, yaricap * 0.35, paint);

    for (int i = 0; i < disSayisi; i++) {
      final theta = (2 * math.pi / disSayisi) * i;
      final p1 = Offset(math.cos(theta) * yaricap * 0.78, math.sin(theta) * yaricap * 0.78);
      final p2 = Offset(math.cos(theta) * yaricap, math.sin(theta) * yaricap);
      canvas.drawLine(p1, p2, paint);
    }

    for (int j = 0; j < 4; j++) {
      final kAci = (math.pi / 2) * j;
      canvas.drawLine(
        Offset(math.cos(kAci) * yaricap * 0.35, math.sin(kAci) * yaricap * 0.35),
        Offset(math.cos(kAci) * yaricap * 0.78, math.sin(kAci) * yaricap * 0.78),
        paint,
      );
    }
    canvas.restore();
  }

  void _mekanikSaatCiz(Canvas canvas, Size size) {
    final cizgiPaint = Paint()
      ..color = vurguRengi.withValues(alpha: 0.18)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;

    final aci = animasyonDegeri * 2 * math.pi;
    _disliCiz(canvas, Offset(size.width * 0.22, size.height * 0.22), 54, 14, aci, cizgiPaint);
    _disliCiz(canvas, Offset(size.width * 0.78, size.height * 0.30), 68, 18, -aci * 0.8, cizgiPaint);
    _disliCiz(canvas, Offset(size.width * 0.50, size.height * 0.42), 95, 24, aci * 0.5, cizgiPaint);
    _disliCiz(canvas, Offset(size.width * 0.25, size.height * 0.72), 60, 16, -aci, cizgiPaint);
    _disliCiz(canvas, Offset(size.width * 0.80, size.height * 0.76), 48, 12, aci * 1.2, cizgiPaint);

    final ledPaint = Paint()
      ..color = vurguRengi.withValues(alpha: 0.25 + 0.45 * math.sin(aci).abs())
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(size.width * 0.50, size.height * 0.42), 4.5, ledPaint);
  }

  @override
  bool shouldRepaint(covariant HareketliArkaPlanPainter oldDelegate) => true;
}