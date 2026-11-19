import 'dart:ui';

import 'package:mobile_scanner/mobile_scanner.dart';

/// Filtro de tipo de código escolhido na tela.
enum FiltroCodigo {
  todos('Todos'),
  barras('Barras'),
  qr2d('QR / 2D'),
  chaveNfe('Chave NF-e');

  const FiltroCodigo(this.rotulo);
  final String rotulo;
}

const _formatos2D = {
  BarcodeFormat.qrCode,
  BarcodeFormat.microQrCode,
  BarcodeFormat.dataMatrix,
  BarcodeFormat.aztec,
  BarcodeFormat.pdf417,
  BarcodeFormat.maxiCode,
};

bool ehCodigo2D(BarcodeFormat f) => _formatos2D.contains(f);

bool passaNoFiltro(FiltroCodigo filtro, BarcodeFormat formato, String valor) {
  switch (filtro) {
    case FiltroCodigo.todos:
      return true;
    case FiltroCodigo.barras:
      return !ehCodigo2D(formato);
    case FiltroCodigo.qr2d:
      return ehCodigo2D(formato);
    case FiltroCodigo.chaveNfe:
      return extrairChave(valor) != null;
  }
}

String nomeFormato(BarcodeFormat f) {
  switch (f) {
    case BarcodeFormat.qrCode:
      return 'QR Code';
    case BarcodeFormat.microQrCode:
      return 'Micro QR';
    case BarcodeFormat.dataMatrix:
      return 'Data Matrix';
    case BarcodeFormat.aztec:
      return 'Aztec';
    case BarcodeFormat.pdf417:
      return 'PDF417';
    case BarcodeFormat.maxiCode:
      return 'MaxiCode';
    case BarcodeFormat.code128:
      return 'Code 128';
    case BarcodeFormat.code39:
      return 'Code 39';
    case BarcodeFormat.code93:
      return 'Code 93';
    case BarcodeFormat.codabar:
      return 'Codabar';
    case BarcodeFormat.ean13:
      return 'EAN-13';
    case BarcodeFormat.ean8:
      return 'EAN-8';
    case BarcodeFormat.upcA:
      return 'UPC-A';
    case BarcodeFormat.upcE:
      return 'UPC-E';
    case BarcodeFormat.itf:
    case BarcodeFormat.itf14:
    case BarcodeFormat.itf2of5:
    case BarcodeFormat.itf2of5WithChecksum:
      return 'ITF';
    default:
      return 'Código';
  }
}

// ---------------------------------------------------------------------------
// Chave de acesso (NF-e, NFC-e, CT-e, MDF-e...)
// ---------------------------------------------------------------------------

class ChaveAcesso {
  ChaveAcesso(this.chave);

  final String chave;

  String get uf => _ufs[chave.substring(0, 2)] ?? chave.substring(0, 2);
  String get mesAno => '${chave.substring(4, 6)}/20${chave.substring(2, 4)}';
  String get cnpj {
    final c = chave.substring(6, 20);
    return '${c.substring(0, 2)}.${c.substring(2, 5)}.${c.substring(5, 8)}/'
        '${c.substring(8, 12)}-${c.substring(12)}';
  }

  String get modelo {
    final m = chave.substring(20, 22);
    return switch (m) {
      '55' => 'NF-e',
      '65' => 'NFC-e',
      '57' => 'CT-e',
      '67' => 'CT-e OS',
      '58' => 'MDF-e',
      '59' => 'CF-e SAT',
      _ => 'Modelo $m',
    };
  }

  String get serie => int.parse(chave.substring(22, 25)).toString();
  String get numero => int.parse(chave.substring(25, 34)).toString();

  /// Confere o dígito verificador (módulo 11, pesos 2..9 da direita p/ esquerda).
  bool get dvValido {
    var soma = 0;
    var peso = 2;
    for (var i = 42; i >= 0; i--) {
      soma += int.parse(chave[i]) * peso;
      peso = peso == 9 ? 2 : peso + 1;
    }
    final resto = soma % 11;
    final dv = resto < 2 ? 0 : 11 - resto;
    return dv == int.parse(chave[43]);
  }

  /// Chave em blocos de 4 dígitos, como aparece no DANFE.
  String get formatada {
    final b = StringBuffer();
    for (var i = 0; i < chave.length; i += 4) {
      if (i > 0) b.write(' ');
      b.write(chave.substring(i, i + 4));
    }
    return b.toString();
  }

  static const _ufs = {
    '11': 'RO', '12': 'AC', '13': 'AM', '14': 'RR', '15': 'PA', '16': 'AP',
    '17': 'TO', '21': 'MA', '22': 'PI', '23': 'CE', '24': 'RN', '25': 'PB',
    '26': 'PE', '27': 'AL', '28': 'SE', '29': 'BA', '31': 'MG', '32': 'ES',
    '33': 'RJ', '35': 'SP', '41': 'PR', '42': 'SC', '43': 'RS', '50': 'MS',
    '51': 'MT', '52': 'GO', '53': 'DF',
  };
}

final _soDigitos44 = RegExp(r'^\d{44}$');
final _chaveNoTexto = RegExp(r'(?<!\d)(\d{44})(?!\d)');

/// Retorna a chave se o código for uma chave de 44 dígitos (código de barras
/// do DANFE) ou contiver uma (ex.: QR Code da NFC-e, que traz a chave na URL).
ChaveAcesso? extrairChave(String valor) {
  final v = valor.trim();
  if (_soDigitos44.hasMatch(v)) return ChaveAcesso(v);
  final m = _chaveNoTexto.firstMatch(v);
  if (m != null) return ChaveAcesso(m.group(1)!);
  return null;
}

// ---------------------------------------------------------------------------
// Geometria
// ---------------------------------------------------------------------------

/// Ray casting: o ponto está dentro do polígono?
bool pontoNoPoligono(Offset p, List<Offset> poligono) {
  var dentro = false;
  for (var i = 0, j = poligono.length - 1; i < poligono.length; j = i++) {
    final a = poligono[i];
    final b = poligono[j];
    if ((a.dy > p.dy) != (b.dy > p.dy) &&
        p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
      dentro = !dentro;
    }
  }
  return dentro;
}

Offset centroDe(List<Offset> pts) {
  var x = 0.0, y = 0.0;
  for (final p in pts) {
    x += p.dx;
    y += p.dy;
  }
  return Offset(x / pts.length, y / pts.length);
}

/// Converte os cantos do código (coordenadas da imagem da câmera) para
/// coordenadas da tela, considerando a prévia em BoxFit.cover e o app em
/// retrato. Mesma conta usada pelo BarcodePainter do mobile_scanner.
List<Offset> cantosNaTela({
  required List<Offset> cantos,
  required Size tamanhoImagem,
  required Size tamanhoTela,
}) {
  // Em retrato a imagem é "em pé": lado menor = largura.
  final img = Size(tamanhoImagem.shortestSide, tamanhoImagem.longestSide);
  if (img.isEmpty || tamanhoTela.isEmpty) return const [];

  final escala = (tamanhoTela.width / img.width) > (tamanhoTela.height / img.height)
      ? tamanhoTela.width / img.width
      : tamanhoTela.height / img.height;
  final padH = (img.width * escala - tamanhoTela.width) / 2;
  final padV = (img.height * escala - tamanhoTela.height) / 2;

  return [
    for (final c in cantos) Offset(c.dx * escala - padH, c.dy * escala - padV),
  ];
}
