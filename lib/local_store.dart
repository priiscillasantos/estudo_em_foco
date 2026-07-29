// Autenticação e persistência LOCAIS e DEMONSTRATIVAS.
//
// Este arquivo implementa um cadastro/login simples usando SharedPreferences
// (armazenamento do navegador no Flutter Web) apenas para fins de MVP
// acadêmico. As senhas são guardadas em texto puro e não há nenhum
// mecanismo de criptografia, hashing, tokens de sessão seguros ou proteção
// contra acesso ao armazenamento local do navegador.
//
// NÃO é uma solução de autenticação de produção e NÃO deve ser usada como
// referência de segurança real. Para produção seria necessário um backend
// (ex.: Firebase Auth, ou outro serviço) com hashing de senha, tokens e
// comunicação segura.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Conta de estudante cadastrada localmente.
class UserAccount {
  final String id;
  final String name;
  final String email;
  final String password;

  const UserAccount({
    required this.id,
    required this.name,
    required this.email,
    required this.password,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'password': password,
  };

  factory UserAccount.fromJson(Map<String, dynamic> json) => UserAccount(
    id: json['id'] as String,
    name: json['name'] as String,
    email: json['email'] as String,
    password: json['password'] as String,
  );
}

/// Resultado da extração automática de texto de um material (ver
/// `PdfTextExtractorService` em pdf_text_extractor_service.dart):
/// [pending] enquanto a extração ainda não terminou (ou nunca rodou —
/// materiais recarregados sem os bytes do PDF em memória ficam presos
/// aqui), [success] quando extraiu texto útil o bastante, [failed] quando
/// não conseguiu (PDF protegido/escaneado/corrompido ou texto insuficiente).
enum PdfExtractionStatus { pending, success, failed }

/// Resultado da geração automática de resumo (ver `StudySummaryGenerator`
/// em study_summary_generator.dart): mesma semântica de
/// [PdfExtractionStatus], mas para o resumo — [failed] cobre tanto "sem
/// texto extraído para resumir" quanto "texto extraído mas sem frases
/// aproveitáveis o bastante para montar um resumo".
enum SummaryStatus { pending, success, failed }

/// Um PDF que o estudante carregou em "Material de estudo".
///
/// [bytes] guarda o conteúdo binário real do PDF para que a leitura possa
/// abrir o arquivo de verdade, mas é **intencionalmente excluído** de
/// [toJson] — persistir o PDF inteiro dentro do SharedPreferences (texto)
/// não é viável nesta demonstração. Isso significa que [bytes] só existe
/// durante a sessão atual: se o app/navegador for recarregado, o material
/// continua aparecendo na lista (nome e id sobrevivem), mas precisa ser
/// carregado novamente para reabrir a leitura. A tela de leitura mostra essa
/// limitação de forma explícita em vez de falhar silenciosamente.
///
/// [extractedText] é o texto real extraído do PDF, já limpo (ver
/// `_MaterialStudyPageState._extractTextInBackground` em main.dart e
/// `PdfTextExtractorService`) — string vazia enquanto [extractionStatus]
/// não for [PdfExtractionStatus.success]. Diferente de [bytes], é pequeno o
/// bastante para persistir em [toJson], então continua associado ao mesmo
/// PDF mesmo depois de recarregar a página. [extractionMessage] traz uma
/// explicação amigável quando [extractionStatus] é [PdfExtractionStatus.failed].
///
/// [generatedSummary] é o resumo automático montado a partir de
/// [extractedText] (ver `StudySummaryGenerator`) assim que a extração
/// termina — string vazia enquanto [summaryStatus] não for
/// [SummaryStatus.success]. [summaryMessage] explica quando
/// [summaryStatus] é [SummaryStatus.failed].
///
/// [userSummary] é o "texto base"/resumo que o próprio usuário digita para
/// aquele material (ver "Adicionar resumo"/"Editar texto base" em
/// `_MaterialListCard` em main.dart) — como a extração automática de texto
/// do PDF nem sempre funciona (PDF escaneado, protegido etc.), esse resumo
/// manual tem prioridade sobre [extractedText] na hora de gerar o quiz (ver
/// `_QuizScreenState._effectiveBaseText` em main.dart). Não confundir com
/// [generatedSummary], que é automático e ainda não é usado pelo quiz.
class StudyMaterial {
  final String id;
  final String fileName;
  final int? pageCount;
  final Uint8List? bytes;
  final String extractedText;
  final PdfExtractionStatus extractionStatus;
  final String? extractionMessage;
  final String generatedSummary;
  final SummaryStatus summaryStatus;
  final String? summaryMessage;
  final String? userSummary;

