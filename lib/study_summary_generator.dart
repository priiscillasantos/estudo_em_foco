// Etapa 2 da "inteligência" do app: gerar um resumo automático a partir do
// texto REAL já extraído do PDF (ver PdfTextExtractorService/Etapa 1) — sem
// IA externa, por extração/seleção de frases (heurística simples). Não gera
// quiz nenhum; é usado só para alimentar o card "Resumo gerado" na tela
// Material de estudo nesta etapa.

import 'local_store.dart' show SummaryStatus;

/// Devolvido por [StudySummaryGenerator.generate]: nunca lança — se não
/// houver texto de entrada suficiente, [status] vem `failed` com [message]
/// explicando o motivo, para a UI mostrar orientação em vez de travar.
class StudySummaryResult {
  final SummaryStatus status;
  final String summary;
  final String? message;

  const StudySummaryResult({
    required this.status,
    required this.summary,
    this.message,
  });

  bool get isSuccess => status == SummaryStatus.success;
}

/// Gera um resumo extrativo (seleciona frases reais do próprio texto, nunca
/// inventa conteúdo) a partir do texto extraído de um PDF.
///
/// Como funciona:
/// 1. Quebra o texto em frases e descarta as curtas/longas demais para
///    servir de resumo (cabeçalhos, rodapés, ruído de layout).
/// 2. Remove frases duplicadas (comum quando um cabeçalho/rodapé se repete
///    em toda página do PDF).
/// 3. Conta os termos (palavras de 4+ letras) que aparecem mais de uma vez
///    no texto — os "conceitos" mais prováveis do material.
/// 4. Pontua cada frase pela quantidade desses termos que ela contém e
///    seleciona as de maior pontuação, até um máximo de 8 e no mínimo 4
///    (se houver frases suficientes) — sempre respeitando a ordem original
///    do texto na montagem final, para o resumo continuar legível.
class StudySummaryGenerator {
  StudySummaryGenerator._();

  /// Faixa de tamanho do resumo pedida para esta etapa.
  static const int minSentences = 4;
  static const int maxSentences = 8;

  /// Abaixo deste tamanho de texto de entrada, não há conteúdo real o
  /// bastante para resumir (mesmo critério de "texto insuficiente" da
  /// extração, ver `PdfTextExtractorService.minUsefulChars`).
  static const int minInputChars = 300;

  /// Teto de tamanho do resumo final, para não ficar enorme mesmo com 8
  /// frases longas.
  static const int maxSummaryChars = 1600;

  static const int _minSentenceChars = 30;
  static const int _maxSentenceChars = 300;

  static const Set<String> _stopWords = {
    'para', 'como', 'isso', 'esse', 'essa', 'esses', 'essas', 'este', 'esta',
    'estes', 'estas', 'aquele', 'aquela', 'aqueles', 'aquelas', 'sobre',
    'entre', 'quando', 'onde', 'mais', 'menos', 'muito', 'muita', 'muitos',
    'muitas', 'pouco', 'pouca', 'também', 'ainda', 'sendo', 'assim', 'então',
    'porque', 'porém', 'todos', 'todas', 'cada', 'pelo', 'pela', 'pelos',
    'pelas', 'pode', 'podem', 'deve', 'devem', 'pois', 'qual', 'quais',
    'quanto', 'quanta', 'seus', 'suas', 'seu', 'sua', 'ele', 'ela', 'eles',
    'elas', 'nesse', 'nessa', 'neste', 'nesta', 'nestes', 'nestas', 'desse',
    'dessa', 'deste', 'desta', 'destes', 'destas', 'nosso', 'nossa',
    'nossos', 'nossas', 'foram', 'foi', 'são', 'está', 'estão', 'tem',
    'têm', 'haver', 'houve', 'sido', 'toda', 'todo', 'apenas', 'outro',
    'outra', 'outros', 'outras', 'algum', 'alguma', 'alguns', 'algumas',
    'mesmo', 'mesma', 'mesmos', 'mesmas', 'antes', 'depois', 'durante',
    'dentro', 'fora', 'sempre', 'nunca', 'já', 'não', 'sim',
  };

