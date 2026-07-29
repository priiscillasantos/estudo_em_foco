import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:estudo_em_foco/main.dart';
import 'package:estudo_em_foco/local_store.dart';
import 'package:estudo_em_foco/pdf_text_extractor_service.dart';

/// Simula um `localStorage` bloqueado/indisponível (ex.: iframe sandboxed),
/// usado para provar que o fallback em memória do [LocalStore] evita o erro
/// genérico e o botão travado em "Carregando..." quando a gravação falha.
class _ThrowingSharedPreferencesStore extends SharedPreferencesStorePlatform {
  @override
  Future<bool> remove(String key) async =>
      throw Exception('armazenamento local indisponível (simulado)');

  @override
  Future<bool> setValue(String valueType, String key, Object value) async =>
      throw Exception('armazenamento local indisponível (simulado)');

  @override
  Future<bool> clear() async =>
      throw Exception('armazenamento local indisponível (simulado)');

  @override
  Future<Map<String, Object>> getAll() async =>
      throw Exception('armazenamento local indisponível (simulado)');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    currentAccount.value = null;
    currentProgress.value = const UserProgress();
    mainShellTabIndex.value = 0;
    // A sessão ativa vive fora do SharedPreferences (ver
    // `session_storage.dart`/AJUSTE de persistência de sessão), então
    // `setMockInitialValues` sozinho não a limpa entre testes.
    await LocalStore.logout();
  });

  testWidgets('onboarding shows welcome content', (WidgetTester tester) async {
    await tester.pumpWidget(const EstudoEmFocoApp());

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName == kOnboardingAsset,
      ),
      findsOneWidget,
    );
    expect(find.text('Começar'), findsOneWidget);
    expect(find.text('Já tenho uma conta'), findsOneWidget);
  });

  testWidgets('sign up creates an account and opens Home', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const EstudoEmFocoApp());

    await tester.ensureVisible(find.text('Começar'));
    await tester.tap(find.text('Começar'));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);

    await tester.ensureVisible(find.text('Primeiro acesso? Criar conta'));
    await tester.tap(find.text('Primeiro acesso? Criar conta'));
    await tester.pumpAndSettle();

    expect(find.byType(SignUpScreen), findsOneWidget);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Priscila');
    await tester.enterText(fields.at(1), 'priscila@exemplo.com');
    await tester.enterText(fields.at(2), 'senha123');

    await tester.ensureVisible(find.text('Cadastrar'));
    await tester.tap(find.text('Cadastrar'));
    await tester.pumpAndSettle();

    expect(find.byType(MainShell), findsOneWidget);
    expect(find.textContaining('Olá, Priscila!'), findsOneWidget);
    expect(currentAccount.value?.email, 'priscila@exemplo.com');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'sign up with a taken e-mail shows the duplicate-account message and '
    'never gets stuck on "Carregando..."',
    (WidgetTester tester) async {
      await LocalStore.signUp(
        name: 'Aluno 1',
        email: 'aluno1@estudo.com',
        password: '123456',
      );
      await LocalStore.logout();

      await tester.pumpWidget(const EstudoEmFocoApp());

      await tester.ensureVisible(find.text('Começar'));
      await tester.tap(find.text('Começar'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Primeiro acesso? Criar conta'));
      await tester.tap(find.text('Primeiro acesso? Criar conta'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Outro Aluno');
      await tester.enterText(fields.at(1), 'aluno1@estudo.com');
      await tester.enterText(fields.at(2), 'outrasenha');

      await tester.ensureVisible(find.text('Cadastrar'));
      await tester.tap(find.text('Cadastrar'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Este e-mail já está cadastrado. Use outro e-mail ou faça login.',
        ),
        findsOneWidget,
      );
      // The button must return to its normal label, never stay stuck on
      // "Carregando...", and the app must not have navigated away.
      expect(find.text('Cadastrar'), findsOneWidget);
      expect(find.text('Carregando...'), findsNothing);
      expect(find.byType(MainShell), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'two students can sign up with different e-mails, each seeing only '
    'their own name/e-mail in Perfil, and logout always returns to Início',
    (WidgetTester tester) async {
      Future<void> signUp(String name, String email, String password) async {
        await tester.ensureVisible(find.text('Primeiro acesso? Criar conta'));
        await tester.tap(find.text('Primeiro acesso? Criar conta'));
        await tester.pumpAndSettle();

        final fields = find.byType(TextFormField);
        await tester.enterText(fields.at(0), name);
        await tester.enterText(fields.at(1), email);
        await tester.enterText(fields.at(2), password);

        await tester.ensureVisible(find.text('Cadastrar'));
        await tester.tap(find.text('Cadastrar'));
        await tester.pumpAndSettle();
      }

      await tester.pumpWidget(const EstudoEmFocoApp());
      await tester.ensureVisible(find.text('Começar'));
      await tester.tap(find.text('Começar'));
      await tester.pumpAndSettle();

      // --- Aluno 1 ---
      await signUp('Aluno 1', 'aluno1@estudo.com', '123456');

      expect(find.byType(MainShell), findsOneWidget);
      expect(find.textContaining('Olá, Aluno 1!'), findsOneWidget);

      await tester.tap(find.text('Perfil'));
      await tester.pumpAndSettle();
      expect(find.text('Aluno 1'), findsOneWidget);
      expect(find.text('aluno1@estudo.com'), findsOneWidget);
      expect(find.text('aluno2@estudo.com'), findsNothing);

      // "Sair da conta" is far down Perfil's scroll view, so it isn't built
      // yet (Sliver-based ListView only mounts what's near the viewport) —
      // scroll the list itself until the button exists, then tap it.
      final profileScrollable = find.descendant(
        of: find.byType(ProfilePage),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('Sair da conta'),
        300,
        scrollable: profileScrollable,
      );
      await tester.tap(find.text('Sair da conta'));
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingScreen), findsOneWidget);

      // --- Aluno 2, from a fresh Onboarding->Login->Cadastro run ---
      await tester.ensureVisible(find.text('Começar'));
      await tester.tap(find.text('Começar'));
      await tester.pumpAndSettle();

      await signUp('Aluno 2', 'aluno2@estudo.com', '123456');

      // Logging in must always land on Início, never on the Perfil tab
      // that was active when Aluno 1 signed out.
      expect(find.byType(MainShell), findsOneWidget);
      expect(find.textContaining('Olá, Aluno 2!'), findsOneWidget);

      await tester.tap(find.text('Perfil'));
      await tester.pumpAndSettle();
      expect(find.text('Aluno 2'), findsOneWidget);
      expect(find.text('aluno2@estudo.com'), findsOneWidget);
      expect(find.text('aluno1@estudo.com'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'full demo flow: clear test data, create both students, catch the '
    'duplicate e-mail, then log each one in separately',
    (WidgetTester tester) async {
      Future<void> goToLogin() async {
        await tester.pumpWidget(const EstudoEmFocoApp());
        await tester.ensureVisible(find.text('Começar'));
        await tester.tap(find.text('Começar'));
        await tester.pumpAndSettle();
      }

      Future<void> signUp(String name, String email, String password) async {
        await tester.ensureVisible(find.text('Primeiro acesso? Criar conta'));
        await tester.tap(find.text('Primeiro acesso? Criar conta'));
        await tester.pumpAndSettle();

        final fields = find.byType(TextFormField);
        await tester.enterText(fields.at(0), name);
        await tester.enterText(fields.at(1), email);
        await tester.enterText(fields.at(2), password);

        await tester.ensureVisible(find.text('Cadastrar'));
        await tester.tap(find.text('Cadastrar'));
        await tester.pumpAndSettle();
      }

      Future<void> logout() async {
        await tester.tap(find.text('Perfil'));
        await tester.pumpAndSettle();
        final profileScrollable = find.descendant(
          of: find.byType(ProfilePage),
          matching: find.byType(Scrollable),
        );
        await tester.scrollUntilVisible(
          find.text('Sair da conta'),
          300,
          scrollable: profileScrollable,
        );
        await tester.tap(find.text('Sair da conta'));
        await tester.pumpAndSettle();
      }

      Future<void> login(String email, String password) async {
        await tester.ensureVisible(find.text('Já tenho uma conta'));
        await tester.tap(find.text('Já tenho uma conta'));
        await tester.pumpAndSettle();

        final fields = find.byType(TextFormField);
        await tester.enterText(fields.at(0), email);
        await tester.enterText(fields.at(1), password);
        await tester.ensureVisible(find.text('Entrar'));
        await tester.tap(find.text('Entrar'));
        await tester.pumpAndSettle();
      }

      // 1. Limpar dados de teste — não existe mais botão nenhum na
      // interface de produção para isso (removido: era um botão técnico
      // "Limpar dados de teste" visível na tela de Login), então o teste
      // chama o mesmo método de limpeza diretamente, como preparação de
      // ambiente, não como uma ação do usuário.
      await LocalStore.clearAllTestData();
      currentAccount.value = null;
      currentProgress.value = const UserProgress();
      await goToLogin();

      // 2. Cadastrar Aluno 1.
      await signUp('Aluno 1', 'aluno1@estudo.com', '123456');
      expect(find.byType(MainShell), findsOneWidget);
      expect(find.textContaining('Olá, Aluno 1!'), findsOneWidget);

      await logout();
      expect(find.byType(OnboardingScreen), findsOneWidget);

      // 3. Tentar cadastrar aluno1@estudo.com de novo -> mensagem exata.
      await tester.ensureVisible(find.text('Começar'));
      await tester.tap(find.text('Começar'));
      await tester.pumpAndSettle();
      await signUp('Aluno 1 Duplicado', 'aluno1@estudo.com', 'outrasenha');

      expect(
        find.text(
          'Este e-mail já está cadastrado. Use outro e-mail ou faça login.',
        ),
        findsOneWidget,
      );
      expect(find.text('Cadastrar'), findsOneWidget);
      expect(find.text('Carregando...'), findsNothing);
      expect(find.byType(MainShell), findsNothing);

      // Volta para o Login e cadastra o Aluno 2 a partir dele. Escopado ao
      // SignUpScreen porque o LoginScreen (embaixo na pilha) também tem uma
      // seta "voltar" com o mesmo ícone. A tela rolou ao preencher a senha,
      // então a seta pode estar acima do topo visível — rola de volta até
      // ela antes de tocar.
      final signUpBackArrow = find.descendant(
        of: find.byType(SignUpScreen),
        matching: find.byIcon(LucideIcons.arrowLeft),
      );
      await tester.scrollUntilVisible(
        signUpBackArrow,
        -300,
        scrollable: find
            .descendant(
              of: find.byType(SignUpScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(signUpBackArrow);
      await tester.pumpAndSettle();

      // 4. Cadastrar Aluno 2.
      await signUp('Aluno 2', 'aluno2@estudo.com', '123456');
      expect(find.byType(MainShell), findsOneWidget);
      expect(find.textContaining('Olá, Aluno 2!'), findsOneWidget);

      await logout();

      // 5. Login separado como Aluno 1 -> Perfil mostra Aluno 1.
      await login('aluno1@estudo.com', '123456');
      expect(find.byType(MainShell), findsOneWidget);
      expect(find.textContaining('Olá, Aluno 1!'), findsOneWidget);

      await tester.tap(find.text('Perfil'));
      await tester.pumpAndSettle();
      expect(find.text('Aluno 1'), findsOneWidget);
      expect(find.text('aluno1@estudo.com'), findsOneWidget);

      await logout();

      // 6. Login separado como Aluno 2 -> Perfil mostra Aluno 2.
      await login('aluno2@estudo.com', '123456');
      expect(find.byType(MainShell), findsOneWidget);
      expect(find.textContaining('Olá, Aluno 2!'), findsOneWidget);

      await tester.tap(find.text('Perfil'));
      await tester.pumpAndSettle();
      expect(find.text('Aluno 2'), findsOneWidget);
      expect(find.text('aluno2@estudo.com'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test('materials and progress stay isolated per account', () async {
    SharedPreferences.setMockInitialValues({});

    await LocalStore.signUp(
      name: 'Aluno 1',
      email: 'aluno1@estudo.com',
      password: '123456',
    );
    await LocalStore.signUp(
      name: 'Aluno 2',
      email: 'aluno2@estudo.com',
      password: '123456',
    );

    await LocalStore.saveMaterials('aluno1@estudo.com', [
      StudyMaterial(id: '1', fileName: 'apostila-aluno1.pdf'),
    ]);
    await LocalStore.saveProgress(
      'aluno1@estudo.com',
      const UserProgress(quizzesCompleted: 2, acertosTotal: 5),
    );

    final aluno1Materials = await LocalStore.loadMaterials('aluno1@estudo.com');
    final aluno2Materials = await LocalStore.loadMaterials('aluno2@estudo.com');
    final aluno1Progress = await LocalStore.loadProgress('aluno1@estudo.com');
    final aluno2Progress = await LocalStore.loadProgress('aluno2@estudo.com');

    expect(aluno1Materials.map((m) => m.fileName), ['apostila-aluno1.pdf']);
    expect(aluno2Materials, isEmpty);
    expect(aluno1Progress.quizzesCompleted, 2);
    expect(aluno2Progress.quizzesCompleted, 0);
  });

  test(
    'signup/login keep working via memory fallback when the local storage '
    'is blocked (e.g. sandboxed browser), instead of a generic error',
    () async {
      SharedPreferencesStorePlatform.instance =
          _ThrowingSharedPreferencesStore();
      addTearDown(() {
        SharedPreferences.setMockInitialValues({});
      });

      final account = await LocalStore.signUp(
        name: 'Aluno3',
        email: 'aluno3@estudo.com',
        password: '123456',
      );
      expect(account.email, 'aluno3@estudo.com');

      final loggedIn = await LocalStore.login(
        email: 'aluno3@estudo.com',
        password: '123456',
      );
      expect(loggedIn.name, 'Aluno3');

      await LocalStore.saveProgress(
        'aluno3@estudo.com',
        const UserProgress(quizzesCompleted: 1, acertosTotal: 3),
      );
      final progress = await LocalStore.loadProgress('aluno3@estudo.com');
      expect(progress.quizzesCompleted, 1);
    },
  );

  testWidgets('login rejects the wrong password and accepts the right one', (
    WidgetTester tester,
  ) async {
    await LocalStore.signUp(
      name: 'Priscila',
      email: 'priscila@exemplo.com',
      password: 'senha123',
    );
    await LocalStore.logout();

    await tester.pumpWidget(const EstudoEmFocoApp());

    await tester.ensureVisible(find.text('Já tenho uma conta'));
    await tester.tap(find.text('Já tenho uma conta'));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'priscila@exemplo.com');
    await tester.enterText(fields.at(1), 'senha-errada');
    await tester.ensureVisible(find.text('Entrar'));
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();

    expect(find.text('E-mail ou senha incorretos.'), findsOneWidget);
    expect(find.byType(MainShell), findsNothing);

    await tester.enterText(fields.at(1), 'senha123');
    await tester.ensureVisible(find.text('Entrar'));
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();

    expect(find.byType(MainShell), findsOneWidget);
    expect(find.textContaining('Olá, Priscila!'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'onboarding mostra a orientação de primeiro acesso e o link de login '
    'convida a criar conta',
    (WidgetTester tester) async {
      await tester.pumpWidget(const EstudoEmFocoApp());
      expect(
        find.text('Primeiro acesso? Toque em Começar para criar sua conta.'),
        findsOneWidget,
      );

      await tester.ensureVisible(find.text('Começar'));
      await tester.tap(find.text('Começar'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('Primeiro acesso? Criar conta'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'e-mail inexistente mostra mensagem orientando a criar conta',
    (WidgetTester tester) async {
      await tester.pumpWidget(const EstudoEmFocoApp());
      await tester.ensureVisible(find.text('Já tenho uma conta'));
      await tester.tap(find.text('Já tenho uma conta'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'ninguem@nao-existe.com');
      await tester.enterText(fields.at(1), 'qualquersenha');
      await tester.ensureVisible(find.text('Entrar'));
      await tester.tap(find.text('Entrar'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Não encontramos uma conta com esse e-mail. Se for seu primeiro '
          'acesso, toque em Criar conta.',
        ),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'lembra o último e-mail usado (nunca a senha) e mantém isso depois do '
    'logout; outro usuário que entrar depois substitui o e-mail lembrado',
    (WidgetTester tester) async {
      Future<void> logout() async {
        await tester.tap(find.text('Perfil'));
        await tester.pumpAndSettle();
        final profileScrollable = find.descendant(
          of: find.byType(ProfilePage),
          matching: find.byType(Scrollable),
        );
        await tester.scrollUntilVisible(
          find.text('Sair da conta'),
          300,
          scrollable: profileScrollable,
        );
        await tester.tap(find.text('Sair da conta'));
        await tester.pumpAndSettle();
      }

      // Cadastra e entra com o e-mail A.
      await tester.pumpWidget(const EstudoEmFocoApp());
      await tester.ensureVisible(find.text('Começar'));
      await tester.tap(find.text('Começar'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Primeiro acesso? Criar conta'));
      await tester.tap(find.text('Primeiro acesso? Criar conta'));
      await tester.pumpAndSettle();

      final signUpFieldsA = find.byType(TextFormField);
      await tester.enterText(signUpFieldsA.at(0), 'Aluno A');
      await tester.enterText(signUpFieldsA.at(1), 'aluno.a@estudo.com');
      await tester.enterText(signUpFieldsA.at(2), 'senhaA123');
      await tester.ensureVisible(find.text('Cadastrar'));
      await tester.tap(find.text('Cadastrar'));
      await tester.pumpAndSettle();

      expect(find.byType(MainShell), findsOneWidget);

      await logout();
      expect(find.byType(OnboardingScreen), findsOneWidget);

      // Volta para o login: e-mail A preenchido, senha sempre vazia.
      await tester.ensureVisible(find.text('Já tenho uma conta'));
      await tester.tap(find.text('Já tenho uma conta'));
      await tester.pumpAndSettle();

      final loginFieldsA = find.byType(TextFormField);
      expect(
        tester.widget<TextFormField>(loginFieldsA.at(0)).controller?.text,
        'aluno.a@estudo.com',
      );
      expect(
        tester.widget<TextFormField>(loginFieldsA.at(1)).controller?.text,
        isEmpty,
      );

      // Entra de novo com A.
      await tester.enterText(loginFieldsA.at(1), 'senhaA123');
      await tester.ensureVisible(find.text('Entrar'));
      await tester.tap(find.text('Entrar'));
      await tester.pumpAndSettle();
      expect(find.byType(MainShell), findsOneWidget);

      await logout();

      // Cadastra o e-mail B: deve substituir o e-mail lembrado. Passa pelo
      // Login primeiro (o link "Primeiro acesso? Criar conta" fica na tela
      // de Login, não na Onboarding).
      await tester.ensureVisible(find.text('Já tenho uma conta'));
      await tester.tap(find.text('Já tenho uma conta'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Primeiro acesso? Criar conta'));
      await tester.tap(find.text('Primeiro acesso? Criar conta'));
      await tester.pumpAndSettle();

      final signUpFieldsB = find.byType(TextFormField);
      await tester.enterText(signUpFieldsB.at(0), 'Aluno B');
      await tester.enterText(signUpFieldsB.at(1), 'aluno.b@estudo.com');
      await tester.enterText(signUpFieldsB.at(2), 'senhaB123');
      await tester.ensureVisible(find.text('Cadastrar'));
      await tester.tap(find.text('Cadastrar'));
      await tester.pumpAndSettle();

      await logout();

      await tester.ensureVisible(find.text('Já tenho uma conta'));
      await tester.tap(find.text('Já tenho uma conta'));
      await tester.pumpAndSettle();

      final loginFieldsB = find.byType(TextFormField);
      expect(
        tester.widget<TextFormField>(loginFieldsB.at(0)).controller?.text,
        'aluno.b@estudo.com',
      );
      expect(
        tester.widget<TextFormField>(loginFieldsB.at(1)).controller?.text,
        isEmpty,
      );

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('main shell redirects to login without an identified user', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: MainShell()));

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Entrar'), findsOneWidget);
  });

  group('botão voltar com sessão ativa (AJUSTE 3)', () {
    Future<void> signUpAndReachMainShell(WidgetTester tester) async {
      await tester.pumpWidget(const EstudoEmFocoApp());
      await tester.ensureVisible(find.text('Começar'));
      await tester.tap(find.text('Começar'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Primeiro acesso? Criar conta'));
      await tester.tap(find.text('Primeiro acesso? Criar conta'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Aluno Voltar');
      await tester.enterText(fields.at(1), 'aluno.voltar@estudo.com');
      await tester.enterText(fields.at(2), 'senha123');
      await tester.ensureVisible(find.text('Cadastrar'));
      await tester.tap(find.text('Cadastrar'));
      await tester.pumpAndSettle();

      expect(find.byType(MainShell), findsOneWidget);
    }

    testWidgets(
      'reabrir Onboarding/Login/Cadastro com sessão ativa (ex.: entrada '
      'antiga no histórico do navegador) redireciona de volta para o app, '
      'em vez de aparentar que a sessão foi perdida',
      (WidgetTester tester) async {
        await signUpAndReachMainShell(tester);

        for (final stale in [
          const OnboardingScreen(),
          const LoginScreen(),
          const SignUpScreen(),
        ]) {
          final context = tester.element(find.byType(MainShell));
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => stale),
          );
          await tester.pumpAndSettle();

          expect(find.byType(OnboardingScreen), findsNothing);
          expect(find.byType(LoginScreen), findsNothing);
          expect(find.byType(SignUpScreen), findsNothing);
          expect(find.byType(MainShell), findsOneWidget);
          expect(find.textContaining('Olá, Aluno Voltar!'), findsOneWidget);
        }

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'voltar numa aba diferente de Início troca para Início dentro do '
      'app, em vez de deixar o voltar do navegador tentar sair da sessão',
      (WidgetTester tester) async {
        await signUpAndReachMainShell(tester);

        await tester.tap(find.text('Perfil'));
        await tester.pumpAndSettle();
        expect(find.text('aluno.voltar@estudo.com'), findsOneWidget);

        final navigator = Navigator.of(
          tester.element(find.byType(MainShell)),
        );
        // maybePop() retorna true tanto quando uma rota é removida quanto
        // quando um PopScope intercepta o pop (RoutePopDisposition.doNotPop)
        // — o que importa aqui é que a ROTA do MainShell continua lá (não
        // saiu da sessão) e a aba voltou para Início.
        await navigator.maybePop();
        await tester.pumpAndSettle();

        expect(find.byType(MainShell), findsOneWidget);
        expect(find.text('aluno.voltar@estudo.com'), findsNothing);
        expect(find.textContaining('Olá, Aluno Voltar!'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  });

  group('persistência da sessão ativa entre reaberturas do app (AJUSTE 3 '
      '- sessão)', () {
    testWidgets(
      'sessão ativa sobrevive a "reabrir o app" (trocar de app/recarregar '
      'a página): abre direto na Home, sem pedir login de novo',
      (WidgetTester tester) async {
        await LocalStore.signUp(
          name: 'Aluno Sessão',
          email: 'aluno.sessao@estudo.com',
          password: 'senha123',
        );

        // Simula um "reabrir o app" (nova aba/recarregar a página): os
        // ValueNotifiers globais voltam ao estado inicial, exatamente como
        // aconteceria com uma recarga de verdade — só a sessão em
        // `sessionStorage` (aqui, o stub em memória) sobrevive.
        currentAccount.value = null;
        currentProgress.value = const UserProgress();

        await restoreActiveSession();
        await tester.pumpWidget(const EstudoEmFocoApp());
        await tester.pumpAndSettle();

        expect(find.byType(MainShell), findsOneWidget);
        expect(find.byType(OnboardingScreen), findsNothing);
        expect(find.byType(LoginScreen), findsNothing);
        expect(find.textContaining('Olá, Aluno Sessão!'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'depois de Sair, reabrir o app NÃO restaura a sessão — mostra '
      'onboarding com o último e-mail lembrado e a senha vazia',
      (WidgetTester tester) async {
        await LocalStore.signUp(
          name: 'Aluno Sessão',
          email: 'aluno.sessao@estudo.com',
          password: 'senha123',
        );
        await LocalStore.logout();

        currentAccount.value = null;
        currentProgress.value = const UserProgress();

        await restoreActiveSession();
        await tester.pumpWidget(const EstudoEmFocoApp());
        await tester.pumpAndSettle();

        expect(find.byType(MainShell), findsNothing);
        expect(find.byType(OnboardingScreen), findsOneWidget);

        await tester.ensureVisible(find.text('Já tenho uma conta'));
        await tester.tap(find.text('Já tenho uma conta'));
        await tester.pumpAndSettle();

        final loginFields = find.byType(TextFormField);
        expect(
          tester.widget<TextFormField>(loginFields.at(0)).controller?.text,
          'aluno.sessao@estudo.com',
        );
        expect(
          tester.widget<TextFormField>(loginFields.at(1)).controller?.text,
          isEmpty,
        );

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    test(
      'sessão residual apontando para uma conta que não existe mais '
      '(dados limpos) não é restaurada',
      () async {
        await LocalStore.signUp(
          name: 'Aluno Removido',
          email: 'removido@estudo.com',
          password: '123456',
        );

        await LocalStore.clearAllTestData();

        final restored = await LocalStore.restoreSession();
        expect(restored, isNull);
      },
    );

    test(
      'LocalStore.restoreSession() devolve a conta certa depois de '
      'signUp/login e null depois de logout',
      () async {
        expect(await LocalStore.restoreSession(), isNull);

        final account = await LocalStore.signUp(
          name: 'Aluno Unit',
          email: 'aluno.unit@estudo.com',
          password: 'senha123',
        );
        final restored = await LocalStore.restoreSession();
        expect(restored?.email, account.email);

        await LocalStore.logout();
        expect(await LocalStore.restoreSession(), isNull);
      },
    );
  });

  group('navegação do voltar no fluxo de quiz (upload + quiz + feedback)', () {
    const transdutores =
        'Esta aula aborda os sistemas de medição, os transdutores, sensores '
        'e atuadores. Os sensores convertem grandezas físicas, como '
        'temperatura, pressão e movimento, em sinais elétricos. Os '
        'atuadores transformam sinais elétricos em outras grandezas '
        'físicas, como movimento.';

    Future<void> answerCurrentQuestionAndAdvance(WidgetTester tester) async {
      // Restrito ao próprio QuizScreen (o IndexedStack do shell mantém as
      // outras abas montadas, só escondidas) e pulando os 2 primeiros
      // InkWells do cabeçalho (seta de voltar e favoritar, sempre
      // presentes ANTES das alternativas na árvore) — tocar a seta de
      // voltar aqui testaria o botão interno do app, não uma alternativa.
      final firstOption = find
          .descendant(
            of: find.byType(QuizScreen),
            matching: find.byType(InkWell),
          )
          .at(2);
      await tester.ensureVisible(firstOption);
      await tester.tap(firstOption);
      await tester.pumpAndSettle();
      final resultButton = find.text('Ver resultado');
      if (tester.any(resultButton)) {
        await tester.ensureVisible(resultButton);
        await tester.tap(resultButton);
      } else {
        final nextButton = find.text('Próxima pergunta');
        await tester.ensureVisible(nextButton);
        await tester.tap(nextButton);
      }
      await tester.pumpAndSettle();
    }

    testWidgets(
      'terminar um quiz (aberto a partir de um material com resumo, como '
      'depois de um upload de PDF) chega no Feedback com o shell já em '
      'Início por baixo; voltar uma vez sai do Feedback pra Início, e '
      'voltar várias vezes depois disso nunca cai em login/onboarding',
      (WidgetTester tester) async {
        // Viewport bem mais alto que o padrão de teste (800x600): a tela
        // do quiz tem cabeçalho + pergunta + 4 alternativas + dica + botão,
        // que não cabe em 600px de altura — sem isso, o botão "Próxima
        // pergunta"/"Ver resultado" fica fora da área testável mesmo com
        // ensureVisible (por causa das camadas de Ink/Semantics em volta).
        tester.view.physicalSize = const Size(800, 2000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        // Cria a conta e já salva o material (simulando o resultado de um
        // upload de PDF já processado) ANTES do MainShell existir: a aba
        // Quiz (QuizScreen dentro do IndexedStack do shell) resolve o
        // material mais recente uma única vez, no seu próprio initState —
        // se o shell já tivesse montado antes de o material existir, essa
        // resolução ficaria presa num quiz vazio.
        final account = await LocalStore.signUp(
          name: 'Aluno Quiz',
          email: 'aluno.quiz@estudo.com',
          password: 'senha123',
        );
        await LocalStore.saveMaterials(account.email, [
          StudyMaterial(
            id: 'material-quiz-1',
            fileName: 'aula-transdutores.pdf',
            userSummary: transdutores,
            // "Já processado" (como depois que o app libera o quiz de
            // verdade): extractionStatus/summaryStatus pending renderiam
            // um CircularProgressIndicator indeterminado em Estudos (que
            // fica sempre montado no IndexedStack do shell) e travariam
            // qualquer pumpAndSettle deste teste para sempre.
            extractedText: transdutores,
            extractionStatus: PdfExtractionStatus.success,
            generatedSummary: transdutores,
            summaryStatus: SummaryStatus.success,
          ),
        ]);
        currentAccount.value = account;
        currentProgress.value = await LocalStore.loadProgress(account.email);
        mainShellTabIndex.value = 0;

        await tester.pumpWidget(const MaterialApp(home: MainShell()));
        await tester.pumpAndSettle();

        expect(find.byType(MainShell), findsOneWidget);

        // Abre a aba Quiz pelo shell (não empilha nada além do próprio
        // shell até aqui) e responde as 3 perguntas até o Feedback. Usa o
        // destino da NavigationBar especificamente, já que "Quiz" também
        // aparece no atalho da Home.
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text('Quiz'),
          ),
        );
        await tester.pumpAndSettle();
        for (var i = 0; i < 3; i++) {
          await answerCurrentQuestionAndAdvance(tester);
        }

        expect(find.byType(PerformanceScreen), findsOneWidget);
        expect(
          mainShellTabIndex.value,
          0,
          reason:
              'o shell por baixo do Feedback já deve estar em Início, para '
              'que voltar não caia na aba onde o quiz foi aberto',
        );

        // Voltar uma vez a partir do Feedback: sai do Feedback (pop normal
        // de uma rota empilhada sobre o shell) e cai em Início, nunca em
        // login/onboarding.
        final performanceContext = tester.element(
          find.byType(PerformanceScreen),
        );
        await Navigator.of(performanceContext).maybePop();
        await tester.pumpAndSettle();

        expect(find.byType(PerformanceScreen), findsNothing);
        expect(find.byType(MainShell), findsOneWidget);
        expect(find.byType(OnboardingScreen), findsNothing);
        expect(find.byType(LoginScreen), findsNothing);
        expect(find.textContaining('Olá, Aluno Quiz!'), findsOneWidget);

        // Voltar várias vezes a partir daqui (já em Início, sem mais
        // rotas empilhadas): o shell autenticado intercepta TODO pop
        // (PopScope com canPop sempre false), então isso nunca deve
        // vazar pro histórico do navegador de antes do login.
        for (var i = 0; i < 4; i++) {
          final shellContext = tester.element(find.byType(MainShell));
          await Navigator.of(shellContext).maybePop();
          await tester.pumpAndSettle();
        }

        expect(find.byType(MainShell), findsOneWidget);
        expect(find.byType(OnboardingScreen), findsNothing);
        expect(find.byType(LoginScreen), findsNothing);
        expect(find.textContaining('Olá, Aluno Quiz!'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  });

  group('orientação do quiz quando não há PDF carregado (AJUSTE 5)', () {
    testWidgets(
      'sem nenhum material carregado, mostra título/explicação/botão de '
      'orientação (não a mensagem técnica antiga) e o botão leva para '
      'Material de estudo',
      (WidgetTester tester) async {
        final account = await LocalStore.signUp(
          name: 'Aluno Sem PDF',
          email: 'aluno.sempdf@estudo.com',
          password: 'senha123',
        );
        currentAccount.value = account;
        currentProgress.value = await LocalStore.loadProgress(account.email);
        mainShellTabIndex.value = 0;

        await tester.pumpWidget(const MaterialApp(home: MainShell()));
        await tester.pumpAndSettle();

        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text('Quiz'),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Primeiro carregue um PDF'), findsOneWidget);
        expect(
          find.text(
            'Para criar um quiz, envie um material de estudo em PDF. '
            'Depois disso, o app vai gerar perguntas com base no '
            'conteúdo do arquivo.',
          ),
          findsOneWidget,
        );
        expect(find.text('Carregar PDF agora'), findsOneWidget);
        // Passo a passo em 3 etapas.
        expect(find.text('Carregue seu PDF'), findsOneWidget);
        expect(find.text('Aguarde o resumo'), findsOneWidget);
        expect(find.text('Responda o quiz'), findsOneWidget);
        // Nunca a mensagem técnica antiga.
        expect(find.textContaining('Nenhum material carregado'), findsNothing);

        await tester.ensureVisible(find.text('Carregar PDF agora'));
        await tester.tap(find.text('Carregar PDF agora'));
        await tester.pumpAndSettle();

        expect(mainShellTabIndex.value, 1);
        expect(find.byType(MaterialStudyPage), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'depois de carregar um PDF com resumo, a aba Quiz volta a gerar o '
      'quiz normalmente (não fica presa na orientação de "sem PDF")',
      (WidgetTester tester) async {
        const transdutores =
            'Esta aula aborda os sistemas de medição, os transdutores, '
            'sensores e atuadores. Os sensores convertem grandezas '
            'físicas, como temperatura, pressão e movimento, em sinais '
            'elétricos.';
        final account = await LocalStore.signUp(
          name: 'Aluno Com PDF',
          email: 'aluno.compdf@estudo.com',
          password: 'senha123',
        );
        await LocalStore.saveMaterials(account.email, [
          StudyMaterial(
            id: 'material-com-pdf-1',
            fileName: 'aula-transdutores.pdf',
            userSummary: transdutores,
            extractedText: transdutores,
            extractionStatus: PdfExtractionStatus.success,
            generatedSummary: transdutores,
            summaryStatus: SummaryStatus.success,
          ),
        ]);
        currentAccount.value = account;
        currentProgress.value = await LocalStore.loadProgress(account.email);
        mainShellTabIndex.value = 0;

        await tester.pumpWidget(const MaterialApp(home: MainShell()));
        await tester.pumpAndSettle();

        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text('Quiz'),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Primeiro carregue um PDF'), findsNothing);
        expect(find.text('Pergunta 1 de 3'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  });

  group('zoom button enablement (Leitura do material)', () {
    test('"-" disabled while the viewer is not ready yet', () {
      expect(
        canZoomOutFor(ready: false, zoom: 2.73, minScale: 0.1),
        isFalse,
      );
    });

    test('"-" disabled exactly at the minimum zoom', () {
      expect(
        canZoomOutFor(ready: true, zoom: 1.0, minScale: 1.0),
        isFalse,
      );
    });

    test('"-" disabled within the floating-point tolerance of the minimum', () {
      expect(
        canZoomOutFor(ready: true, zoom: 1.005, minScale: 1.0),
        isFalse,
      );
    });

    test('"-" enabled when zoom is clearly above the minimum', () {
      expect(
        canZoomOutFor(ready: true, zoom: 2.73, minScale: 0.1),
        isTrue,
      );
    });

    test('"+" disabled while the viewer is not ready yet', () {
      expect(canZoomInFor(ready: false, zoom: 2.73, maxScale: 8.0), isFalse);
    });

    test('"+" disabled exactly at the maximum zoom', () {
      expect(canZoomInFor(ready: true, zoom: 8.0, maxScale: 8.0), isFalse);
    });

    test('"+" enabled when zoom is clearly below the maximum', () {
      expect(canZoomInFor(ready: true, zoom: 2.73, maxScale: 8.0), isTrue);
    });
  });

  group('annotation page-fraction coordinates (Leitura do material)', () {
    // Simula o Matrix4 do PdfViewerController como um simples afim
    // escala+deslocamento (zoom e pan), sem depender do pdfrx de verdade —
    // o que basta para provar a matemática da conversão.
    Offset Function(Offset) makeLocalToDocument({
      double zoom = 1,
      Offset pan = Offset.zero,
    }) => (local) => (local - pan) / zoom;
    Offset Function(Offset) makeDocumentToLocal({
      double zoom = 1,
      Offset pan = Offset.zero,
    }) => (doc) => doc * zoom + pan;

    test('round-trips to the same local point when nothing changes', () {
      const pageRect = Rect.fromLTWH(100, 500, 800, 1200);
      const local = Offset(150, 550);
      final localToDocument = makeLocalToDocument();
      final documentToLocal = makeDocumentToLocal();

      final fraction = localToPageFraction(
        local: local,
        localToDocument: localToDocument,
        pageRectInDocument: pageRect,
      );
      final roundTripped = pageFractionToLocal(
        fraction: fraction,
        documentToLocal: documentToLocal,
        pageRectInDocument: pageRect,
      );

      expect(roundTripped.dx, closeTo(local.dx, 0.001));
      expect(roundTripped.dy, closeTo(local.dy, 0.001));
    });

    test('marcação acompanha a página quando ela rola (scroll)', () {
      const pageRect = Rect.fromLTWH(0, 0, 400, 800);
      const markedAt = Offset(150, 550);

      // Antes de rolar: sem deslocamento.
      final fraction = localToPageFraction(
        local: markedAt,
        localToDocument: makeLocalToDocument(),
        pageRectInDocument: pageRect,
      );

      // Depois de rolar 300px para baixo: o conteúdo sobe 300px na tela.
      final afterScroll = pageFractionToLocal(
        fraction: fraction,
        documentToLocal: makeDocumentToLocal(pan: const Offset(0, -300)),
        pageRectInDocument: pageRect,
      );

      // A marcação deve ter subido junto, não ficado parada na tela.
      expect(afterScroll.dx, closeTo(markedAt.dx, 0.001));
      expect(afterScroll.dy, closeTo(markedAt.dy - 300, 0.001));
    });

    test('marcação mantém proporção correta quando o zoom muda', () {
      const pageRect = Rect.fromLTWH(0, 0, 400, 800);
      const markedAt = Offset(100, 200);

      final fraction = localToPageFraction(
        local: markedAt,
        localToDocument: makeLocalToDocument(),
        pageRectInDocument: pageRect,
      );
      expect(fraction.dx, closeTo(0.25, 0.001));
      expect(fraction.dy, closeTo(0.25, 0.001));

      // Zoom dobrou (2x), sem pan: a marcação deve aparecer no dobro da
      // distância da borda da página, não na mesma posição de tela de antes.
      final afterZoom = pageFractionToLocal(
        fraction: fraction,
        documentToLocal: makeDocumentToLocal(zoom: 2),
        pageRectInDocument: pageRect,
      );

      expect(afterZoom.dx, closeTo(markedAt.dx * 2, 0.001));
      expect(afterZoom.dy, closeTo(markedAt.dy * 2, 0.001));
    });

    test('a mesma fração em páginas de tamanhos diferentes cai em pontos '
        'diferentes da tela (a marcação fica na página certa)', () {
      const page2Rect = Rect.fromLTWH(0, 0, 400, 800);
      const page3Rect = Rect.fromLTWH(0, 900, 400, 600);
      const fraction = Offset(0.5, 0.5);
      final documentToLocal = makeDocumentToLocal();

      final onPage2 = pageFractionToLocal(
        fraction: fraction,
        documentToLocal: documentToLocal,
        pageRectInDocument: page2Rect,
      );
      final onPage3 = pageFractionToLocal(
        fraction: fraction,
        documentToLocal: documentToLocal,
        pageRectInDocument: page3Rect,
      );

      expect(onPage2, isNot(equals(onPage3)));
      expect(onPage2, const Offset(200, 400));
      expect(onPage3, const Offset(200, 1200));
    });
  });

  group('quiz generation from PDF text (generateQuizFromText)', () {
    const materialA =
        'Fotossíntese é o processo pelo qual as plantas convertem luz solar '
        'em energia química. A fotossíntese ocorre principalmente nas '
        'folhas, dentro de estruturas chamadas cloroplastos. Durante a '
        'fotossíntese, a planta absorve dióxido de carbono e água, liberando '
        'oxigênio como subproduto. A clorofila é o pigmento responsável por '
        'capturar a luz solar necessária para a fotossíntese acontecer.';

    const materialB =
        'A Revolução Industrial transformou a economia mundial a partir do '
        'século dezoito. A Revolução Industrial começou na Inglaterra, com '
        'a introdução de máquinas a vapor nas fábricas têxteis. Antes da '
        'Revolução Industrial, a produção era majoritariamente artesanal e '
        'manual. As cidades cresceram rapidamente durante a Revolução '
        'Industrial, atraindo trabalhadores do campo.';

    test(
      'devolve lista vazia quando o texto não tem termos nem frases '
      'utilizáveis (PDF sem texto selecionável)',
      () {
        expect(
          generateQuizFromText(text: '', materialTitle: 'Vazio'),
          isEmpty,
        );
        expect(
          generateQuizFromText(text: '   ', materialTitle: 'Vazio'),
          isEmpty,
        );
      },
    );

    test('extrai termos recorrentes ignorando conectores comuns', () {
      final terms = extractKeyTerms(materialA);
      expect(terms, contains('fotossíntese'));
      expect(terms, isNot(contains('para')));
      expect(terms, isNot(contains('como')));
    });

    test(
      'gera exatamente 3 perguntas, cada uma com 4 alternativas e a '
      'resposta certa presente nas opções',
      () {
        final questions = generateQuizFromText(
          text: materialA,
          materialTitle: 'Fotossíntese - Aula 1',
        );
        expect(questions.length, 3);
        for (final q in questions) {
          expect(q.options.length, 4);
          expect(q.correct, inInclusiveRange(0, 3));
          expect(q.options[q.correct], isNotEmpty);
          expect(q.category, 'Fotossíntese - Aula 1');
        }
      },
    );

    test(
      'o quiz de um material reflete o conteúdo dele, não um tema fixo de '
      'inclusão digital',
      () {
        final questions = generateQuizFromText(
          text: materialA,
          materialTitle: 'Fotossíntese - Aula 1',
        );
        final allText = questions
            .map((q) => '${q.question} ${q.options.join(' ')}')
            .join(' ')
            .toLowerCase();
        expect(allText, isNot(contains('inclusão digital')));
      },
    );

    test(
      'dois PDFs com conteúdos diferentes geram quizzes diferentes '
      '(associados ao material carregado, não um quiz fixo)',
      () {
        final questionsA = generateQuizFromText(
          text: materialA,
          materialTitle: 'Aula 1',
        );
        final questionsB = generateQuizFromText(
          text: materialB,
          materialTitle: 'Aula 2',
        );
        expect(questionsA.first.question, isNot(questionsB.first.question));
        expect(
          questionsA.map((q) => q.category),
          everyElement('Aula 1'),
        );
        expect(
          questionsB.map((q) => q.category),
          everyElement('Aula 2'),
        );
      },
    );
  });

  group('detecção do tema do material a partir do nome do arquivo '
      '(detectMaterialTheme)', () {
    test(
      'mantém o nome completo do arquivo quando não há tema real além de '
      '"Aula N"',
      () {
        expect(detectMaterialTheme('AULA 1.pdf'), 'AULA 1.pdf');
        expect(detectMaterialTheme('Aula 2.pdf'), 'Aula 2.pdf');
      },
    );

    test('identifica o tema quando o nome do arquivo traz mais que "Aula N"', () {
      expect(
        detectMaterialTheme('Instrumentação Eletrônica.pdf'),
        'Instrumentação Eletrônica',
      );
      expect(
        detectMaterialTheme('Aula 3 - Estrutura de Dados.pdf'),
        'Estrutura de Dados',
      );
    });
  });

  group('quiz gerado a partir do texto base digitado pelo usuário '
      '(resumo/"texto base")', () {
    const transdutores =
        'Esta aula aborda os sistemas de medição, os transdutores, sensores '
        'e atuadores. Os sensores convertem grandezas físicas, como '
        'temperatura, pressão e movimento, em sinais elétricos. Os '
        'atuadores transformam sinais elétricos em outras grandezas '
        'físicas, como movimento.';

    test(
      'gera perguntas sobre o conteúdo do texto base (transdutores/'
      'sensores/atuadores), não sobre técnicas de estudo',
      () {
        final questions = generateQuizFromText(
          text: transdutores,
          materialTitle: 'Instrumentação Eletrônica',
        );
        expect(questions.length, 3);
        final allText = questions
            .map((q) => '${q.question} ${q.options.join(' ')}')
            .join(' ')
            .toLowerCase();
        // Deve conter pelo menos um dos conceitos reais do texto base.
        expect(
          allText.contains('sensor') ||
              allText.contains('atuador') ||
              allText.contains('transdutor') ||
              allText.contains('medição'),
          isTrue,
        );
        // Nunca as perguntas genéricas de técnica de estudo removidas.
        expect(allText, isNot(contains('boa prática')));
        expect(allText, isNot(contains('fixar melhor o conteúdo')));
        expect(allText, isNot(contains('objetivo de responder a este quiz')));
      },
    );

    test(
      'nunca usa alternativas evasivas genéricas que entregam a resposta '
      'certa por eliminação',
      () {
        final questions = generateQuizFromText(
          text: transdutores,
          materialTitle: 'Instrumentação Eletrônica',
        );
        final allOptions = questions.expand((q) => q.options).join(' | ');
        final lower = allOptions.toLowerCase();
        for (final banned in [
          'não é mencionado',
          'não aparece',
          'retirado de outro contexto',
          'nenhuma das alternativas',
          'todas as alternativas',
          'não se aplica',
          'não informado no texto',
        ]) {
          expect(
            lower,
            isNot(contains(banned)),
            reason: 'Alternativa evasiva "$banned" entrega a resposta certa '
                'por eliminação — nunca deveria aparecer.',
          );
        }
      },
    );

    test(
      'as 4 alternativas de cada pergunta de conceito ficam com tamanho '
      'parecido, sem a certa se destacar só pelo tamanho',
      () {
        final questions = generateQuizFromText(
          text: transdutores,
          materialTitle: 'Instrumentação Eletrônica',
        );
        for (final q in questions.where((q) => q.term.isNotEmpty)) {
          final lengths = q.options.map((o) => o.length).toList();
          final shortest = lengths.reduce((a, b) => a < b ? a : b);
          final longest = lengths.reduce((a, b) => a > b ? a : b);
          expect(
            longest,
            lessThanOrEqualTo(shortest * 3),
            reason:
                'Alternativas com tamanhos muito diferentes '
                '(${q.options}) denunciam a resposta certa só pelo '
                'formato.',
          );
        }
      },
    );

    test(
      'não usa como resposta certa uma frase onde o termo e o marcador de '
      'definição aparecem sem relação (longe demais um do outro)',
      () {
        // "medição" aparece 2x, sempre longe de um marcador de definição
        // ("são" na 1ª frase está perto de "definições", não de "medição";
        // a 2ª frase nem tem marcador). "instrumento" aparece 2x, sempre
        // PERTO de um marcador ("chamamos de instrumento"/"Instrumento é")
        // — exatamente o bug relatado testando com o PDF real: uma frase
        // não pode "explicar" um termo só por conter os dois em pontos sem
        // relação.
        const text =
            'Algumas definições são importantes antes de iniciarmos o '
            'estudo aprofundado sobre os diferentes sistemas usados para '
            'realizar medição de grandezas físicas diversas. '
            'Estudaremos ao longo deste curso vários exemplos de medição '
            'aplicados na prática industrial. '
            'Segundo Aguirre (2013), chamamos de instrumento um sistema '
            'que processa o sinal captado por um sensor. '
            'Instrumento é utilizado com frequência ao longo deste '
            'material introdutório sobre eletrônica aplicada.';

        final questions = generateQuizFromText(
          text: text,
          materialTitle: 'Teste',
        );
        final correctAnswers = questions.map((q) => q.options[q.correct]);
        expect(
          correctAnswers,
          isNot(
            contains(
              'Algumas definições são importantes antes de iniciarmos o '
              'estudo aprofundado sobre os diferentes sistemas usados para '
              'realizar medição de grandezas físicas diversas.',
            ),
          ),
        );
      },
    );

    test(
      'nunca usa uma palavra genérica isolada ("sistemas") como o '
      'conceito principal de uma pergunta, mesmo quando ela recorre e '
      'aparece perto de um marcador de definição',
      () {
        // Cenário do bug relatado testando com o PDF real: a pergunta "o
        // que caracteriza 'Sistemas'?" usava uma frase que na verdade
        // caracterizava "instrumentos" ("os instrumentos SÃO sistemas
        // dinâmicos..."), porque "sistemas" sozinho não é um conceito
        // fechado o bastante para virar pergunta. A correção não é só
        // achar a frase "certa" para "sistemas" — é nunca usar "sistemas"
        // (nem os outros termos de [kQuizBannedSoloConcepts]) como
        // conceito principal, ponto.
        const text =
            'Os instrumentos são sistemas dinâmicos e por isso variam '
            'bastante conforme o tempo total gasto no processo. '
            'Os sistemas são conjuntos organizados de componentes que '
            'atuam de forma integrada e contínua durante a operação.';

        final questions = generateQuizFromText(
          text: text,
          materialTitle: 'Teste',
        );
        expect(questions.every((q) => q.term != 'sistemas'), isTrue);
        expect(
          questions.every(
            (q) => !q.question.toLowerCase().contains('"sistemas"'),
          ),
          isTrue,
        );
      },
    );

    test(
      'lista de conceitos do quiz nunca contém uma palavra genérica '
      'isolada, mesmo que ela recorra bastante no texto',
      () {
        const text =
            'Este material aborda vários sistemas de medição. Os sistemas '
            'de medição são conjuntos organizados de sensores e '
            'atuadores. Um sistema converte grandezas físicas em sinais '
            'elétricos. Outro sistema realiza o processamento do sinal '
            'obtido antes de gerar uma saída legível ao usuário final.';

        final concepts = extractQuizConcepts(text);
        for (final banned in kQuizBannedSoloConcepts) {
          expect(
            concepts,
            isNot(contains(banned)),
            reason: '"$banned" nunca pode ser um conceito principal sozinho.',
          );
        }
        // Mas o conceito composto (que contém a palavra banida dentro
        // dele) continua permitido.
        expect(
          concepts.any((c) => c.contains('sistema')),
          isTrue,
          reason: 'Conceitos compostos como "sistema de medição" continuam '
              'permitidos mesmo contendo uma palavra banida sozinha.',
        );
      },
    );
  });

  group('limpeza do texto extraído do PDF (cleanExtractedText)', () {
    test('remove espaços e quebras de linha repetidos', () {
      const raw = 'Este   é\n\n\num   texto  de   teste.\n\n\nSegunda frase.';
      final cleaned = cleanExtractedText(raw);
      expect(cleaned, isNot(contains('  ')));
      expect(cleaned, isNot(contains('\n')));
      expect(cleaned, contains('Este é um texto de teste.'));
    });

    test('descarta linhas isoladas de 1-2 caracteres (ruído de OCR/layout)', () {
      const raw = 'a\nb\n1\nEste é o conteúdo de verdade da página, com texto '
          'suficiente para ser considerado útil.\nx\n2';
      final cleaned = cleanExtractedText(raw);
      expect(
        cleaned,
        'Este é o conteúdo de verdade da página, com texto suficiente '
        'para ser considerado útil.',
      );
    });

    test('texto vazio ou só com ruído vira string vazia', () {
      expect(cleanExtractedText(''), isEmpty);
      expect(cleanExtractedText('a\nb\n1\n2'), isEmpty);
    });
  });

  group('PdfTextExtractorService: mensagens específicas por causa de falha', () {
    test(
      'bytes vazios falha imediatamente com mensagem específica de upload, '
      'sem tentar abrir o PDF',
      () async {
        final result = await PdfTextExtractorService.extract(Uint8List(0));
        expect(result.status, PdfExtractionStatus.failed);
        expect(result.text, isEmpty);
        expect(result.message, contains('Bytes vazios'));
        expect(result.totalPages, 0);
      },
    );

    test(
      'bytes que não são um PDF de verdade falham com mensagem específica '
      'de "erro ao abrir o PDF", não a mensagem genérica de texto '
      'insuficiente',
      () async {
        final garbage = Uint8List.fromList(
          List.generate(50, (i) => i % 256),
        );
        final result = await PdfTextExtractorService.extract(garbage);
        expect(result.status, PdfExtractionStatus.failed);
        expect(result.text, isEmpty);
        expect(result.message, contains('Erro ao abrir o PDF'));
      },
    );
  });

  group('StudyMaterial: persistência do resultado da extração', () {
    test(
      'toJson/fromJson preserva extractedText, extractionStatus, '
      'extractionMessage e userSummary',
      () {
        final material = StudyMaterial(
          id: '1',
          fileName: 'AULA 1.pdf',
          pageCount: 5,
          extractedText: 'Texto extraído de verdade do PDF.',
          extractionStatus: PdfExtractionStatus.success,
          userSummary: 'Resumo digitado pelo usuário.',
        );
        final restored = StudyMaterial.fromJson(material.toJson());
        expect(restored.extractedText, material.extractedText);
        expect(restored.extractionStatus, PdfExtractionStatus.success);
        expect(restored.userSummary, material.userSummary);
      },
    );

    test(
      'materiais novos (nunca processados) começam como "pending", nunca '
      'como se já tivessem texto',
      () {
        final material = StudyMaterial(id: '2', fileName: 'AULA 2.pdf');
        expect(material.extractionStatus, PdfExtractionStatus.pending);
        expect(material.extractedText, isEmpty);
      },
    );

    test(
      'extractionMessage explica a falha quando extractionStatus é failed',
      () {
        final material = StudyMaterial(
          id: '3',
          fileName: 'AULA 3.pdf',
          extractionStatus: PdfExtractionStatus.failed,
          extractionMessage: 'Texto insuficiente extraído deste PDF.',
        );
        final restored = StudyMaterial.fromJson(material.toJson());
        expect(restored.extractionStatus, PdfExtractionStatus.failed);
        expect(restored.extractionMessage, 'Texto insuficiente extraído deste PDF.');
      },
    );

    test(
      'toJson/fromJson preserva generatedSummary, summaryStatus e '
      'summaryMessage',
      () {
        final withSummary = StudyMaterial(
          id: '4',
          fileName: 'AULA 4.pdf',
          generatedSummary: 'Resumo automático gerado a partir do PDF.',
          summaryStatus: SummaryStatus.success,
        );
        final restoredWithSummary = StudyMaterial.fromJson(
          withSummary.toJson(),
        );
        expect(
          restoredWithSummary.generatedSummary,
          withSummary.generatedSummary,
        );
        expect(restoredWithSummary.summaryStatus, SummaryStatus.success);
        expect(restoredWithSummary.summaryMessage, isNull);

        final withoutSummary = StudyMaterial(
          id: '5',
          fileName: 'AULA 5.pdf',
          summaryStatus: SummaryStatus.failed,
          summaryMessage:
              'Resumo indisponível: não foi possível extrair texto do PDF.',
        );
        final restoredWithoutSummary = StudyMaterial.fromJson(
          withoutSummary.toJson(),
        );
        expect(restoredWithoutSummary.summaryStatus, SummaryStatus.failed);
        expect(restoredWithoutSummary.generatedSummary, isEmpty);
        expect(
          restoredWithoutSummary.summaryMessage,
          'Resumo indisponível: não foi possível extrair texto do PDF.',
        );
      },
    );

    test(
      'materiais novos começam com summaryStatus "pending", nunca com um '
      'resumo já pronto',
      () {
        final material = StudyMaterial(id: '6', fileName: 'AULA 6.pdf');
        expect(material.summaryStatus, SummaryStatus.pending);
        expect(material.generatedSummary, isEmpty);
      },
    );
  });
}
