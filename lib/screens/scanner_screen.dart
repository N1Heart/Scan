import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../utils/codigo_utils.dart';
import '../widgets/marcador_painter.dart';

/// Um código lido e guardado no histórico.
class Leitura {
  Leitura({required this.valor, required this.formato, required this.hora});

  final String valor;
  final String formato;
  DateTime hora;
  int vezes = 1;

  late final ChaveAcesso? chave = extrairChave(valor);
}

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: 120, // atualiza o marcador ~8x por segundo
  );

  /// Tempo que o código precisa ficar fora de foco para ser contado de novo.
  static const _intervaloReleitura = Duration(milliseconds: 1500);

  /// Sem detecção por esse tempo, o marcador some da tela.
  static const _tempoParaLimpar = Duration(milliseconds: 450);

  // Estado da câmera / marcadores
  Size _areaCamera = Size.zero;
  Rect _mira = Rect.zero;
  List<CodigoNaTela> _codigos = const [];
  CodigoNaTela? _focado;
  Timer? _timerLimpar;

  // Opções
  FiltroCodigo _filtro = FiltroCodigo.todos;
  bool _usarMira = true;
  bool _pausado = false;

  // Leituras
  final List<Leitura> _historico = [];
  final Map<String, DateTime> _vistoEm = {};
  Leitura? _atual;

  @override
  void dispose() {
    _timerLimpar?.cancel();
    unawaited(_controller.dispose());
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Detecção
  // ---------------------------------------------------------------------------

  void _aoDetectar(BarcodeCapture captura) {
    if (_pausado || _areaCamera.isEmpty || !mounted) return;

    final codigos = <CodigoNaTela>[];

    for (final b in captura.barcodes) {
      final valor = b.rawValue ?? b.displayValue;
      if (valor == null || valor.isEmpty || b.corners.length < 3) continue;

      final poligono = cantosNaTela(
        cantos: b.corners,
        tamanhoImagem: captura.size,
        tamanhoTela: _areaCamera,
      );
      if (poligono.length < 3) continue;

      final c = CodigoNaTela(
        valor: valor,
        formato: nomeFormato(b.format),
        poligono: poligono,
        passaFiltro: passaNoFiltro(_filtro, b.format, valor),
        naMira: pontoNoPoligono(_mira.center, poligono) ||
            _mira.contains(centroDe(poligono)),
      );
      codigos.add(c);
    }

    // Escolhe o código em foco: passa no filtro, (está na mira) e é o mais
    // próximo do centro.
    CodigoNaTela? focado;
    var melhor = double.infinity;
    for (final c in codigos) {
      if (!c.passaFiltro || (_usarMira && !c.naMira)) continue;
      final d = (centroDe(c.poligono) - _mira.center).distanceSquared;
      if (d < melhor) {
        melhor = d;
        focado = c;
      }
    }

    setState(() {
      _codigos = codigos;
      _focado = focado;
    });

    if (focado != null) {
      _registrar(focado.valor, focado.formato);
    }

    _timerLimpar?.cancel();
    _timerLimpar = Timer(_tempoParaLimpar, () {
      if (!mounted || _pausado) return;
      setState(() {
        _codigos = const [];
        _focado = null;
      });
    });
  }

  /// Adiciona ao histórico. Um código que continua parado em foco não é
  /// contado de novo; só conta outra vez depois de sair de foco.
  void _registrar(String valor, String formato, {bool forcar = false}) {
    final agora = DateTime.now();
    final visto = _vistoEm[valor];
    _vistoEm[valor] = agora;
    if (!forcar &&
        visto != null &&
        agora.difference(visto) < _intervaloReleitura) {
      return;
    }

    final existente = _historico.where((l) => l.valor == valor).firstOrNull;
    setState(() {
      if (existente != null) {
        existente
          ..vezes += 1
          ..hora = agora;
        _historico
          ..remove(existente)
          ..insert(0, existente);
        _atual = existente;
      } else {
        final nova = Leitura(valor: valor, formato: formato, hora: agora);
        _historico.insert(0, nova);
        _atual = nova;
      }
    });

    HapticFeedback.mediumImpact();
    SystemSound.play(SystemSoundType.click);
  }

  /// Tocar num contorno na tela escolhe aquele código.
  void _aoTocarCamera(TapUpDetails d) {
    for (final c in _codigos.reversed) {
      if (pontoNoPoligono(d.localPosition, c.poligono)) {
        setState(() => _focado = c);
        _registrar(c.valor, c.formato, forcar: true);
        return;
      }
    }
  }

  Future<void> _alternarPausa() async {
    setState(() => _pausado = !_pausado);
    if (_pausado) {
      _timerLimpar?.cancel();
      await _controller.pause();
    } else {
      setState(() {
        _codigos = const [];
        _focado = null;
      });
      await _controller.start();
    }
  }

  // ---------------------------------------------------------------------------
  // Ações
  // ---------------------------------------------------------------------------

  void _copiar(String texto, {String msg = 'Copiado'}) {
    Clipboard.setData(ClipboardData(text: texto));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 1),
      ));
  }

  void _limparHistorico() {
    setState(() {
      _historico.clear();
      _vistoEm.clear();
      _atual = null;
    });
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Leitor de Códigos'),
        actions: [
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _controller,
            builder: (context, estado, _) {
              final t = estado.torchState;
              if (t == TorchState.unavailable) return const SizedBox.shrink();
              return IconButton(
                tooltip: 'Lanterna',
                icon: Icon(t == TorchState.on
                    ? Icons.flashlight_on
                    : Icons.flashlight_off),
                onPressed: _controller.toggleTorch,
              );
            },
          ),
          IconButton(
            tooltip: 'Copiar todos',
            icon: const Icon(Icons.copy_all),
            onPressed: _historico.isEmpty
                ? null
                : () => _copiar(
                      _historico.reversed.map((l) => l.valor).join('\n'),
                      msg: '${_historico.length} código(s) copiados',
                    ),
          ),
          IconButton(
            tooltip: 'Limpar histórico',
            icon: const Icon(Icons.delete_sweep),
            onPressed: _historico.isEmpty ? null : _limparHistorico,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(flex: 6, child: _camera()),
          Expanded(flex: 5, child: _painel()),
        ],
      ),
    );
  }

  Widget _camera() {
    return LayoutBuilder(builder: (context, box) {
      final tamanho = box.biggest;
      if (tamanho != _areaCamera) {
        _areaCamera = tamanho;
        final w = tamanho.width * 0.84;
        final h = (tamanho.height * 0.40).clamp(80.0, w * 0.62);
        _mira = Rect.fromCenter(
          center: tamanho.center(Offset.zero),
          width: w,
          height: h,
        );
      }

      return GestureDetector(
        onTapUp: _aoTocarCamera,
        child: Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(
              controller: _controller,
              fit: BoxFit.cover,
              onDetect: _aoDetectar,
              errorBuilder: (context, erro) => _erroCamera(erro),
            ),
            IgnorePointer(
              child: CustomPaint(
                painter: MarcadorPainter(
                  codigos: _codigos,
                  focado: _focado,
                  mira: _mira,
                  usarMira: _usarMira,
                  pausado: _pausado,
                ),
              ),
            ),
            // Filtros no topo
            Positioned(
              top: 8,
              left: 0,
              right: 0,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    for (final f in FiltroCodigo.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(f.rotulo),
                          selected: _filtro == f,
                          onSelected: (_) => setState(() => _filtro = f),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // Controles embaixo
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Row(
                children: [
                  FilterChip(
                    avatar: const Icon(Icons.center_focus_strong, size: 18),
                    label: Text(_usarMira ? 'Só na mira' : 'Tela toda'),
                    selected: _usarMira,
                    onSelected: (v) => setState(() => _usarMira = v),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _codigos.length > 1
                        ? Align(
                            alignment: Alignment.centerLeft,
                            child: Chip(
                              label: Text(
                                '${_codigos.length} códigos · toque para escolher',
                                overflow: TextOverflow.ellipsis,
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  IconButton.filled(
                    tooltip: _pausado ? 'Continuar' : 'Pausar',
                    icon: Icon(_pausado ? Icons.play_arrow : Icons.pause),
                    onPressed: _alternarPausa,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _erroCamera(MobileScannerException erro) {
    final msg = erro.errorCode == MobileScannerErrorCode.permissionDenied
        ? 'Sem permissão para usar a câmera.\n'
            'Libere em Configurações > Apps > Leitor de Códigos > Permissões.'
        : 'Não foi possível abrir a câmera.\n${erro.errorDetails?.message ?? ''}';
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(msg,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70)),
        ),
      ),
    );
  }

  Widget _painel() {
    final tema = Theme.of(context);
    return Container(
      color: tema.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cartaoAtual(tema),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text('Histórico (${_historico.length})',
                style: tema.textTheme.titleSmall),
          ),
          Expanded(
            child: _historico.isEmpty
                ? Center(
                    child: Text('Nenhum código lido ainda',
                        style: tema.textTheme.bodySmall),
                  )
                : ListView.separated(
                    itemCount: _historico.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final l = _historico[i];
                      return ListTile(
                        dense: true,
                        selected: identical(l, _atual),
                        title: Text(l.chave?.formatada ?? l.valor,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontFamily: 'monospace')),
                        subtitle: Text(
                            '${l.chave?.modelo ?? l.formato} · ${_hora(l.hora)}'
                            '${l.vezes > 1 ? ' · ${l.vezes}x' : ''}'),
                        onTap: () => setState(() => _atual = l),
                        trailing: IconButton(
                          icon: const Icon(Icons.copy, size: 20),
                          onPressed: () => _copiar(l.valor),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _cartaoAtual(ThemeData tema) {
    final l = _atual;
    if (l == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.qr_code_scanner),
            SizedBox(width: 12),
            Expanded(child: Text('Aponte a câmera para um código')),
          ],
        ),
      );
    }

    final chave = l.chave;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Chip(
                  label: Text(chave?.modelo ?? l.formato),
                  visualDensity: VisualDensity.compact,
                ),
                if (chave != null) ...[
                  const SizedBox(width: 6),
                  Icon(
                    chave.dvValido ? Icons.verified : Icons.error_outline,
                    size: 18,
                    color: chave.dvValido ? Colors.greenAccent : Colors.orange,
                  ),
                  const SizedBox(width: 4),
                  Text(chave.dvValido ? 'DV ok' : 'DV não confere',
                      style: tema.textTheme.bodySmall),
                ],
                const Spacer(),
                Text(_hora(l.hora), style: tema.textTheme.bodySmall),
                IconButton(
                  tooltip: 'Copiar',
                  icon: const Icon(Icons.copy),
                  onPressed: () => _copiar(chave?.chave ?? l.valor),
                ),
              ],
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 72),
              child: SingleChildScrollView(
                child: SelectableText(
                  chave?.formatada ?? l.valor,
                  style: tema.textTheme.titleMedium
                      ?.copyWith(fontFamily: 'monospace'),
                ),
              ),
            ),
            if (chave != null)
              Padding(
                padding: const EdgeInsets.only(top: 6, right: 8),
                child: Text(
                  'UF ${chave.uf} · ${chave.mesAno} · Série ${chave.serie} · '
                  'Nº ${chave.numero}\nCNPJ ${chave.cnpj}',
                  style: tema.textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _hora(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';
}
