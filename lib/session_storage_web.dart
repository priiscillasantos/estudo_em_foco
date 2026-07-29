// Implementação real (Flutter Web): usa `window.sessionStorage`, que dura
// só enquanto a ABA/sessão do navegador estiver aberta — sobrevive a trocar
// de app, bloquear o celular ou recarregar a página (a aba continua sendo a
// mesma sessão), mas some sozinha quando a aba/navegador é fechado de
// verdade ou quando os dados do navegador são limpos. É por isso que essa
// chave é separada das contas/materiais/progresso em `local_store.dart`
// (esses usam `shared_preferences`/`localStorage`, que sobrevivem para
// sempre): a sessão ATIVA não deve virar um "login automático permanente".
import 'package:web/web.dart' as web;

const _sessionEmailKey = 'session_email';

String? readSessionEmail() {
  final email = web.window.sessionStorage.getItem(_sessionEmailKey);
  return (email == null || email.isEmpty) ? null : email;
}

void writeSessionEmail(String? email) {
  if (email == null) {
    web.window.sessionStorage.removeItem(_sessionEmailKey);
  } else {
    web.window.sessionStorage.setItem(_sessionEmailKey, email);
  }
}
