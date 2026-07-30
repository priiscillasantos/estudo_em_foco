// Implementação usada fora do Flutter Web (e nos testes, que rodam na VM
// do Dart): não existe histórico de navegador para controlar, então as
// duas operações não fazem nada. Ver `browser_history.dart` (export
// condicional) e `browser_history_web.dart` (implementação real).

void initBrowserBackGuard(void Function() onBrowserBack) {}

void pushSafeHistoryEntry() {}