  StudyMaterial({
    required this.id,
    required this.fileName,
    this.pageCount,
    this.bytes,
    this.extractedText = '',
    this.extractionStatus = PdfExtractionStatus.pending,
    this.extractionMessage,
    this.generatedSummary = '',
    this.summaryStatus = SummaryStatus.pending,
    this.summaryMessage,
    this.userSummary,
  });

  StudyMaterial copyWith({
    int? pageCount,
    String? extractedText,
    PdfExtractionStatus? extractionStatus,
    String? extractionMessage,
    bool clearExtractionMessage = false,
    String? generatedSummary,
    SummaryStatus? summaryStatus,
    String? summaryMessage,
    bool clearSummaryMessage = false,
    String? userSummary,
  }) => StudyMaterial(
    id: id,
    fileName: fileName,
    pageCount: pageCount ?? this.pageCount,
    bytes: bytes,
    extractedText: extractedText ?? this.extractedText,
    extractionStatus: extractionStatus ?? this.extractionStatus,
    extractionMessage: clearExtractionMessage
        ? null
        : (extractionMessage ?? this.extractionMessage),
    generatedSummary: generatedSummary ?? this.generatedSummary,
    summaryStatus: summaryStatus ?? this.summaryStatus,
    summaryMessage: clearSummaryMessage
        ? null
        : (summaryMessage ?? this.summaryMessage),
    userSummary: userSummary ?? this.userSummary,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'fileName': fileName,
    'pageCount': pageCount,
    'extractedText': extractedText,
    'extractionStatus': extractionStatus.name,
    'extractionMessage': extractionMessage,
    'generatedSummary': generatedSummary,
    'summaryStatus': summaryStatus.name,
    'summaryMessage': summaryMessage,
    'userSummary': userSummary,
  };

  factory StudyMaterial.fromJson(Map<String, dynamic> json) => StudyMaterial(
    id: json['id'] as String,
    fileName: json['fileName'] as String,
    pageCount: json['pageCount'] as int?,
    extractedText: json['extractedText'] as String? ?? '',
    extractionStatus: _extractionStatusFromName(
      json['extractionStatus'] as String?,
    ),
    extractionMessage: json['extractionMessage'] as String?,
    generatedSummary: json['generatedSummary'] as String? ?? '',
    summaryStatus: _summaryStatusFromName(json['summaryStatus'] as String?),
    summaryMessage: json['summaryMessage'] as String?,
    userSummary: json['userSummary'] as String?,
  );
}

PdfExtractionStatus _extractionStatusFromName(String? name) {
  return PdfExtractionStatus.values.firstWhere(
    (status) => status.name == name,
    orElse: () => PdfExtractionStatus.pending,
  );
}

SummaryStatus _summaryStatusFromName(String? name) {
  return SummaryStatus.values.firstWhere(
    (status) => status.name == name,
    orElse: () => SummaryStatus.pending,
  );
}

/// Estatísticas de desempenho demonstrativas, associadas a uma conta.
class UserProgress {
  final int quizzesCompleted;
  final int acertosTotal;
  final int sequenciaDias;
  final int tempoEstudoMinutos;

  const UserProgress({
    this.quizzesCompleted = 0,
    this.acertosTotal = 0,
    this.sequenciaDias = 0,
    this.tempoEstudoMinutos = 0,
  });

  /// Percentual de acerto derivado (3 perguntas por quiz), 0 a 100.
  int get percent {
    if (quizzesCompleted == 0) return 0;
    final value = (acertosTotal / (quizzesCompleted * 3) * 100).round();
    return value.clamp(0, 100);
  }

  UserProgress copyWith({
    int? quizzesCompleted,
    int? acertosTotal,
    int? sequenciaDias,
    int? tempoEstudoMinutos,
  }) => UserProgress(
    quizzesCompleted: quizzesCompleted ?? this.quizzesCompleted,
    acertosTotal: acertosTotal ?? this.acertosTotal,
    sequenciaDias: sequenciaDias ?? this.sequenciaDias,
    tempoEstudoMinutos: tempoEstudoMinutos ?? this.tempoEstudoMinutos,
  );

