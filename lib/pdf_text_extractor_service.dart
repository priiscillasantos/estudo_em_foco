// Extração de texto real de um PDF já carregado em memória (bytes) — etapa
// 1 da "inteligência" do app: confirmar que dá para ler o conteúdo de
// verdade do arquivo antes de gerar resumo ou quiz a partir dele. Não gera
// resumo nem quiz — só entrega texto limpo (ou uma falha controlada) para
// quem chamar decidir o que fazer com ele.

import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';

import 'local_store.dart' show PdfExtractionStatus;

/// Devolvido por [PdfTextExtractorService.extract]: nunca lança — qualquer
/// falha (bytes vazios, PDF protegido/corrompido, zero páginas com texto,
/// texto insuficiente, falha da biblioteca ao processar página) vira
/// [status] `failed` com [message] explicando o motivo ESPECÍFICO — nunca
/// uma frase genérica igual para qualquer causa — e os campos de
/// diagnóstico ([totalPages]/[pagesProcessed]/[pagesWithText]/
/// [pagesFailed]) preenchidos com o que de fato aconteceu, para a tela de
/// Material de estudo poder mostrar um diagnóstico real (ver
/// `_ExtractionDiagnostics` em main.dart).
class PdfTextExtractionResult {
  final PdfExtractionStatus status;
  final String text;
  final String? message;
  final int totalPages;
  final int pagesProcessed;
  final int pagesWithText;
  final int pagesFailed;

  const PdfTextExtractionResult({
    required this.status,
    required this.text,
    this.message,
    this.totalPages = 0,
    this.pagesProcessed = 0,
    this.pagesWithText = 0,
    this.pagesFailed = 0,
  });

  bool get isSuccess => status == PdfExtractionStatus.success;
}

/// Remove ruído comum de texto extraído de PDF: espaços/quebras de linha
/// repetidos e linhas isoladas de 1-2 caracteres (comuns quando o PDF tem
/// layout quebrado ou é parcialmente escaneado) — sem essa limpeza, esse
/// ruído poderia inflar a contagem de caracteres e mascarar uma extração
/// ruim quando comparada a [PdfTextExtractorService.minUsefulChars].
String cleanExtractedText(String raw) {
  final usefulLines = raw
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.length > 2);
  return usefulLines.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Extrai o texto real (selecionável) de um PDF a partir dos bytes já
/// carregados em memória — usa o `pdfrx` (`PdfDocument.openData` +
/// `PdfPage.loadText`), a mesma biblioteca já usada para renderizar o PDF na
/// tela de Leitura do material. O `pdfrx` embute o `pdfium` (via wasm no
/// Flutter Web), então a extração funciona na mesma plataforma sem
/// depender de nenhum pacote adicional.
class PdfTextExtractorService {
  PdfTextExtractorService._();

  /// Só as primeiras [maxPages] páginas são lidas e o texto é cortado em
  /// [maxChars] — o objetivo é uma amostra do conteúdo, não o PDF inteiro,
  /// então não vale a pena gastar tempo/memória num arquivo grande.
  static const int maxPages = 8;
  static const int maxChars = 6000;

  /// Abaixo deste tamanho (depois de limpo por [cleanExtractedText]), o
  /// texto é considerado insuficiente e a extração falha — evita tratar
  /// "algumas palavras soltas de ruído" como um texto extraído de verdade.
  static const int minUsefulChars = 300;

