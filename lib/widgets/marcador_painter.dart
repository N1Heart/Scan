import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Um código detectado no quadro atual, já em coordenadas da tela.
class CodigoNaTela {
  CodigoNaTela({
    required this.valor,
    required this.formato,
    required this.poligono,
    required this.passaFiltro,
    required this.naMira,
  });

  final String valor;
  final String formato;
  final List<Offset> poligono;
  final bool passaFiltro;
  final bool naMira;
}

/// Desenha a mira e um contorno em cima de cada código visível:
///  - verde e preenchido: o código em foco (o que está sendo lido);
///  - amarelo: outros códigos que passam no filtro;
///  - cinza: códigos ignorados pelo filtro.
class MarcadorPainter extends CustomPainter {
  MarcadorPainter({
    required this.codigos,
    required this.focado,
    required this.mira,
    required this.usarMira,
    required this.pausado,
  });

  final List<CodigoNaTela> codigos;
  final CodigoNaTela? focado;
  final Rect mira;
  final bool usarMira;
  final bool pausado;

  static const _verde = Color(0xFF00E676);
  static const _amarelo = Color(0xFFFFC400);
  static const _cinza = Color(0xFF9E9E9E);

  @override
  void paint(Canvas canvas, Size size) {
    if (usarMira) _desenharMira(canvas, size);

    for (final c in codigos) {
      if (identical(c, focado) || c.poligono.length < 3) continue;
      final cor = c.passaFiltro ? _amarelo : _cinza;
      _contorno(canvas, c.poligono, cor, c.passaFiltro ? 2.5 : 1.5, preencher: false);
    }

    final f = focado;
    if (f != null && f.poligono.length >= 3) {
      _contorno(canvas, f.poligono, _verde, 3.5, preencher: true);
      _rotulo(canvas, size, f);
    }
  }

  void _desenharMira(Canvas canvas, Size size) {
    // Escurece o que está fora da mira.
    final fundo = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(mira, const Radius.circular(14)));
    canvas.drawPath(fundo, Paint()..color = Colors.black.withValues(alpha: 0.40));

    final cor = pausado
        ? Colors.white54
        : (focado != null ? _verde : Colors.white);
    final p = Paint()
      ..color = cor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    // Cantoneiras.
    const l = 28.0;
    final r = mira;
    canvas
      ..drawLine(r.topLeft, r.topLeft + const Offset(l, 0), p)
      ..drawLine(r.topLeft, r.topLeft + const Offset(0, l), p)
      ..drawLine(r.topRight, r.topRight + const Offset(-l, 0), p)
      ..drawLine(r.topRight, r.topRight + const Offset(0, l), p)
      ..drawLine(r.bottomLeft, r.bottomLeft + const Offset(l, 0), p)
      ..drawLine(r.bottomLeft, r.bottomLeft + const Offset(0, -l), p)
      ..drawLine(r.bottomRight, r.bottomRight + const Offset(-l, 0), p)
      ..drawLine(r.bottomRight, r.bottomRight + const Offset(0, -l), p);

    // Linha central de referência (ajuda a alinhar código de barras).
    canvas.drawLine(
      Offset(r.left + 16, r.center.dy),
      Offset(r.right - 16, r.center.dy),
      Paint()
        ..color = cor.withValues(alpha: 0.55)
        ..strokeWidth = 1.5,
    );
  }

  void _contorno(Canvas canvas, List<Offset> pts, Color cor, double largura,
      {required bool preencher}) {
    final path = Path()..addPolygon(pts, true);
    if (preencher) {
      canvas.drawPath(path, Paint()..color = cor.withValues(alpha: 0.22));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = cor
        ..style = PaintingStyle.stroke
        ..strokeWidth = largura
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _rotulo(Canvas canvas, Size size, CodigoNaTela c) {
    var texto = c.valor.replaceAll('\n', ' ');
    if (texto.length > 48) texto = '${texto.substring(0, 45)}...';

    final tp = TextPainter(
      text: TextSpan(
        text: texto,
        style: const TextStyle(
          color: Colors.black,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
    )..layout(maxWidth: size.width - 32);

    // Acima do contorno; se não couber, abaixo.
    var top = double.infinity, bottom = -double.infinity;
    var left = double.infinity, right = -double.infinity;
    for (final p in c.poligono) {
      if (p.dy < top) top = p.dy;
      if (p.dy > bottom) bottom = p.dy;
      if (p.dx < left) left = p.dx;
      if (p.dx > right) right = p.dx;
    }
    final w = tp.width + 16, h = tp.height + 8;
    var y = top - h - 8;
    if (y < 4) y = bottom + 8;
    var x = (left + right) / 2 - w / 2;
    x = x.clamp(8.0, math.max(8.0, size.width - w - 8));
    y = y.clamp(4.0, math.max(4.0, size.height - h - 4));

    final caixa = RRect.fromRectAndRadius(
      Rect.fromLTWH(x, y, w, h),
      const Radius.circular(8),
    );
    canvas.drawRRect(caixa, Paint()..color = _verde);
    tp.paint(canvas, Offset(x + 8, y + 4));
    tp.dispose();
  }

  @override
  bool shouldRepaint(MarcadorPainter old) =>
      old.codigos != codigos ||
      old.focado != focado ||
      old.mira != mira ||
      old.usarMira != usarMira ||
      old.pausado != pausado;
}