  Map<String, dynamic> toJson() => {
    'quizzesCompleted': quizzesCompleted,
    'acertosTotal': acertosTotal,
    'sequenciaDias': sequenciaDias,
    'tempoEstudoMinutos': tempoEstudoMinutos,
  };

  factory UserProgress.fromJson(Map<String, dynamic> json) => UserProgress(
    quizzesCompleted: json['quizzesCompleted'] as int? ?? 0,
    acertosTotal: json['acertosTotal'] as int? ?? 0,
    sequenciaDias: json['sequenciaDias'] as int? ?? 0,
    tempoEstudoMinutos: json['tempoEstudoMinutos'] as int? ?? 0,
  );
}

/// Uma marcação (destaque ou traço de lápis) feita pelo estudante sobre uma
/// página do PDF durante a leitura. É uma camada visual apenas — nunca
/// edita nem gera um novo arquivo PDF.
///
/// [fileName] identifica o material (não [StudyMaterial.id], que muda a
/// cada novo upload do mesmo arquivo): é o que permite reencontrar as
/// anotações se o estudante recarregar o mesmo PDF em outra sessão.
/// [points] fica em coordenadas normalizadas (0.0 a 1.0, relativas à área
/// visível do leitor no momento em que a marcação foi feita) — 2 pontos
/// (cantos) para [type] `'highlight'`, vários pontos para o traço de
/// `'pen'`. [color] é o valor ARGB da cor (ver `Color.value`).
class PageAnnotation {
  final String id;
  final String fileName;
  final String userEmail;
  final int pageNumber;
  final String type;
  final List<List<double>> points;
  final int color;
  final DateTime createdAt;