  /// Nunca lança: qualquer exceção durante a abertura/leitura do PDF vira
  /// um [PdfTextExtractionResult] com `status: failed` e uma [message]
  /// específica sobre QUAL etapa falhou.
  static Future<PdfTextExtractionResult> extract(
    Uint8List bytes, {
    String? sourceName,
  }) async {
    if (bytes.isEmpty) {
      return const PdfTextExtractionResult(
        status: PdfExtractionStatus.failed,
        text: '',
        message:
            'Bytes vazios recebidos no upload — o arquivo não chegou a ser '
            'lido corretamente pelo seletor de arquivo.',
      );
    }

    PdfDocument? document;
    try {
      try {
        // No Flutter Web, `PdfDocument.openData` exige que o `pdfrx` já
        // tenha sido inicializado (`PdfrxEntryFunctions.instance` setado
        // com a implementação WASM) — normalmente isso acontece sozinho
        // quando um `PdfViewer`/`PdfDocumentRef` é montado (ver
        // pdf_viewer.dart/pdf_document_ref.dart no próprio pdfrx), mas
        // aqui chamamos `PdfDocument.openData` direto, sem nenhum
        // `PdfViewer` na árvore ainda (o upload acontece antes do usuário
        // abrir a Leitura do material) — sem esta chamada explícita, isso
        // lançava "PdfrxEntryFunctions.instance is not initialized" só no
        // navegador (nunca em `flutter test`, que roda nativo e já tem uma
        // instância padrão disponível sem precisar inicializar nada). É
        // idempotente (`pdfrxFlutterInitialize` só faz algo na primeira
        // chamada), então é seguro chamar aqui toda vez. Em try/catch
        // próprio: em ambiente de teste nativo sem o plugin path_provider
        // registrado, essa chamada pode falhar tentando achar um diretório
        // de cache (usado só no lado nativo/desktop, irrelevante para a
        // extração em si) — se isso acontecer, seguimos tentando abrir o
        // PDF mesmo assim em vez de abortar por causa de uma etapa que não
        // é essencial para ler o texto.
        try {
          await pdfrxFlutterInitialize();
        } catch (e) {
          debugPrint(
            'PdfTextExtractorService.extract: pdfrxFlutterInitialize() '
            'falhou (seguindo mesmo assim): $e',
          );
        }
        document = await PdfDocument.openData(bytes, sourceName: sourceName);
      } catch (e, stack) {
        debugPrint('PdfTextExtractorService.extract: erro ao abrir o PDF: $e');
        debugPrint('PdfTextExtractorService.extract stack: $stack');
        return PdfTextExtractionResult(
          status: PdfExtractionStatus.failed,
          text: '',
          message: 'Erro ao abrir o PDF (${bytes.length} bytes recebidos): $e',
        );
      }

      final totalPages = document.pages.length;
      final buffer = StringBuffer();
      final pageLimit = totalPages < maxPages ? totalPages : maxPages;
      var pagesWithText = 0;
      var pagesFailed = 0;
      for (var i = 0; i < pageLimit; i++) {
        // `loadText()` de UMA página pode lançar mesmo quando as outras
        // funcionam — no backend WASM (Flutter Web) isso acontece quando
        // `FPDFText_LoadPage` falha para aquela página específica (fonte
        // incorporada problemática, conteúdo malformado etc.): o worker JS
        // devolve `{fullText: ''}` sem a chave `charRects`, e o lado Dart
        // lança um TypeError ao tentar ler essa chave ausente. Sem este
        // try/catch por página, uma exceção em QUALQUER página descartava
        // todo o texto já acumulado das páginas anteriores e derrubava a
        // extração inteira para "failed" — mesmo com páginas boas o
        // bastante para passar em [minUsefulChars].
        try {
          final pageText = await document.pages[i].loadText();
          final fullText = pageText?.fullText;
          if (fullText != null && fullText.trim().isNotEmpty) {
            buffer.writeln(fullText);
            pagesWithText++;
          }
          debugPrint(
            'PdfTextExtractorService.extract: página ${i + 1}/$pageLimit '
            'ok (${fullText?.length ?? 0} caracteres brutos desta página, '
            '${buffer.length} acumulados).',
          );
        } catch (e, stack) {
          pagesFailed++;
          debugPrint(
            'PdfTextExtractorService.extract: falha ao extrair texto da '
            'página ${i + 1}/$pageLimit (pulando esta página): $e',
          );
          debugPrint('PdfTextExtractorService.extract stack: $stack');
        }
        if (buffer.length > maxChars) break;
      }
      final cleaned = cleanExtractedText(buffer.toString());
      debugPrint(
        'PdfTextExtractorService.extract: resumo — $pagesWithText/'
        '$pageLimit páginas com texto, $pagesFailed/$pageLimit páginas '
        'falharam ao processar, ${cleaned.length} caracteres úteis após '
        'limpeza.',
      );
      if (cleaned.length < minUsefulChars) {
        // Mensagem específica por causa (ver item 3 da etapa de
        // diagnóstico): distingue "a biblioteca falhou ao processar TODAS
        // as páginas" (limitação/bug da extração em si, ex.: o bug de
        // WASM comentado acima) de "nenhuma página tinha texto" (zero
        // páginas com texto, sem nenhuma exceção — PDF genuinamente sem
        // texto selecionável) de "teve algum texto, mas pouco" (abaixo do
        // mínimo) — nunca a mesma frase genérica para as três.
        String message;
        if (pageLimit == 0) {
          message = 'O PDF não tem nenhuma página.';
        } else if (pagesFailed == pageLimit) {
          message =
              'Falha da biblioteca ao processar todas as $pageLimit '
              'página(s) deste PDF no Flutter Web (0 caracteres úteis).';
        } else if (pagesWithText == 0) {
          message =
              'Zero de $pageLimit página(s) retornaram texto (0 '
              'caracteres úteis) — PDF provavelmente sem texto '
              'selecionável (imagem/escaneado).';
        } else {
          message =
              'Texto extraído abaixo do mínimo útil (${cleaned.length} '
              'de $minUsefulChars caracteres; $pagesWithText de '
              '$pageLimit páginas com texto, $pagesFailed falharam ao '
              'processar).';
        }
        return PdfTextExtractionResult(
          status: PdfExtractionStatus.failed,
          text: '',
          message: message,
          totalPages: totalPages,
          pagesProcessed: pageLimit,
          pagesWithText: pagesWithText,
          pagesFailed: pagesFailed,
        );
      }
      return PdfTextExtractionResult(
        status: PdfExtractionStatus.success,
        text: cleaned,
        totalPages: totalPages,
        pagesProcessed: pageLimit,
        pagesWithText: pagesWithText,
        pagesFailed: pagesFailed,
      );
    } catch (e, stack) {
      debugPrint('PdfTextExtractorService.extract: erro inesperado: $e');
      debugPrint('PdfTextExtractorService.extract stack: $stack');
      return PdfTextExtractionResult(
        status: PdfExtractionStatus.failed,
        text: '',
        message: 'Erro inesperado ao processar o PDF: $e',
      );
    } finally {
      await document?.dispose();
    }
  }
}