  /// Nunca lança: se o texto de entrada não tiver conteúdo/frases
  /// suficientes, devolve `status: failed` em vez de um resumo vazio ou
  /// genérico.
  static StudySummaryResult generate(String extractedText) {
    final text = extractedText.trim();
    if (text.length < minInputChars) {
      return const StudySummaryResult(
        status: SummaryStatus.failed,
        summary: '',
        message: 'Resumo indisponível: não foi possível extrair texto do PDF.',
      );
    }

    final sentences = _dedupeSentences(_splitIntoSentences(text));
    if (sentences.length < minSentences) {
      return const StudySummaryResult(
        status: SummaryStatus.failed,
        summary: '',
        message: 'Resumo indisponível: não foi possível extrair texto do PDF.',
      );
    }

    final keyTerms = _extractKeyTerms(text);
    final scored = sentences
        .map((s) => MapEntry(s, _relevanceScore(s, keyTerms)))
        .toList();
    final rankedByScore = [...scored]
      ..sort((a, b) => b.value.compareTo(a.value));

    final take = sentences.length < maxSentences
        ? sentences.length
        : maxSentences;
    final selected = rankedByScore.take(take).map((e) => e.key).toSet();
    // Restaura a ordem original do texto (não a ordem de pontuação) para o
    // resumo final ler de forma coerente, como um parágrafo de verdade.
    final ordered = sentences.where(selected.contains).toList();

    final buffer = StringBuffer();
    for (final sentence in ordered) {
      if (buffer.isNotEmpty && buffer.length + sentence.length + 1 > maxSummaryChars) {
        break;
      }
      if (buffer.isNotEmpty) buffer.write(' ');
      buffer.write(sentence);
    }

    return StudySummaryResult(
      status: SummaryStatus.success,
      summary: buffer.toString(),
    );
  }

  static List<String> _splitIntoSentences(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return [];
    return normalized
        .split(RegExp(r'(?<=[.!?])\s+'))
        .map((s) => s.trim())
        .where((s) => s.length >= _minSentenceChars && s.length <= _maxSentenceChars)
        .where((s) => !_looksLikeCaptionOrSource(s))
        .toList();
  }

  static final RegExp _captionPattern = RegExp(
    r'^\s*(Figura|Tabela|Quadro|Gr[áa]fico)\b',
    caseSensitive: false,
  );
  static final RegExp _sourceAttributionPattern = RegExp(
    r'Fonte:\s*Adaptado',
    caseSensitive: false,
  );

  /// Legendas de figura/tabela e linhas de "Fonte: Adaptado de ..." são
  /// ruído comum de PDF acadêmico: repetem palavras-chave do texto (o que
  /// as faria pontuar bem em [_relevanceScore]) sem carregar nenhum
  /// conceito explicado de verdade — por isso são descartadas antes da
  /// pontuação, não depois.
  static bool _looksLikeCaptionOrSource(String sentence) {
    return _captionPattern.hasMatch(sentence) ||
        _sourceAttributionPattern.hasMatch(sentence);
  }

  static List<String> _dedupeSentences(List<String> sentences) {
    final seen = <String>{};
    final result = <String>[];
    for (final sentence in sentences) {
      final key = sentence.toLowerCase();
      if (seen.contains(key)) continue;
      seen.add(key);
      result.add(sentence);
    }
    return result;
  }

  static List<String> _extractKeyTerms(String text, {int maxTerms = 15}) {
    final counts = <String, int>{};
    for (final match in RegExp(r'[A-Za-zÀ-ÿ]{4,}').allMatches(text)) {
      final word = match.group(0)!.toLowerCase();
      if (_stopWords.contains(word)) continue;
      counts[word] = (counts[word] ?? 0) + 1;
    }
    final recurring = counts.entries.where((e) => e.value > 1).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return recurring.take(maxTerms).map((e) => e.key).toList();
  }

  static int _relevanceScore(String sentence, List<String> keyTerms) {
    final lower = sentence.toLowerCase();
    var score = 0;
    for (final term in keyTerms) {
      if (lower.contains(term)) score++;
    }
    return score;
  }
}