  const PageAnnotation({
    required this.id,
    required this.fileName,
    required this.userEmail,
    required this.pageNumber,
    required this.type,
    required this.points,
    required this.color,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'fileName': fileName,
    'userEmail': userEmail,
    'pageNumber': pageNumber,
    'type': type,
    'points': points,
    'color': color,
    'createdAt': createdAt.toIso8601String(),
  };

  factory PageAnnotation.fromJson(Map<String, dynamic> json) => PageAnnotation(
    id: json['id'] as String,
    fileName: json['fileName'] as String,
    userEmail: json['userEmail'] as String,
    pageNumber: json['pageNumber'] as int,
    type: json['type'] as String,
    points: (json['points'] as List<dynamic>)
        .map(
          (p) =>
              (p as List<dynamic>).map((v) => (v as num).toDouble()).toList(),
        )
        .toList(),
    color: json['color'] as int,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}

/// Erro simples de autenticação local (e-mail em uso, credenciais inválidas).
class AuthException implements Exception {
  final String message;
  const AuthException(this.message);

  @override
  String toString() => message;
}

/// Centraliza toda a leitura/escrita no SharedPreferences para que as telas
/// não precisem conhecer chaves ou formato de armazenamento.
///
/// Toda operação de leitura/escrita é protegida por try/catch com um
/// espelho em memória (`_memory*`) como reserva: se o `localStorage` do
/// navegador estiver bloqueado ou inacessível por qualquer motivo (comum em
/// iframes/painéis de preview sandboxed), o cadastro/login/PDFs/progresso
/// continuam funcionando normalmente durante a sessão atual da página — só
/// não sobrevivem a um recarregamento nesse cenário específico. Isso evita
/// que um problema de armazenamento vire um erro genérico travando o app.
class LocalStore {
  LocalStore._();

  static const _accountsKey = 'accounts';
  static const _sessionKey = 'session_email';
  // Guarda só o e-mail (nunca a senha) do último login/cadastro bem-sucedido,
  // para pré-preencher o campo de e-mail na tela de Login (ver
  // `_LoginScreenState`). Deliberadamente uma chave SEPARADA de
  // [_sessionKey]: "Sair" limpa a sessão ativa, mas não deve apagar essa
  // lembrança — o campo de e-mail continua preenchido depois do logout.
  static const _lastEmailKey = 'last_used_email';

  static String _materialsKey(String email) => 'materials_$email';
  static String _progressKey(String email) => 'progress_$email';
  static String _annotationsKey(String email) => 'annotations_$email';

  static String? _memoryLastEmail;
  static List<UserAccount>? _memoryAccounts;
  static final Map<String, List<StudyMaterial>> _memoryMaterials = {};
  static final Map<String, UserProgress> _memoryProgress = {};
  static final Map<String, List<PageAnnotation>> _memoryAnnotations = {};

  /// Wraps [SharedPreferences.getInstance] with a timeout so a stuck
  /// platform channel can never hang the UI forever — it surfaces as a
  /// catchable [TimeoutException] instead (screens turn that into a plain
  /// error message and re-enable their button).
  static Future<SharedPreferences> _prefs() {
    return SharedPreferences.getInstance().timeout(const Duration(seconds: 8));
  }

  static Future<List<UserAccount>> _loadAccounts() async {
    try {
      final prefs = await _prefs();
      // Uma leitura bem-sucedida do armazenamento é sempre a fonte da
      // verdade, mesmo quando vazia — só cai para a memória se a leitura em
      // si falhar (catch abaixo), nunca por já ter havido dados antes.
      final raw = prefs.getString(_accountsKey);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => UserAccount.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      // Tanto dados corrompidos/incompatíveis quanto um armazenamento
      // indisponível caem aqui — nunca deixamos isso virar um erro genérico
      // no cadastro/login. Usa o espelho em memória desta sessão.
      debugPrint(
        'LocalStore: não foi possível ler contas do armazenamento local, '
        'usando memória temporária desta sessão: $e',
      );
      return _memoryAccounts ?? [];
    }
  }

  static Future<void> _saveAccounts(List<UserAccount> accounts) async {
    _memoryAccounts = accounts;
    try {
      final prefs = await _prefs();
      final raw = jsonEncode(accounts.map((a) => a.toJson()).toList());
      await prefs.setString(_accountsKey, raw);
    } catch (e) {
      debugPrint(
        'LocalStore: não foi possível salvar contas no armazenamento local '
        '(mantidas em memória apenas para esta sessão): $e',
      );
    }
  }

  /// Cria uma nova conta. Lança [AuthException] se o e-mail já existir.
  static Future<UserAccount> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final accounts = await _loadAccounts();
    final exists = accounts.any((a) => a.email == normalizedEmail);
    if (exists) {
      throw const AuthException(
        'Este e-mail já está cadastrado. Use outro e-mail ou faça login.',
      );
    }
    final account = UserAccount(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name.trim(),
      email: normalizedEmail,
      password: password,
    );
    await _saveAccounts([...accounts, account]);
    await _setSession(normalizedEmail);
    await _saveLastEmail(normalizedEmail);
    return account;
  }

  /// Autentica com e-mail/senha. Lança [AuthException] se a conta não
  /// existir ou a senha estiver incorreta.
  static Future<UserAccount> login({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final accounts = await _loadAccounts();
    final account = accounts
        .where((a) => a.email == normalizedEmail)
        .firstOrNull;
    if (account == null) {
      throw const AuthException(
        'Não encontramos uma conta com esse e-mail. Se for seu primeiro '
        'acesso, toque em Criar conta.',
      );
    }
    if (account.password != password) {
      throw const AuthException('E-mail ou senha incorretos.');
    }
    await _setSession(normalizedEmail);
    await _saveLastEmail(normalizedEmail);
    return account;
  }

  /// Guarda só o e-mail (nunca a senha) do login/cadastro bem-sucedido mais
  /// recente, para pré-preencher o campo de e-mail na próxima vez que a
  /// tela de Login abrir (ver [loadLastEmail]). Sobrescreve o e-mail
  /// anterior se outra conta fizer login depois.
  static Future<void> _saveLastEmail(String email) async {
    _memoryLastEmail = email;
    try {
      final prefs = await _prefs();
      await prefs.setString(_lastEmailKey, email);
    } catch (e) {
      debugPrint(
        'LocalStore: não foi possível salvar o último e-mail usado '
        '(mantido em memória apenas para esta sessão): $e',
      );
    }
  }

  /// Devolve o último e-mail usado com sucesso em login/cadastro, ou `null`
  /// se nenhum usuário nunca entrou neste navegador. Nunca lê/expõe senha
  /// nenhuma — só o e-mail.
  static Future<String?> loadLastEmail() async {
    try {
      final prefs = await _prefs();
      final email = prefs.getString(_lastEmailKey);
      return (email == null || email.isEmpty) ? null : email;
    } catch (e) {
      debugPrint(
        'LocalStore: não foi possível ler o último e-mail usado, usando '
        'memória temporária desta sessão: $e',
      );
      return _memoryLastEmail;
    }
  }

  static Future<void> _setSession(String? email) async {
    try {
      final prefs = await _prefs();
      if (email == null) {
        await prefs.remove(_sessionKey);
      } else {
        await prefs.setString(_sessionKey, email);
      }
    } catch (e) {
      debugPrint(
        'LocalStore: não foi possível salvar a sessão no armazenamento '
        'local (mantida em memória apenas para esta sessão): $e',
      );
    }
  }

  static Future<void> logout() => _setSession(null);

  static Future<List<StudyMaterial>> loadMaterials(String email) async {
    try {
      final prefs = await _prefs();
      final raw = prefs.getString(_materialsKey(email));
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => StudyMaterial.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint(
        'LocalStore: não foi possível ler materiais do armazenamento local, '
        'usando memória temporária desta sessão: $e',
      );
      return _memoryMaterials[email] ?? [];
    }
  }

  static Future<void> saveMaterials(
    String email,
    List<StudyMaterial> materials,
  ) async {
    _memoryMaterials[email] = materials;
    try {
      final prefs = await _prefs();
      final raw = jsonEncode(materials.map((m) => m.toJson()).toList());
      await prefs.setString(_materialsKey(email), raw);
    } catch (e) {
      debugPrint(
        'LocalStore: não foi possível salvar materiais no armazenamento '
        'local (mantidos em memória apenas para esta sessão): $e',
      );
    }
  }

  static Future<UserProgress> loadProgress(String email) async {
    try {
      final prefs = await _prefs();
      final raw = prefs.getString(_progressKey(email));
      if (raw == null || raw.isEmpty) return const UserProgress();
      return UserProgress.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint(
        'LocalStore: não foi possível ler progresso do armazenamento local, '
        'usando memória temporária desta sessão: $e',
      );
      return _memoryProgress[email] ?? const UserProgress();
    }
  }

  static Future<void> saveProgress(String email, UserProgress progress) async {
    _memoryProgress[email] = progress;
    try {
      final prefs = await _prefs();
      await prefs.setString(_progressKey(email), jsonEncode(progress.toJson()));
    } catch (e) {
      debugPrint(
        'LocalStore: não foi possível salvar progresso no armazenamento '
        'local (mantido em memória apenas para esta sessão): $e',
      );
    }
  }

  /// Anotações (destaques/traços de lápis) de todos os materiais e páginas
  /// de um usuário, feitas na tela de leitura. Filtre por
  /// [PageAnnotation.fileName]/[PageAnnotation.pageNumber] na tela.
  static Future<List<PageAnnotation>> loadAnnotations(String email) async {
    try {
      final prefs = await _prefs();
      final raw = prefs.getString(_annotationsKey(email));
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => PageAnnotation.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint(
        'LocalStore: não foi possível ler anotações do armazenamento local, '
        'usando memória temporária desta sessão: $e',
      );
      return _memoryAnnotations[email] ?? [];
    }
  }

  static Future<void> saveAnnotations(
    String email,
    List<PageAnnotation> annotations,
  ) async {
    _memoryAnnotations[email] = annotations;
    try {
      final prefs = await _prefs();
      final raw = jsonEncode(annotations.map((a) => a.toJson()).toList());
      await prefs.setString(_annotationsKey(email), raw);
    } catch (e) {
      debugPrint(
        'LocalStore: não foi possível salvar anotações no armazenamento '
        'local (mantidas em memória apenas para esta sessão): $e',
      );
    }
  }

  /// Apaga TODOS os dados desta demonstração local: contas cadastradas,
  /// sessão ativa, materiais e progresso de todos os usuários (inclusive o
  /// espelho em memória). Pensado para permitir recomeçar o cadastro do
  /// zero antes de gravar uma demo — não é chamado automaticamente em
  /// nenhum outro fluxo do app.
  static Future<void> clearAllTestData() async {
    _memoryAccounts = null;
    _memoryMaterials.clear();
    _memoryProgress.clear();
    _memoryAnnotations.clear();
    try {
      final prefs = await _prefs();
      await prefs.clear();
    } catch (e) {
      debugPrint(
        'LocalStore: não foi possível limpar o armazenamento local '
        '(a memória desta sessão já foi limpa): $e',
      );
    }
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
