# Leitor de Códigos (Android)

App Flutter que usa a câmera para **ler e mostrar** códigos de barras e QR Codes,
sem enviar para o PC. Baseado no antigo *ColetorCelular* (mesmo `mobile_scanner` / ML Kit).

## O que faz

- **Marcador na câmera**: cada código visível ganha um contorno desenhado em cima dele.
  - **Verde** (preenchido, com o valor escrito): o código em foco, que está sendo lido.
  - **Amarelo**: outros códigos visíveis que passam no filtro.
  - **Cinza**: códigos ignorados pelo filtro.
- **Mira** ("Só na mira"): só lê o código que está dentro do retângulo central,
  o que ajuda quando há vários códigos juntos (ex.: etiqueta com EAN + QR).
  Desligue para ler em qualquer lugar da tela ("Tela toda").
- **Filtros**: Todos · Barras (1D) · QR / 2D · Chave NF-e.
- **Tocar no contorno** escolhe aquele código quando há mais de um na tela.
- **Chave de acesso**: se o código for (ou contiver) uma chave de 44 dígitos (DANFE,
  QR da NFC-e, CT-e...), mostra a chave em blocos de 4, modelo, UF, mês/ano, série,
  número e CNPJ do emitente, e confere o dígito verificador.
- **Histórico** da sessão com contagem de leituras, copiar um ou todos, limpar.
- Vibração e clique ao ler; lanterna; botão para pausar a câmera.

Um código parado na frente da câmera é contado **uma vez**; ele só conta de novo
depois de sair de foco por 1,5 s (ajuste em `_intervaloReleitura`).

## Como montar o projeto

O `.rar` original só tinha a pasta `lib/`, então crie o projeto Android e copie os arquivos:

```bash
flutter create --platforms=android --org br.com.suaempresa leitor_codigos
# copie por cima: pubspec.yaml, analysis_options.yaml e a pasta lib/ deste pacote
cd leitor_codigos
flutter pub get
flutter run            # com o celular conectado em modo depuração
flutter build apk --release   # APK em build/app/outputs/flutter-apk/
```

Requisitos: Flutter 3.29+ e Android 6.0 (API 23) ou mais novo.

- A permissão de câmera já vem do `mobile_scanner` (é mesclada no AndroidManifest automaticamente).
- Se o build reclamar de `minSdk`, em `android/app/build.gradle.kts` coloque `minSdk = 23`
  (ou maior) no bloco `defaultConfig`.
- Opcional: para um APK ~3–10 MB menor, use o ML Kit que é baixado pelo Google Play Services.
  Em `android/gradle.properties` adicione:
  `dev.steenbakker.mobile_scanner.useUnbundled=true`
  (o leitor só funciona depois que o Play Services baixar o modelo, na primeira abertura com internet).

## Arquivos

```
lib/
  main.dart                     app + trava em retrato
  screens/scanner_screen.dart   tela da câmera, filtros, histórico
  widgets/marcador_painter.dart desenho da mira e dos contornos
  utils/codigo_utils.dart       filtros, nomes de formato, chave NF-e, geometria
```
