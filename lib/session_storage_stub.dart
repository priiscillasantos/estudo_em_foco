// Implementação usada em plataformas que não são Flutter Web (e nos testes,
// que rodam na VM do Dart): não existe `sessionStorage` de navegador fora do
// contexto web, então a sessão ativa fica só numa variável estática — dura
// pelo tempo do processo, o mesmo tanto que faria sentido sem um navegador
// de verdade por trás. Ver `session_storage.dart` (export condicional) e
// `session_storage_web.dart` (implementação real usada em builds web).

String? _sessionEmail;

String? readSessionEmail() => _sessionEmail;

void writeSessionEmail(String? email) {
  _sessionEmail = email;
}
