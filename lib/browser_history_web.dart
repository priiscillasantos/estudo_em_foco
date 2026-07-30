// Controle PRÓPRIO do histórico do navegador (só Flutter Web).
//
// Por que o app faz isso em vez de deixar o motor do Flutter cuidar: o
// mecanismo do motor mantém UMA entrada protetora e a **recria durante o
// tratamento do próprio voltar**. O Chrome no Android descarta entradas
// criadas assim (sem gesto do usuário) — é uma proteção do navegador
// contra páginas que "prendem" o botão voltar. Resultado prático no
// celular: o 1º voltar funcionava (consumia a entrada criada no
// carregamento da página, que o Chrome respeita) e o 2º saía do site,
// porque a entrada recriada não valia.
//
// Aqui as entradas são criadas SEMPRE durante um gesto do usuário (ao
// tocar numa aba, ao abrir o leitor/quiz/feedback), que é o caso que o
// Chrome respeita. Cada voltar consome uma entrada de verdade e vira
// navegação interna, sem depender de recriar nada.
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Marca as entradas criadas por este app, para não confundir com
/// entradas de outras páginas do histórico.
const String _entryMarker = 'estudo-em-foco';

/// Cria a entrada base (no contexto do carregamento da página) e passa a
/// escutar o voltar do navegador/Android, encaminhando para [onBrowserBack].
void initBrowserBackGuard(void Function() onBrowserBack) {
  pushSafeHistoryEntry();
  web.window.addEventListener(
    'popstate',
    ((web.Event _) => onBrowserBack()).toJS,
  );
}

/// Empilha uma entrada de histórico "de verdade" no navegador.
///
/// Deve ser chamada durante um gesto do usuário que aprofunda a
/// navegação (trocar de aba, abrir o leitor de PDF, abrir o quiz), para
/// que exista o que o próximo voltar consumir. Não altera a URL — só a
/// profundidade do histórico.
void pushSafeHistoryEntry() {
  web.window.history.pushState(
    _entryMarker.toJS,
    '',
    web.window.location.href,
  );
}
