// Controle do histórico do navegador para o botão voltar do
// navegador/Android. Em builds web usa `browser_history_web.dart`
// (history.pushState + popstate); fora da web, e nos testes que rodam na
// VM, cai no stub sem efeito de `browser_history_stub.dart`.
export 'browser_history_stub.dart'
    if (dart.library.js_interop) 'browser_history_web.dart';
