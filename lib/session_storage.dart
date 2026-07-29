// Guarda só o e-mail da sessão ATIVA (nunca a senha) em
// `window.sessionStorage` no Flutter Web — ver `session_storage_web.dart`
// para o porquê de ser sessionStorage e não localStorage. Fora da web (ou
// nos testes, que rodam na VM), cai no stub em memória de
// `session_storage_stub.dart`.
export 'session_storage_stub.dart'
    if (dart.library.js_interop) 'session_storage_web.dart';
