// Validação REAL (fim a fim, via widget test) de que a tela "Feedback do
// quiz" (PerformanceScreen) mostra em "Pontos fortes"/"O que revisar" os
// termos de verdade do material que o usuário acertou/errou durante o
// quiz — não mais as tags fixas ('Inclusão digital'/'Tecnologia' etc.)
// sem relação com o PDF estudado. O teste roda o fluxo inteiro pela
// árvore de widgets (responde as perguntas tocando nas alternativas de
// verdade), não chama nenhuma função de estado privada diretamente.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:estudo_em_foco/main.dart';
import 'package:estudo_em_foco/local_store.dart';

void main() {
  testWidgets(
    'PerformanceScreen mostra em "Pontos fortes"/"O que revisar" os termos '
    'reais do material que o usuário acertou/errou no quiz',
    (tester) async {
      // Viewport bem alto: o conteúdo de cada pergunta (card + dica +
      // botão) não cabe nos 600px padrão de teste, e tap() não rola a
      // ListView sozinho até o alvo — mais simples aumentar o viewport do
      // que encadear ensureVisible em cada alternativa.
      tester.view.physicalSize = const Size(800, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Texto com só dois conceitos técnicos permitidos sozinhos
      // ("sensores"/"atuadores", ver kQuizAllowedSoloTechnicalTerms) —
      // nenhuma palavra genérica banida (kQuizBannedSoloConcepts) e
      // nenhum dos conceitos compostos curados, para o teste controlar
      // exatamente quais 2 conceitos entram no quiz.
      const text =
          'Os sensores transformam movimento em corrente elétrica de '
          'forma direta e constante durante toda a operação do '
          'equipamento. Os atuadores convertem corrente elétrica em '
          'movimento mecânico de forma direta e constante durante toda '
          'a operação do equipamento.';
      const fileName = 'Aula 1 - Instrumentação.pdf';

      final material = StudyMaterial(
        id: 'perf-1',
        fileName: fileName,
        extractedText: text,
        extractionStatus: PdfExtractionStatus.success,
      );

      // Mesma função pura usada pela tela — dá o gabarito (qual opção é a
      // certa e a qual termo cada pergunta pertence) para o teste decidir
      // o que tocar, sem hardcodar índices que quebrariam se a ordem das
      // perguntas mudasse.
      final expected = generateQuizFromText(
        text: text,
        materialTitle: detectMaterialTheme(fileName),
      );
      expect(
        expected.map((q) => q.term).toSet(),
        containsAll(['sensores', 'atuadores']),
        reason: 'O texto de teste deveria gerar perguntas para ambos os '
            'conceitos técnicos permitidos.',
      );

      await tester.pumpWidget(
        MaterialApp(home: QuizScreen(material: material)),
      );
      await tester.pumpAndSettle();

      for (var i = 0; i < expected.length; i++) {
        final q = expected[i];
        final isLast = i == expected.length - 1;

        // "sensores" -> respondida CERTA; "atuadores" -> respondida
        // ERRADA; qualquer outra (pergunta sem termo único) -> certa,
        // para não interferir nas duas listas sob teste.
        final optionToTap = q.term == 'atuadores'
            ? q.options.firstWhere((o) => o != q.options[q.correct])
            : q.options[q.correct];

        await tester.tap(find.text(optionToTap).first);
        await tester.pumpAndSettle();

        await tester.tap(
          find.text(isLast ? 'Ver resultado' : 'Próxima pergunta'),
        );
        await tester.pumpAndSettle();
      }

      // Chegou em PerformanceScreen com as tags reais, não os fallbacks.
      expect(find.text('Sensores'), findsOneWidget);
      expect(find.text('Atuadores'), findsOneWidget);
      expect(
        find.text('Responda o quiz para ver seus pontos fortes'),
        findsNothing,
      );
      expect(find.text('Nenhum tópico para revisar agora'), findsNothing);
    },
  );
}
