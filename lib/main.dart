import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:pdfrx/pdfrx.dart';
import 'app_buttons.dart';
import 'local_store.dart';
import 'pdf_text_extractor_service.dart';
import 'study_summary_generator.dart';

void main() {
  // Captura qualquer exceção do framework ou da plataforma (ex.: uma falha
  // assíncrona ao carregar o PDFium/WASM) que não seria pega por um
  // try/catch comum dentro de um único widget, registrando-a no console em
  // vez de deixar a tela travar silenciosamente.
  FlutterError.onError = (details) {
    debugPrint('FlutterError.onError: ${details.exceptionAsString()}');
    debugPrint('FlutterError stack: ${details.stack}');
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('PlatformDispatcher.onError: $error');
    debugPrint('PlatformDispatcher stack: $stack');
    return true;
  };
  runApp(const EstudoEmFocoApp());
}

final BoxDecoration kCardDecoration = BoxDecoration(
  color: AppColors.surface,
  borderRadius: BorderRadius.circular(20),
  border: Border.all(color: AppColors.border),
  boxShadow: const [
    BoxShadow(color: Color(0x0D0D2B4D), blurRadius: 18, offset: Offset(0, 7)),
  ],
);

const String kLogoAsset = 'assets/icone.png';
const String kTrophyAsset = 'assets/trofeu_feedback.png';
const String kOnboardingAsset = 'assets/tela_inicial.png';
const String kLoginAsset = 'assets/login_ilustracao.png';

/// The account currently signed in, or `null` when logged out. See
/// lib/local_store.dart for the (demo-only, local) auth implementation.
final ValueNotifier<UserAccount?> currentAccount = ValueNotifier<UserAccount?>(
  null,
);

/// Demo performance stats for [currentAccount], loaded from local storage
/// right after login/signup and updated whenever a quiz is completed.
final ValueNotifier<UserProgress> currentProgress = ValueNotifier<UserProgress>(
  const UserProgress(),
);

/// Selected bottom-nav tab of [MainShell]. Screens pushed on top of the
/// shell (e.g. Material de estudo reached from a Home shortcut) update this
/// before popping back, so "voltar" always lands on a specific tab of the
/// shell instead of relying on whatever tab happened to be active.
final ValueNotifier<int> mainShellTabIndex = ValueNotifier<int>(0);

/// Returns to the Início tab of [MainShell], popping any screen(s) pushed
/// on top of the shell along the way. Never falls through to Login/
/// Onboarding, since MainShell is always the root route once logged in.
void goToMainShellHome(BuildContext context) {
  mainShellTabIndex.value = 0;
  Navigator.of(context).popUntil((route) => route.isFirst);
}

/// Largura máxima da "moldura" que faz o app parecer um celular no Chrome
/// desktop, em vez de esticar por toda a largura da janela — a Leitura do
/// material é a única exceção (ver [MaterialReaderPage.routeName]).
const double kMobileFrameMaxWidth = 430;

/// Fundo das laterais fora da moldura mobile: neutro e visivelmente
/// diferente do fundo do app ([AppColors.background]), para não parecer
/// parte do aplicativo.
const Color kMobileFrameOuterBackground = Color(0xFFE3E7ED);

/// `true` enquanto a rota no topo da pilha de navegação é a Leitura do
/// material — atualizado pelo [_MobileFrameRouteObserver]. É assim que
/// [EstudoEmFocoApp] decide, a cada troca de tela, se deve aplicar a
/// moldura de largura mobile ou deixar a tela usar a largura real da
/// janela (só a Leitura do material precisa disso, para o layout com
/// miniaturas ao lado do PDF).
final ValueNotifier<bool> isFullBleedRouteActive = ValueNotifier<bool>(false);

/// Observa a pilha de navegação só para manter [isFullBleedRouteActive] em
/// dia — não faz mais nada.
class _MobileFrameRouteObserver extends NavigatorObserver {
  void _update(Route<dynamic>? route) {
    isFullBleedRouteActive.value =
        route?.settings.name == MaterialReaderPage.routeName;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _update(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _update(previousRoute);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _update(previousRoute);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _update(newRoute);
}

/// Centraliza o conteúdo do app numa largura de celular
/// ([kMobileFrameMaxWidth]) quando a janela é mais larga que isso (Chrome
/// desktop), deixando as laterais com um fundo neutro — em vez de esticar o
/// app pela janela inteira. Também substitui o [MediaQuery] herdado por um
/// com a largura JÁ limitada, para qualquer lógica responsiva dentro do
/// conteúdo (ex.: grids que recalculam colunas por largura) enxergar a
/// largura real disponível, não a da janela inteira. Numa tela realmente
/// estreita (celular de verdade), não muda nada: a largura efetiva já é
/// menor que o limite.
class _MobileWidthFrame extends StatelessWidget {
  final Widget child;

  const _MobileWidthFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final effectiveWidth = mediaQuery.size.width < kMobileFrameMaxWidth
        ? mediaQuery.size.width
        : kMobileFrameMaxWidth;
    return ColoredBox(
      color: kMobileFrameOuterBackground,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kMobileFrameMaxWidth),
          child: MediaQuery(
            data: mediaQuery.copyWith(
              size: Size(effectiveWidth, mediaQuery.size.height),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class EstudoEmFocoApp extends StatelessWidget {
  const EstudoEmFocoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Estudo em Foco',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme:
            ColorScheme.fromSeed(
              seedColor: AppColors.secondary,
              brightness: Brightness.light,
            ).copyWith(
              primary: AppColors.primary,
              secondary: AppColors.secondary,
              surface: AppColors.surface,
            ),
        scaffoldBackgroundColor: AppColors.background,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.primary,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: AppColors.primary,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
          iconTheme: IconThemeData(color: AppColors.primary),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.secondary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppColors.lightBlue,
            elevation: 0,
            minimumSize: const Size(0, 52),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.secondary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surface,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 17,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(
              color: AppColors.secondary,
              width: 1.6,
            ),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Colors.redAccent),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Colors.redAccent, width: 1.6),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: AppColors.surface,
          surfaceTintColor: Colors.transparent,
          indicatorColor: AppColors.lightBlue.withValues(alpha: 0.32),
          elevation: 1,
          iconTheme: WidgetStateProperty.resolveWith((states) {
            return IconThemeData(
              color: states.contains(WidgetState.selected)
                  ? AppColors.secondary
                  : AppColors.primary.withValues(alpha: 0.72),
            );
          }),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            return TextStyle(
              color: states.contains(WidgetState.selected)
                  ? AppColors.secondary
                  : AppColors.primary,
              fontSize: 12,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w600,
            );
          }),
        ),
        // fontSize explícito em cada estilo: sem isso, um TextStyle aqui só
        // com color/fontWeight é combinado (merge) com o tamanho padrão do
        // Material 3 — correto na maioria dos casos, mas deixa qualquer Text
        // sem fontSize próprio (como havia na tela do Quiz) dependendo
        // inteiramente desse merge para não renderizar enorme.
        textTheme: const TextTheme(
          titleLarge: TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.w800,
            fontSize: 22,
          ),
          titleMedium: TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
          bodyLarge: TextStyle(color: AppColors.primary, fontSize: 16),
          bodyMedium: TextStyle(color: AppColors.primary, fontSize: 14),
        ),
      ),
      navigatorObservers: [_MobileFrameRouteObserver()],
      // Centraliza todas as telas numa largura de celular no Chrome
      // desktop, exceto a Leitura do material (ver
      // [isFullBleedRouteActive]/[_MobileWidthFrame]), que precisa da
      // largura real da janela para o próprio layout responsivo dela
      // (miniaturas ao lado do PDF).
      builder: (context, child) => ValueListenableBuilder<bool>(
        valueListenable: isFullBleedRouteActive,
        builder: (context, fullBleed, navigatorChild) => fullBleed
            ? navigatorChild!
            : _MobileWidthFrame(child: navigatorChild!),
        child: child,
      ),
      home: const OnboardingScreen(),
    );
  }
}

class _PageList extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  const _PageList({
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(20, 20, 20, 28),
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(padding: padding, children: children),
          ),
        ),
      ),
    );
  }
}

/// Confina o conteúdo a uma largura de celular e centraliza na tela em
/// telas largas (tablet/desktop), evitando que a ilustração em pé seja
/// esticada/cortada por um `BoxFit.cover` num viewport muito largo.
class _PhoneFrame extends StatelessWidget {
  final Widget child;

  const _PhoneFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: child,
        ),
      ),
    );
  }
}

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _PhoneFrame(
        child: Stack(
          fit: StackFit.expand,
          children: [
            const Positioned.fill(
              child: Image(
                image: AssetImage(kOnboardingAsset),
                fit: BoxFit.cover,
              ),
            ),
            // Painel inferior com gradiente: o subtítulo "Organize seus
            // estudos..." já vem DESENHADO na própria imagem de fundo, numa
            // posição proporcional à altura da tela — em celulares mais
            // altos/estreitos que a prévia usada no design, os indicadores/
            // texto abaixo (que ficam mais altos por ficarem ancorados só
            // no fundo) acabavam caindo bem em cima desse texto da imagem,
            // parecendo um erro visual. Um gradiente que sempre acompanha o
            // tamanho real do conteúdo (em vez de uma altura fixa "no
            // olho") garante que indicadores/texto/botões sempre pousem
            // sobre um fundo sólido e legível, não importa a altura do
            // aparelho.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.background.withValues(alpha: 0),
                      AppColors.background,
                    ],
                    stops: const [0.0, 0.55],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 64, 24, 0),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _PageIndicator(selected: true),
                              _PageIndicator(),
                              _PageIndicator(),
                            ],
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'Primeiro acesso? Toque em Começar para criar '
                            'sua conta.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.mutedText,
                            ),
                          ),
                          const SizedBox(height: 12),
                          PrimaryButton(
                            label: 'Começar',
                            height: 56,
                            borderRadius: 28,
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const LoginScreen(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          SecondaryTextButton(
                            label: 'Já tenho uma conta',
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const LoginScreen(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageIndicator extends StatelessWidget {
  final bool selected;

  const _PageIndicator({this.selected = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: selected ? 10 : 8,
      height: selected ? 10 : 8,
      margin: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: selected ? AppColors.secondary : AppColors.lightBlue,
        shape: BoxShape.circle,
      ),
    );
  }
}

/// Signs [account] in: loads their demo progress, resets the shell tab to
/// Início, and replaces the whole navigation stack with [MainShell] — so
/// Login/Onboarding/Cadastro are never reachable via "voltar" afterwards.
Future<void> enterAppAfterAuth(
  BuildContext context,
  UserAccount account,
) async {
  currentAccount.value = account;
  currentProgress.value = await LocalStore.loadProgress(account.email);
  mainShellTabIndex.value = 0;
  if (!context.mounted) return;
  Navigator.pushAndRemoveUntil(
    context,
    MaterialPageRoute(builder: (_) => const MainShell()),
    (route) => false,
  );
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prefillLastEmail();
  }

  /// Pré-preenche o campo de e-mail com o último e-mail usado com sucesso
  /// em login/cadastro neste navegador (ver `LocalStore.loadLastEmail`) —
  /// nunca a senha, que continua sempre vazia. Sobrevive ao "Sair"
  /// (`LocalStore.logout` só limpa a sessão ativa, não essa lembrança).
  Future<void> _prefillLastEmail() async {
    final lastEmail = await LocalStore.loadLastEmail();
    if (!mounted || lastEmail == null || lastEmail.isEmpty) return;
    _emailController.text = lastEmail;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final account = await LocalStore.login(
        email: _emailController.text,
        password: _passwordController.text,
      );
      if (!mounted) return;
      await enterAppAfterAuth(context, account);
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.message;
      });
    } catch (e) {
      // Qualquer outra falha (ex.: armazenamento local indisponível) não
      // deve deixar o botão preso em "Carregando..." — sempre volta ao
      // estado normal e mostra um aviso. O erro real vai pro console do
      // navegador (F12) para depuração, já que isso NUNCA deveria ser
      // confundido com "e-mail já cadastrado" (esse caso é AuthException).
      debugPrint('LoginScreen: erro inesperado ao entrar: $e');
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Não foi possível entrar agora. Tente novamente.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _PhoneFrame(
        child: Stack(
          fit: StackFit.expand,
          children: [
            const Positioned.fill(
              child: Image(image: AssetImage(kLoginAsset), fit: BoxFit.cover),
            ),
            Positioned(
              left: 24,
              right: 24,
              bottom: 32,
              child: SafeArea(
                top: false,
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_error != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFE7E7),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.redAccent.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      const Text(
                        'E-mail',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Digite seu e-mail.';
                          }
                          if (!value.contains('@')) {
                            return 'Digite um e-mail válido.';
                          }
                          return null;
                        },
                        decoration: const InputDecoration(
                          hintText: 'seuemail@exemplo.com',
                          prefixIcon: Icon(
                            LucideIcons.mail,
                            color: AppColors.secondary,
                            size: 22,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Senha',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: true,
                        textInputAction: TextInputAction.done,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        onFieldSubmitted: (_) => _submit(),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Digite sua senha.';
                          }
                          return null;
                        },
                        decoration: const InputDecoration(
                          hintText: 'Digite sua senha',
                          prefixIcon: Icon(
                            LucideIcons.lock,
                            color: AppColors.secondary,
                            size: 22,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      PrimaryButton(
                        label: 'Entrar',
                        height: 56,
                        borderRadius: 20,
                        icon: LucideIcons.logIn,
                        isLoading: _submitting,
                        onPressed: _submit,
                      ),
                      const SizedBox(height: 4),
                      SecondaryTextButton(
                        label: 'Primeiro acesso? Criar conta',
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SignUpScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 16,
              left: 16,
              child: SafeArea(
                child: IconButton(
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(
                    LucideIcons.arrowLeft,
                    color: AppColors.primary,
                    size: 24,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final account = await LocalStore.signUp(
        name: _nameController.text,
        email: _emailController.text,
        password: _passwordController.text,
      );
      if (!mounted) return;
      await enterAppAfterAuth(context, account);
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.message;
      });
    } catch (e) {
      // Qualquer outra falha (ex.: armazenamento local indisponível) não
      // deve deixar o botão preso em "Carregando..." — sempre volta ao
      // estado normal e mostra um aviso. O erro real vai pro console do
      // navegador (F12) para depuração, já que isso NUNCA deveria ser
      // confundido com "e-mail já cadastrado" (esse caso é AuthException).
      debugPrint('SignUpScreen: erro inesperado ao cadastrar: $e');
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Não foi possível criar sua conta agora. Tente novamente.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.maybePop(context),
                          icon: const Icon(
                            LucideIcons.arrowLeft,
                            color: AppColors.primary,
                            size: 24,
                          ),
                        ),
                      ],
                    ),
                    Image.asset(kLogoAsset, width: 72, height: 72),
                    const SizedBox(height: 8),
                    const Text(
                      'Criar conta de estudante',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (_error != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFE7E7),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.redAccent.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    const Text(
                      'Nome',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Digite seu nome.';
                        }
                        return null;
                      },
                      decoration: const InputDecoration(
                        hintText: 'Digite seu nome',
                        prefixIcon: Icon(
                          LucideIcons.user,
                          color: AppColors.secondary,
                          size: 22,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'E-mail',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Digite seu e-mail.';
                        }
                        if (!value.contains('@')) {
                          return 'Digite um e-mail válido.';
                        }
                        return null;
                      },
                      decoration: const InputDecoration(
                        hintText: 'seuemail@exemplo.com',
                        prefixIcon: Icon(
                          LucideIcons.mail,
                          color: AppColors.secondary,
                          size: 22,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Senha',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      onFieldSubmitted: (_) => _submit(),
                      validator: (value) {
                        if (value == null || value.length < 4) {
                          return 'Use pelo menos 4 caracteres.';
                        }
                        return null;
                      },
                      decoration: const InputDecoration(
                        hintText: 'Crie uma senha',
                        prefixIcon: Icon(
                          LucideIcons.lock,
                          color: AppColors.secondary,
                          size: 22,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    PrimaryButton(
                      label: 'Cadastrar',
                      height: 56,
                      borderRadius: 20,
                      icon: LucideIcons.userPlus,
                      isLoading: _submitting,
                      onPressed: _submit,
                    ),
                    const SizedBox(height: 4),
                    SecondaryTextButton(
                      label: 'Já tenho conta',
                      onPressed: () => Navigator.maybePop(context),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _selectedIndex = mainShellTabIndex.value;
    mainShellTabIndex.addListener(_onTabRequested);
  }

  @override
  void dispose() {
    mainShellTabIndex.removeListener(_onTabRequested);
    super.dispose();
  }

  void _onTabRequested() {
    if (mounted) setState(() => _selectedIndex = mainShellTabIndex.value);
  }

  void _selectTab(int index) {
    mainShellTabIndex.value = index;
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    if (currentAccount.value == null) {
      return const LoginScreen();
    }

    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: const [
          HomePage(),
          MaterialStudyPage(),
          QuizScreen(),
          ProfilePage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _selectTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(LucideIcons.house),
            selectedIcon: Icon(LucideIcons.house),
            label: 'Início',
          ),
          NavigationDestination(
            icon: Icon(LucideIcons.folder),
            selectedIcon: Icon(LucideIcons.folder),
            label: 'Estudos',
          ),
          NavigationDestination(
            icon: Icon(LucideIcons.listChecks),
            selectedIcon: Icon(LucideIcons.listChecks),
            label: 'Quiz',
          ),
          NavigationDestination(
            icon: Icon(LucideIcons.user),
            selectedIcon: Icon(LucideIcons.user),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return _PageList(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ValueListenableBuilder<UserAccount?>(
                valueListenable: currentAccount,
                builder: (context, account, _) {
                  final displayName = account == null || account.name.isEmpty
                      ? 'estudante'
                      : account.name;
                  return Text(
                    'Olá, $displayName! 👋',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  );
                },
              ),
            ),
            IconButton(
              onPressed: () {},
              icon: const Icon(LucideIcons.bell, color: AppColors.primary),
            ),
          ],
        ),
        const SizedBox(height: 14),

        ValueListenableBuilder<UserProgress>(
          valueListenable: currentProgress,
          builder: (context, progress, _) {
            return _ProgressCard(
              percent: progress.percent,
              quizzes: progress.quizzesCompleted,
              acertos: progress.acertosTotal,
              sequencia: progress.sequenciaDias,
            );
          },
        ),

        const SizedBox(height: 20),
        const Text(
          'O que você quer fazer hoje?',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 12),

        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          // <=, não <: com a moldura de largura mobile (ver
          // _MobileWidthFrame), a largura relatada por MediaQuery numa tela
          // larga é EXATAMENTE 430 (o limite), não um pouco menos — usar
          // "<" deixava esse caso cair no ramo "desktop" (proporção mais
          // baixa/larga), sem altura suficiente para o ícone + título +
          // legenda do card, causando overflow.
          childAspectRatio: MediaQuery.sizeOf(context).width <= 430
              ? 0.56
              : 0.68,
          children: [
            ShortcutCard(
              title: 'PDFs',
              subtitle: 'Seus materiais',
              icon: LucideIcons.fileText,
              onTap: () => mainShellTabIndex.value = 1,
            ),
            ShortcutCard(
              title: 'Quiz',
              subtitle: 'Testes e exercícios',
              icon: LucideIcons.listChecks,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const QuizScreen()),
              ),
            ),
            ShortcutCard(
              title: 'Feedback',
              subtitle: 'Avalie seus estudos',
              icon: LucideIcons.messageSquare,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PerformanceScreen(
                    acertos: 3,
                    erros: 1,
                    feedback: 'Continue revisando.',
                  ),
                ),
              ),
            ),
            ShortcutCard(
              title: 'Desempenho',
              subtitle: 'Acompanhe seu progresso',
              icon: LucideIcons.trendingUp,
              backgroundColor: AppColors.accent,
              iconColor: AppColors.primary,
              textColor: AppColors.primary,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PerformanceScreen(
                    acertos: 3,
                    erros: 1,
                    feedback: 'Bom progresso.',
                  ),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Color(0x120D2B4D),
                blurRadius: 12,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.secondary.withAlpha(31),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  LucideIcons.target,
                  color: AppColors.secondary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Meta da semana',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Conclua 3 quizzes até domingo',
                      style: TextStyle(fontSize: 14, color: Color(0xFF475569)),
                    ),
                  ],
                ),
              ),
              const Text(
                '2/3',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Container(
          height: 8,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: 0.65,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.secondary,
                borderRadius: BorderRadius.horizontal(
                  right: Radius.circular(12),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProgressCard extends StatelessWidget {
  final int percent;
  final int quizzes;
  final int acertos;
  final int sequencia;

  const _ProgressCard({
    required this.percent,
    required this.quizzes,
    required this.acertos,
    required this.sequencia,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: kCardDecoration,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Seu progresso',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PerformanceScreen(
                      acertos: acertos,
                      erros: quizzes - acertos > 0 ? quizzes - acertos : 0,
                      feedback:
                          'Continue praticando para manter sua sequência.',
                    ),
                  ),
                ),
                child: const Text(
                  'Ver tudo',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.secondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              SizedBox(
                width: 76,
                height: 76,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 76,
                      height: 76,
                      child: CircularProgressIndicator(
                        value: percent / 100,
                        strokeWidth: 7,
                        backgroundColor: const Color(0xFFE2E8F0),
                        valueColor: const AlwaysStoppedAnimation(
                          AppColors.secondary,
                        ),
                      ),
                    ),
                    Text(
                      '$percent%',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ótimo trabalho!',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Continue assim.',
                      style: TextStyle(fontSize: 14, color: Color(0xFF475569)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: percent / 100,
              minHeight: 7,
              backgroundColor: const Color(0xFFE8EEF6),
              valueColor: const AlwaysStoppedAnimation(AppColors.secondary),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _ProgressStat(value: '$quizzes', label: 'Quizzes'),
              ),
              const _StatDivider(),
              Expanded(
                child: _ProgressStat(value: '$acertos', label: 'Acertos'),
              ),
              const _StatDivider(),
              Expanded(
                child: _ProgressStat(
                  value: '$sequencia 🔥',
                  label: 'Sequência',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProgressStat extends StatelessWidget {
  final String value;
  final String label;
  const _ProgressStat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
      ],
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 32, color: const Color(0xFFE2E8F0));
  }
}

class MaterialStudyPage extends StatefulWidget {
  const MaterialStudyPage({super.key});

  @override
  State<MaterialStudyPage> createState() => _MaterialStudyPageState();
}

class _MaterialStudyPageState extends State<MaterialStudyPage> {
  List<StudyMaterial> _materials = [];

  String? get _email => currentAccount.value?.email;

  @override
  void initState() {
    super.initState();
    _loadMaterials();
  }

  Future<void> _loadMaterials() async {
    final email = _email;
    if (email == null) return;
    final materials = await LocalStore.loadMaterials(email);
    if (mounted) setState(() => _materials = materials);
  }

  Future<void> _persist() async {
    final email = _email;
    if (email == null) return;
    await LocalStore.saveMaterials(email, _materials);
  }

  Future<void> _pickPdf() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        debugPrint('_pickPdf: seleção cancelada pelo usuário.');
        return;
      }
      final file = result.files.single;
      debugPrint(
        '_pickPdf: arquivo selecionado "${file.name}" — '
        'file.size (relatado pelo picker) = ${file.size} bytes, '
        'file.bytes.length (bytes reais recebidos) = '
        '${file.bytes?.length ?? 0} bytes.',
      );
      final id = DateTime.now().microsecondsSinceEpoch.toString();
      setState(() {
        _materials = [
          ..._materials,
          StudyMaterial(id: id, fileName: file.name, bytes: file.bytes),
        ];
      });
      await _persist();
      final bytes = file.bytes;
      if (bytes != null && bytes.isNotEmpty) {
        // Dispara em segundo plano: a extração de texto (usada só para
        // gerar o quiz, ver [generateQuizFromText]) não pode travar o
        // upload — o material já aparece na lista antes dela terminar.
        unawaited(_extractTextInBackground(id, file.name, bytes));
      } else {
        debugPrint(
          '_pickPdf: file.bytes veio ${bytes == null ? "null" : "vazio"} '
          'para "${file.name}" — o problema está no upload em si (o '
          'seletor de arquivo não entregou os bytes), a extração nem '
          'chega a rodar.',
        );
        setState(() {
          _materials = _materials
              .map(
                (m) => m.id == id
                    ? m.copyWith(
                        extractionStatus: PdfExtractionStatus.failed,
                        extractionMessage:
                            'Arquivo não carregado corretamente: bytes '
                            '${bytes == null ? "null" : "vazios"} recebidos '
                            'do seletor de arquivo.',
                      )
                    : m,
              )
              .toList();
        });
      }
    } catch (e, stack) {
      debugPrint('_pickPdf: erro ao selecionar/ler o PDF: $e');
      debugPrint('_pickPdf stack: $stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível carregar o PDF: $e')),
        );
      }
    }
  }

  /// Extrai o texto real do PDF via [PdfTextExtractorService] (etapa 1 da
  /// "inteligência" do app) e, se a extração deu certo, gera um resumo
  /// automático a partir DESSE texto via [StudySummaryGenerator] (etapa 2)
  /// — o quiz ainda não usa nada disso, continua vindo só de
  /// [StudyMaterial.userSummary] (ver `_QuizScreenState._effectiveBaseText`,
  /// inalterado nesta etapa). Nenhum dos dois passos falha
  /// "silenciosamente": a tela de Material de estudo mostra "Sem texto
  /// extraível"/"Resumo indisponível" quando os respectivos status vierem
  /// `failed`.
  Future<void> _extractTextInBackground(
    String materialId,
    String fileName,
    Uint8List bytes,
  ) async {
    debugPrint(
      '_extractTextInBackground: iniciando para "$fileName" '
      '(materialId=$materialId, ${bytes.length} bytes) via '
      'PdfTextExtractorService.extract() — mesmo serviço usado no teste '
      'com fixture, nenhum caminho alternativo.',
    );
    final extraction = await PdfTextExtractorService.extract(
      bytes,
      sourceName: fileName,
    );
    final preview = extraction.text.isEmpty
        ? '(vazio)'
        : extraction.text.substring(
            0,
            extraction.text.length < 300 ? extraction.text.length : 300,
          );
    debugPrint(
      '_extractTextInBackground: "$fileName" (materialId=$materialId) -> '
      'status=${extraction.status.name}, '
      '${extraction.text.length} caracteres úteis, '
      'mensagem=${extraction.message ?? "(nenhuma)"}.',
    );
    debugPrint(
      '_extractTextInBackground: primeiros 300 caracteres extraídos de '
      '"$fileName":',
    );
    debugPrint(preview);

    final summary = extraction.isSuccess
        ? StudySummaryGenerator.generate(extraction.text)
        : const StudySummaryResult(
            status: SummaryStatus.failed,
            summary: '',
            message:
                'Resumo indisponível: não foi possível extrair texto do PDF.',
          );
    debugPrint(
      '_extractTextInBackground: "$materialId" -> resumo status='
      '${summary.status.name} (${summary.summary.length} caracteres).',
    );

    if (!mounted) return;
    setState(() {
      _materials = _materials
          .map(
            (m) => m.id == materialId
                ? m.copyWith(
                    extractedText: extraction.text,
                    extractionStatus: extraction.status,
                    extractionMessage: extraction.message,
                    clearExtractionMessage: extraction.message == null,
                    generatedSummary: summary.summary,
                    summaryStatus: summary.status,
                    summaryMessage: summary.message,
                    clearSummaryMessage: summary.message == null,
                  )
                : m,
          )
          .toList();
    });
    await _persist();
  }

  Future<void> _onPageCountResolved(String materialId, int pageCount) async {
    setState(() {
      _materials = _materials
          .map((m) => m.id == materialId ? m.copyWith(pageCount: pageCount) : m)
          .toList();
    });
    await _persist();
  }

  Future<void> _removeMaterial(String id) async {
    setState(() {
      _materials = _materials.where((m) => m.id != id).toList();
    });
    await _persist();
  }

  /// Abre um diálogo para o usuário digitar/editar o "texto base" (resumo)
  /// daquele material — usado para gerar o quiz quando a extração
  /// automática do PDF não estiver disponível (ver
  /// [StudyMaterial.userSummary]/`_QuizScreenState._effectiveBaseText`).
  Future<void> _editSummary(StudyMaterial material) async {
    final controller = TextEditingController(text: material.userSummary ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Texto base para gerar o quiz'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Resuma o conteúdo de "${material.fileName}" — o quiz será '
                'gerado a partir deste texto.',
                style: const TextStyle(
                  color: AppColors.mutedText,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                minLines: 4,
                maxLines: 8,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Ex.: Esta aula aborda transdutores, sensores e '
                      'atuadores, explicando como sensores convertem '
                      'grandezas físicas em sinais elétricos...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null) return;
    setState(() {
      _materials = _materials
          .map(
            (m) => m.id == material.id
                ? m.copyWith(userSummary: result.trim())
                : m,
          )
          .toList();
    });
    await _persist();
  }

  @override
  Widget build(BuildContext context) {
    final hasMaterials = _materials.isNotEmpty;
    return _PageList(
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () => goToMainShellHome(context),
              icon: const Icon(
                LucideIcons.chevronLeft,
                color: AppColors.primary,
                size: 26,
              ),
            ),
            const Expanded(
              child: Text(
                'Material de estudo',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                  color: AppColors.primary,
                ),
              ),
            ),
            IconButton(
              onPressed: () {},
              icon: const Icon(
                LucideIcons.bookmark,
                color: AppColors.secondary,
                size: 24,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _UploadMaterialCard(hasFile: hasMaterials, onPick: _pickPdf),
        if (hasMaterials) ...[
          const SizedBox(height: 22),
          const Text(
            'Materiais carregados',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 12),
          for (final material in _materials) ...[
            _MaterialListCard(
              material: material,
              onRead: () {
                debugPrint('Abrindo leitor: ${material.fileName}');
                debugPrint('PDF bytes: ${material.bytes?.length ?? 0}');
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    settings: const RouteSettings(
                      name: MaterialReaderPage.routeName,
                    ),
                    builder: (_) => MaterialReaderPage(
                      material: material,
                      onPageCountResolved: (pageCount) =>
                          _onPageCountResolved(material.id, pageCount),
                    ),
                  ),
                );
              },
              onQuiz: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => QuizScreen(material: material)),
              ),
              onEditSummary: () => _editSummary(material),
              onRemove: () => _removeMaterial(material.id),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ],
    );
  }
}

/// Desativado nesta etapa de validação da extração automática (ver
/// PdfTextExtractorService/Etapa 1): enquanto o upload real não estiver
/// confirmado extraindo texto de verdade, a UI não deve pedir/induzir um
/// resumo manual — só reativar depois que a extração automática estiver
/// validada no fluxo real do app (não só no teste com fixture).
const bool kManualSummaryUiEnabled = false;

class _MaterialListCard extends StatelessWidget {
  final StudyMaterial material;
  final VoidCallback onRead;
  final VoidCallback onQuiz;
  final VoidCallback onEditSummary;
  final VoidCallback onRemove;

  const _MaterialListCard({
    required this.material,
    required this.onRead,
    required this.onQuiz,
    required this.onEditSummary,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final hasSummary = (material.userSummary ?? '').trim().isNotEmpty;
    return Container(
      decoration: kCardDecoration,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE9F7EF),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      LucideIcons.checkCircle2,
                      size: 15,
                      color: Color(0xFF2EAD68),
                    ),
                    SizedBox(width: 5),
                    Text(
                      'PDF carregado',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF2EAD68),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: onRemove,
                tooltip: 'Remover material',
                icon: const Icon(
                  LucideIcons.trash2,
                  size: 19,
                  color: AppColors.mutedText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const _PdfBadge(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      material.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      material.pageCount != null
                          ? 'PDF  •  Carregado agora  •  ${material.pageCount} páginas'
                          : 'PDF  •  Carregado agora',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.mutedText,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildExtractionStatusRow(context),
          const SizedBox(height: 6),
          _buildSummaryStatusRow(context),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: PrimaryButton(
                  label: 'Ler material',
                  icon: LucideIcons.bookOpen,
                  height: 50,
                  onPressed: onRead,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: onQuiz,
                    icon: const Icon(LucideIcons.listChecks, size: 18),
                    label: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Responder quiz',
                        maxLines: 1,
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.secondary,
                      side: const BorderSide(color: AppColors.secondary),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          // kManualSummaryUiEnabled desligado: esta etapa valida só a
          // extração automática (ver PdfTextExtractorService) — nenhuma
          // UI deve induzir o usuário a digitar um resumo manual enquanto
          // isso não estiver confirmado funcionando no upload real.
          if (kManualSummaryUiEnabled) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: onEditSummary,
                icon: Icon(
                  hasSummary ? LucideIcons.pencil : LucideIcons.filePlus2,
                  size: 16,
                ),
                label: Text(
                  hasSummary ? 'Editar texto base' : 'Adicionar resumo',
                ),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.mutedText,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Status visual da extração automática de texto deste material (ver
  /// [PdfTextExtractorService]/[StudyMaterial.extractionStatus]) — nunca diz
  /// que "extraiu" algo que não extraiu de verdade, e nunca trata o nome do
  /// arquivo como se fosse conteúdo.
  Widget _buildExtractionStatusRow(BuildContext context) {
    switch (material.extractionStatus) {
      case PdfExtractionStatus.success:
        return InkWell(
          onTap: () => _showTextPreview(context),
          borderRadius: BorderRadius.circular(10),
          child: Row(
            children: [
              const Icon(
                LucideIcons.checkCircle2,
                size: 15,
                color: Color(0xFF2EAD68),
              ),
              const SizedBox(width: 5),
              const Text(
                'Texto extraído',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2EAD68),
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                '·  Ver prévia',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.secondary,
                  decoration: TextDecoration.underline,
                ),
              ),
            ],
          ),
        );
      case PdfExtractionStatus.failed:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              LucideIcons.triangleAlert,
              size: 15,
              color: Color(0xFFB3261E),
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Sem texto extraível',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFB3261E),
                    ),
                  ),
                  // Mostra o motivo real (ex.: "42 caracteres úteis" vs.
                  // "0 caracteres úteis", ou o erro específico de alguma
                  // página) em vez de uma frase fixa igual para qualquer
                  // causa — sem isso não dá para saber, só olhando a tela,
                  // se ALGUMA página teve texto ou nenhuma.
                  Text(
                    material.extractionMessage ??
                        'Use um PDF com texto selecionável.',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.mutedText,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      case PdfExtractionStatus.pending:
        return const Row(
          children: [
            SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.mutedText,
              ),
            ),
            SizedBox(width: 7),
            Text(
              'Extração pendente',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.mutedText,
              ),
            ),
          ],
        );
    }
  }

  void _showTextPreview(BuildContext context) {
    final text = material.extractedText;
    final preview = text.length > 200 ? '${text.substring(0, 200)}...' : text;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Prévia do texto extraído'),
        content: SingleChildScrollView(
          child: Text(
            preview,
            style: const TextStyle(color: AppColors.primary, height: 1.4),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  /// Status visual do resumo automático (ver
  /// [StudySummaryGenerator]/[StudyMaterial.summaryStatus]) — não usado
  /// pelo quiz ainda nesta etapa, só exibido aqui.
  Widget _buildSummaryStatusRow(BuildContext context) {
    switch (material.summaryStatus) {
      case SummaryStatus.success:
        return InkWell(
          onTap: () => _showSummaryDialog(context),
          borderRadius: BorderRadius.circular(10),
          child: Row(
            children: [
              const Icon(
                LucideIcons.sparkles,
                size: 15,
                color: Color(0xFF2EAD68),
              ),
              const SizedBox(width: 5),
              const Text(
                'Resumo gerado',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2EAD68),
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                '·  Ver resumo',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.secondary,
                  decoration: TextDecoration.underline,
                ),
              ),
            ],
          ),
        );
      case SummaryStatus.failed:
        return Text(
          material.summaryMessage ??
              'Resumo indisponível: não foi possível extrair texto do PDF.',
          style: const TextStyle(fontSize: 11, color: AppColors.mutedText),
        );
      case SummaryStatus.pending:
        return const Row(
          children: [
            SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.mutedText,
              ),
            ),
            SizedBox(width: 7),
            Text(
              'Resumo pendente',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.mutedText,
              ),
            ),
          ],
        );
    }
  }

  void _showSummaryDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Resumo do material'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                material.fileName,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                material.generatedSummary,
                style: const TextStyle(color: AppColors.primary, height: 1.4),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

}

class _UploadMaterialCard extends StatelessWidget {
  final bool hasFile;
  final VoidCallback onPick;

  const _UploadMaterialCard({required this.hasFile, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.lightBlue.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _RoundIcon(
            icon: LucideIcons.fileUp,
            color: AppColors.secondary,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasFile
                      ? 'Carregar novo material'
                      : 'Nenhum material carregado',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  hasFile
                      ? 'Envie outro PDF para adicionar aos seus estudos.'
                      : 'Carregue um PDF para iniciar seus estudos.',
                  style: const TextStyle(
                    color: AppColors.mutedText,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 14),
                PrimaryButton(
                  label: 'Carregar PDF',
                  icon: LucideIcons.upload,
                  height: 48,
                  onPressed: onPick,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Ferramenta ativa na tela de leitura. [hand] é a navegação normal do PDF
/// (arrastar para rolar, pinça/scroll para zoom); nos demais modos, um
/// arrasto sobre a página vira marcação ou rolagem dependendo da direção
/// (ver [_GestureIntent]) — a navegação nativa do [PdfViewer] nunca é
/// desligada.
enum _AnnotationMode { hand, highlight, pen, eraser }

/// Intenção de um arrasto em curso sobre a página, em Marca-texto/Lápis:
/// decidida pela direção predominante do deslocamento acumulado desde o
/// toque inicial (ver [_gestureIntentThreshold]). Vertical = rolagem
/// (deixa o [PdfViewer] rolar normalmente); horizontal/diagonal = anotação
/// (desenha/marca).
enum _GestureIntent { undecided, scroll, annotation }

/// Tela de leitura real de um [StudyMaterial]: renderiza o PDF de verdade
/// (via `pdfrx`) com zoom, navegação de páginas, miniaturas, busca de texto
/// e uma camada demonstrativa de anotação (marca-texto e lápis) por cima da
/// página — ver [PageAnnotation]. A anotação nunca edita o PDF original nem
/// gera um novo arquivo: é só uma camada visual desenhada com base nos
/// pontos guardados em [LocalStore.saveAnnotations].
///
/// Se [StudyMaterial.bytes] for nulo (o material foi recarregado a partir
/// dos dados persistidos, que não guardam o binário do PDF), a tela explica
/// a limitação em vez de tentar abrir um arquivo inexistente.
class MaterialReaderPage extends StatefulWidget {
  final StudyMaterial material;
  final ValueChanged<int>? onPageCountResolved;

  /// Nome de rota usado só para o [_MobileFrameRouteObserver] identificar
  /// quando a Leitura do material está no topo da pilha de navegação, e
  /// então deixar essa tela escapar da moldura de largura mobile (ver
  /// [_MobileWidthFrame]/[EstudoEmFocoApp]) — ela já tem seu próprio layout
  /// responsivo (thumbnails ao lado do PDF acima de [_wideBreakpoint]) e
  /// precisa da largura real da janela para decidir isso corretamente.
  static const String routeName = '/leitura-material';

  const MaterialReaderPage({
    required this.material,
    this.onPageCountResolved,
    super.key,
  });

  @override
  State<MaterialReaderPage> createState() => _MaterialReaderPageState();
}

class _MaterialReaderPageState extends State<MaterialReaderPage> {
  static const double _wideBreakpoint = 700;

  // Aparência do marca-texto: amarelo vivo e saturado (estilo Foxit/Adobe,
  // não um tom pastel apagado) — mas ainda translúcido o bastante para o
  // texto do PDF continuar legível por baixo. Faixa baixa como um
  // marca-texto de verdade cobrindo uma linha de texto (não a altura
  // bruta do arraste) e sem exigir um arraste grande para registrar.
  static const Color _highlightBaseColor = Color(0xFFFFD400);
  static const double _highlightOpacity = 0.40;
  static const double _highlightBandHeight = 20;
  static const double _highlightCornerRadius = 4;
  static const double _minHighlightDragDistance = 6;

  Color get _highlightFillColor =>
      _highlightBaseColor.withValues(alpha: _highlightOpacity);

  PdfDocumentRef? _documentRef;
  PdfViewerController? _controller;
  PdfTextSearcher? _searcher;

  int? _currentPage;
  int? _pageCount;
  bool _searchExpanded = false;
  final _searchFieldController = TextEditingController();

  // TEMP DIAGNÓSTICO: quando não nulo, o build() inteiro é substituído pela
  // tela de erro em vez de tentar montar o leitor — evita que uma falha na
  // criação do PdfDocumentRef/controller derrube a tela inteira.
  Object? _initError;

  // O try/catch em torno de build() (ver `_buildScaffold`/`build` mais
  // abaixo) só protege contra exceções lançadas enquanto ESTA classe monta
  // a árvore de widgets — ele NÃO alcança uma exceção lançada dentro do
  // próprio `PdfViewer` (um descendente com seu próprio State/build,
  // chamado pelo framework em outro momento). É exatamente aí que o
  // pdfrx tem getters internos com force-unwrap (ex.: layout/escala antes
  // do documento terminar de carregar) que já causaram a tela vermelha
  // "Unexpected null value.". Para cobrir esse caso, sobrescrevemos
  // temporariamente o ErrorWidget.builder global enquanto esta tela existe
  // (restaurado em dispose): qualquer falha de build de um descendente vira
  // um espaço vazio no lugar (nunca mais o vermelho do Flutter) e agenda a
  // troca desta tela inteira para `_buildErrorContent()` no próximo frame.
  ErrorWidgetBuilder? _previousErrorWidgetBuilder;

  // Anotações (marca-texto/lápis): [_annotations] guarda só as deste
  // material (todas as páginas); [_otherAnnotations] guarda as de outros
  // materiais/páginas do mesmo usuário, carregadas junto mas preservadas
  // intactas para o merge ao salvar. [_redoStack] guarda o que foi
  // desfeito (Desfazer/Refazer só valem para a página atual).
  _AnnotationMode _mode = _AnnotationMode.hand;
  List<PageAnnotation> _annotations = [];
  List<PageAnnotation> _otherAnnotations = [];
  final List<PageAnnotation> _redoStack = [];
  Offset? _liveHighlightStart;
  Offset? _liveHighlightEnd;
  List<Offset>? _liveStrokePoints;

  // Decide, a cada gesto de arrastar em Marca-texto/Lápis, se a intenção é
  // rolar (movimento predominantemente vertical) ou marcar/desenhar
  // (horizontal/diagonal) — comparando o deslocamento acumulado desde o
  // toque inicial. panEnabled/scaleEnabled do PdfViewer ficam SEMPRE
  // ligados (ver _buildContentArea); é essa decisão de direção, não
  // desligar a navegação nativa, que evita capturar um gesto de rolagem
  // como anotação.
  static const double _gestureIntentThreshold = 10;
  _GestureIntent _gestureIntent = _GestureIntent.undecided;
  Offset? _gestureStartLocal;

  bool get _hasContent => widget.material.bytes != null;

  bool get _canUndo => _annotations.any((a) => a.pageNumber == _currentPage);
  bool get _canRedo => _redoStack.any((a) => a.pageNumber == _currentPage);

  /// O retângulo da página atual no espaço "documento" do pdfrx (estável
  /// durante scroll/zoom — só muda se a página mudar). É o denominador usado
  /// para converter entre posição na tela e fração relativa à página (ver
  /// [localToPageFraction]/[pageFractionToLocal]). `null` enquanto o
  /// documento ainda não carregou ou a página atual é desconhecida.
  Rect? _currentPageRectInDocument() {
    final controller = _controller;
    final page = _currentPage;
    if (controller == null || !controller.isReady || page == null) {
      return null;
    }
    try {
      final layouts = controller.layout.pageLayouts;
      if (page < 1 || page > layouts.length) return null;
      return layouts[page - 1];
    } catch (_) {
      return null;
    }
  }

  /// Junta, num só lugar, tudo que a camada de anotação precisa ler do
  /// [PdfViewerController] a cada repaint (retângulo da página atual,
  /// função de conversão documento→tela e a matriz corrente, só para o
  /// `shouldRepaint` notar mudanças de scroll/zoom). Tudo dentro do mesmo
  /// try/catch porque esses getters do pdfrx têm force-unwraps internos que
  /// podem falhar por uma janela curta entre `isReady` virar `true` e o
  /// layout da página terminar de ser calculado — nesse caso, devolvemos
  /// tudo `null` e a página simplesmente não desenha marcações naquele
  /// frame (elas aparecem no frame seguinte, sem travar a tela com um erro).
  ({Rect? pageRect, Offset Function(Offset)? toLocal, Matrix4? matrix})
  _annotationTransformSnapshot(PdfViewerController controller) {
    try {
      if (!controller.isReady) {
        return (pageRect: null, toLocal: null, matrix: null);
      }
      return (
        pageRect: _currentPageRectInDocument(),
        toLocal: controller.documentToLocal,
        matrix: controller.value,
      );
    } catch (_) {
      return (pageRect: null, toLocal: null, matrix: null);
    }
  }

  @override
  void initState() {
    super.initState();
    _previousErrorWidgetBuilder = ErrorWidget.builder;
    ErrorWidget.builder = (details) {
      debugPrint(
        'MaterialReaderPage: falha ao construir um widget do leitor: '
        '${details.exception}',
      );
      debugPrint('MaterialReaderPage: stack: ${details.stack}');
      if (mounted && _initError == null) {
        // Não dá para chamar setState() durante a própria falha de build
        // (é isso que está acontecendo agora, em algum descendente) —
        // agenda a troca para a tela de erro no quadro seguinte.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _initError = details.exception);
        });
      }
      return const SizedBox.shrink();
    };
    debugPrint(
      'MaterialReaderPage.initState: arquivo="${widget.material.fileName}"',
    );
    debugPrint(
      'MaterialReaderPage.initState: bytes=${widget.material.bytes?.length ?? 0}',
    );
    final bytes = widget.material.bytes;
    if (bytes == null) {
      debugPrint(
        'MaterialReaderPage.initState: sem bytes (material recarregado sem conteúdo em memória).',
      );
      return;
    }
    try {
      _documentRef = PdfDocumentRefData(
        bytes,
        sourceName: widget.material.fileName,
      );
      _controller = PdfViewerController();
      // NOTA: PdfTextSearcher só pode ser criado depois que o PdfViewer
      // avisar que está pronto (callback onViewerReady, mais abaixo) — o
      // construtor de PdfTextSearcher acessa `controller!.document` de
      // imediato, e o controller só fica "ready" depois que o PdfViewer é
      // montado e o documento termina de carregar. Criá-lo aqui (antes do
      // PdfViewer sequer existir na árvore) sempre lançava
      // "Unexpected null value." — a causa real da tela cinza relatada.
      debugPrint(
        'MaterialReaderPage.initState: PdfDocumentRef/controller criados com sucesso.',
      );
    } catch (e, stack) {
      debugPrint('MaterialReaderPage.initState: erro ao preparar o leitor: $e');
      debugPrint('MaterialReaderPage.initState stack: $stack');
      _initError = e;
      return;
    }
    _loadAnnotations();
  }

  Future<void> _loadAnnotations() async {
    final email = currentAccount.value?.email;
    if (email == null) return;
    final all = await LocalStore.loadAnnotations(email);
    if (!mounted) return;
    setState(() {
      _annotations = all
          .where((a) => a.fileName == widget.material.fileName)
          .toList();
      _otherAnnotations = all
          .where((a) => a.fileName != widget.material.fileName)
          .toList();
    });
  }

  Future<void> _saveAnnotations() async {
    final email = currentAccount.value?.email;
    if (email == null) return;
    await LocalStore.saveAnnotations(email, [
      ..._otherAnnotations,
      ..._annotations,
    ]);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Anotações salvas.')));
  }

  @override
  void dispose() {
    final previousErrorWidgetBuilder = _previousErrorWidgetBuilder;
    if (previousErrorWidgetBuilder != null) {
      ErrorWidget.builder = previousErrorWidgetBuilder;
    }
    _searcher?.dispose();
    _searchFieldController.dispose();
    super.dispose();
  }

  void _showComingSoon(String tool) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$tool: em breve nesta demonstração.'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _setMode(_AnnotationMode mode) {
    setState(() {
      _mode = mode;
      _gestureIntent = _GestureIntent.undecided;
      _gestureStartLocal = null;
      _liveHighlightStart = null;
      _liveHighlightEnd = null;
      _liveStrokePoints = null;
    });
  }

  void _undo() {
    final pageAnnotations = _annotations
        .where((a) => a.pageNumber == _currentPage)
        .toList();
    if (pageAnnotations.isEmpty) return;
    final last = pageAnnotations.reduce(
      (a, b) => a.createdAt.isAfter(b.createdAt) ? a : b,
    );
    setState(() {
      _annotations.remove(last);
      _redoStack.add(last);
    });
  }

  void _redo() {
    final pageRedo = _redoStack.where((a) => a.pageNumber == _currentPage);
    if (pageRedo.isEmpty) return;
    final restored = pageRedo.reduce(
      (a, b) => a.createdAt.isAfter(b.createdAt) ? a : b,
    );
    setState(() {
      _redoStack.remove(restored);
      _annotations.add(restored);
    });
  }

  /// Apaga a anotação da página atual mais próxima do ponto tocado — não
  /// "a última" nem "todas", como pedido: mede a distância do toque até
  /// cada marcação (até a borda do retângulo, no caso do marca-texto; até
  /// o ponto mais próximo do traço, no caso do lápis) e remove só a mais
  /// perto. Não troca de modo — Borracha continua selecionada.
  void _eraseNearestAnnotation(Offset tapLocal) {
    final controller = _controller;
    final pageRect = _currentPageRectInDocument();
    if (controller == null || !controller.isReady || pageRect == null) {
      return;
    }
    final pageAnnotations = _annotations
        .where((a) => a.pageNumber == _currentPage)
        .toList();
    if (pageAnnotations.isEmpty) return;
    PageAnnotation? nearest;
    var bestDistanceSquared = double.infinity;
    for (final annotation in pageAnnotations) {
      final distanceSquared = _squaredDistanceToAnnotation(
        annotation,
        tapLocal,
        controller.documentToLocal,
        pageRect,
      );
      if (distanceSquared < bestDistanceSquared) {
        bestDistanceSquared = distanceSquared;
        nearest = annotation;
      }
    }
    if (nearest != null) {
      final toRemove = nearest;
      setState(() => _annotations.remove(toRemove));
    }
  }

  double _squaredDistanceToAnnotation(
    PageAnnotation annotation,
    Offset tapLocal,
    Offset Function(Offset) documentToLocal,
    Rect pageRectInDocument,
  ) {
    final points = annotation.points
        .map(
          (p) => pageFractionToLocal(
            fraction: Offset(p[0], p[1]),
            documentToLocal: documentToLocal,
            pageRectInDocument: pageRectInDocument,
          ),
        )
        .toList();
    if (annotation.type == 'highlight' && points.length >= 2) {
      final rect = Rect.fromPoints(points[0], points[1]);
      final dx = tapLocal.dx < rect.left
          ? rect.left - tapLocal.dx
          : (tapLocal.dx > rect.right ? tapLocal.dx - rect.right : 0.0);
      final dy = tapLocal.dy < rect.top
          ? rect.top - tapLocal.dy
          : (tapLocal.dy > rect.bottom ? tapLocal.dy - rect.bottom : 0.0);
      return dx * dx + dy * dy;
    }
    var best = double.infinity;
    for (final point in points) {
      final dx = point.dx - tapLocal.dx;
      final dy = point.dy - tapLocal.dy;
      final distanceSquared = dx * dx + dy * dy;
      if (distanceSquared < best) best = distanceSquared;
    }
    return best;
  }

  // Usamos eventos de ponteiro "crus" (Listener) em vez de
  // GestureDetector.onPan* de propósito: o reconhecedor de arraste padrão
  // do Flutter só chama onPanStart depois que o dedo/mouse se move além de
  // um limiar mínimo — e, além disso, precisamos ver CADA movimento desde
  // o toque inicial para decidir a direção do gesto (ver
  // [_onAnnotationPointerMove]), o que um recognizer de alto nível já
  // esconderia de nós.
  void _onAnnotationPointerDown(PointerDownEvent event) {
    _gestureStartLocal = event.localPosition;
    _gestureIntent = _GestureIntent.undecided;
    // Não inicia nenhuma prévia visual ainda — só quando o arrasto decidir
    // a intenção como "annotation" (ver _onAnnotationPointerMove). Até lá,
    // o gesto pode virar uma rolagem normal do PdfViewer.
  }

  void _onAnnotationPointerMove(PointerMoveEvent event) {
    final start = _gestureStartLocal;
    if (start == null) return;
    final local = event.localPosition;

    if (_gestureIntent == _GestureIntent.undecided) {
      final dx = (local.dx - start.dx).abs();
      final dy = (local.dy - start.dy).abs();
      if (dx < _gestureIntentThreshold && dy < _gestureIntentThreshold) {
        return; // ainda não moveu o bastante para saber se é rolagem ou marcação.
      }
      // Vertical predominante = rolagem (não captura; o PdfViewer, que
      // nunca teve panEnabled desligado, cuida disso sozinho). Horizontal
      // ou diagonal = anotação: só a partir daqui começamos a prévia.
      final intent = dy > dx
          ? _GestureIntent.scroll
          : _GestureIntent.annotation;
      setState(() {
        _gestureIntent = intent;
        if (intent == _GestureIntent.annotation) {
          if (_mode == _AnnotationMode.highlight) {
            _liveHighlightStart = start;
            _liveHighlightEnd = local;
          } else if (_mode == _AnnotationMode.pen) {
            _liveStrokePoints = [start, local];
          }
        }
      });
      return;
    }

    if (_gestureIntent != _GestureIntent.annotation) {
      return; // decidido como rolagem: deixa o resto do arrasto passar direto.
    }
    if (_mode == _AnnotationMode.highlight && _liveHighlightStart != null) {
      setState(() => _liveHighlightEnd = local);
    } else if (_mode == _AnnotationMode.pen && _liveStrokePoints != null) {
      setState(() => _liveStrokePoints = [..._liveStrokePoints!, local]);
    }
  }

  void _onAnnotationPointerUp(PointerEvent event) {
    final email = currentAccount.value?.email;
    final page = _currentPage;
    final controller = _controller;
    final pageRect = _currentPageRectInDocument();
    // NOTA: o modo (Marca-texto/Lápis) nunca muda sozinho — nem aqui, nem
    // quando o gesto é interpretado como rolagem. O usuário só troca de
    // ferramenta clicando em outra.
    if (_gestureIntent == _GestureIntent.annotation &&
        email != null &&
        page != null &&
        controller != null &&
        pageRect != null &&
        pageRect.width > 0 &&
        pageRect.height > 0) {
      // Salva em fração relativa à PÁGINA (espaço "documento" do pdfrx), não
      // à viewport — assim a marcação acompanha o scroll/zoom em vez de
      // ficar presa na tela (ver [localToPageFraction]).
      Offset toFraction(Offset local) => localToPageFraction(
        local: local,
        localToDocument: controller.localToDocument,
        pageRectInDocument: pageRect,
      );
      if (_mode == _AnnotationMode.highlight &&
          _liveHighlightStart != null &&
          _liveHighlightEnd != null) {
        final rect = computeHighlightBandRect(
          _liveHighlightStart!,
          _liveHighlightEnd!,
          _highlightBandHeight,
        );
        if (rect.width > _minHighlightDragDistance) {
          final p1 = toFraction(rect.topLeft);
          final p2 = toFraction(rect.bottomRight);
          final annotation = PageAnnotation(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            fileName: widget.material.fileName,
            userEmail: email,
            pageNumber: page,
            type: 'highlight',
            points: [
              [p1.dx, p1.dy],
              [p2.dx, p2.dy],
            ],
            color: _highlightFillColor.toARGB32(),
            createdAt: DateTime.now(),
          );
          _annotations = [..._annotations, annotation];
          _redoStack.removeWhere((a) => a.pageNumber == page);
        }
      } else if (_mode == _AnnotationMode.pen &&
          _liveStrokePoints != null &&
          _liveStrokePoints!.length > 1) {
        final annotation = PageAnnotation(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          fileName: widget.material.fileName,
          userEmail: email,
          pageNumber: page,
          type: 'pen',
          points: _liveStrokePoints!.map((p) {
            final f = toFraction(p);
            return [f.dx, f.dy];
          }).toList(),
          color: AppColors.primary.toARGB32(),
          createdAt: DateTime.now(),
        );
        _annotations = [..._annotations, annotation];
        _redoStack.removeWhere((a) => a.pageNumber == page);
      }
    }
    setState(() {
      _gestureIntent = _GestureIntent.undecided;
      _gestureStartLocal = null;
      _liveHighlightStart = null;
      _liveHighlightEnd = null;
      _liveStrokePoints = null;
    });
  }

  void _toggleSearch() {
    final expanding = !_searchExpanded;
    setState(() => _searchExpanded = expanding);
    if (!expanding) {
      _searchFieldController.clear();
      _searcher?.resetTextSearch();
    }
  }

  void _openThumbnailsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.62,
        child: SafeArea(child: _buildThumbnailList(closeOnTap: true)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    debugPrint(
      'MaterialReaderPage.build: hasContent=$_hasContent initError=$_initError',
    );
    // TEMP DIAGNÓSTICO: qualquer exceção síncrona durante a montagem desta
    // tela (ex.: um erro inesperado ao construir o PdfViewer) cai aqui em
    // vez de derrubar o app inteiro — só esta página vira a tela de erro.
    try {
      return _buildScaffold(context);
    } catch (e, stack) {
      debugPrint('MaterialReaderPage.build: exceção não tratada: $e');
      debugPrint('MaterialReaderPage.build stack: $stack');
      return Scaffold(
        backgroundColor: const Color(0xFFEFF2F6),
        body: SafeArea(child: _buildErrorContent()),
      );
    }
  }

  Widget _buildScaffold(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= _wideBreakpoint;
    return Scaffold(
      backgroundColor: const Color(0xFFEFF2F6),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(wide: wide),
            if (_initError != null)
              Expanded(child: _buildErrorContent())
            else ...[
              if (_hasContent) _buildToolbarRow(),
              if (_hasContent) _buildControlsRow(),
              if (_hasContent && _searchExpanded && _searcher != null)
                _buildSearchBar(),
              Expanded(
                child: _hasContent
                    ? _buildContentArea(wide: wide)
                    : _buildMissingContent(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader({required bool wide}) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(
              LucideIcons.chevronLeft,
              color: AppColors.primary,
              size: 26,
            ),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Leitura do material',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: AppColors.primary,
                  ),
                ),
                Text(
                  widget.material.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.mutedText,
                  ),
                ),
              ],
            ),
          ),
          if (_hasContent && !wide)
            IconButton(
              onPressed: _openThumbnailsSheet,
              tooltip: 'Miniaturas',
              icon: const Icon(
                LucideIcons.layoutGrid,
                color: AppColors.secondary,
                size: 21,
              ),
            ),
          IconButton(
            onPressed: () {},
            icon: const Icon(
              LucideIcons.bookmark,
              color: AppColors.secondary,
              size: 21,
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(
              LucideIcons.moreVertical,
              color: AppColors.primary,
            ),
            onSelected: (value) {
              if (value == 'quiz') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => QuizScreen(material: widget.material),
                  ),
                );
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'quiz', child: Text('Responder quiz')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildToolbarRow() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _ToolButton(
              icon: LucideIcons.hand,
              label: 'Mão',
              selected: _mode == _AnnotationMode.hand,
              onTap: () => _setMode(_AnnotationMode.hand),
            ),
            _ToolButton(
              icon: LucideIcons.highlighter,
              label: 'Marca-texto',
              selected: _mode == _AnnotationMode.highlight,
              onTap: kAnnotationToolsEnabled
                  ? () => _setMode(_AnnotationMode.highlight)
                  : null,
              disabledMessage: 'Em breve nesta versão',
            ),
            _ToolButton(
              icon: LucideIcons.pencil,
              label: 'Lápis',
              selected: _mode == _AnnotationMode.pen,
              onTap: kAnnotationToolsEnabled
                  ? () => _setMode(_AnnotationMode.pen)
                  : null,
              disabledMessage: 'Em breve nesta versão',
            ),
            _ToolButton(
              icon: LucideIcons.eraser,
              label: 'Borracha',
              selected: _mode == _AnnotationMode.eraser,
              onTap: kAnnotationToolsEnabled
                  ? () => _setMode(_AnnotationMode.eraser)
                  : null,
              disabledMessage: 'Em breve nesta versão',
            ),
            _ToolButton(
              icon: LucideIcons.undo2,
              label: 'Desfazer',
              onTap: (kAnnotationToolsEnabled && _canUndo) ? _undo : null,
              disabledMessage: kAnnotationToolsEnabled
                  ? 'Nada para desfazer nesta página'
                  : 'Em breve nesta versão',
            ),
            _ToolButton(
              icon: LucideIcons.redo2,
              label: 'Refazer',
              onTap: (kAnnotationToolsEnabled && _canRedo) ? _redo : null,
              disabledMessage: kAnnotationToolsEnabled
                  ? 'Nada para refazer nesta página'
                  : 'Em breve nesta versão',
            ),
            _DisabledPill(
              onTap: () => _showComingSoon('Cor da marcação'),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ColorSwatchDot(),
                  SizedBox(width: 4),
                  Icon(
                    LucideIcons.chevronDown,
                    size: 14,
                    color: AppColors.mutedText,
                  ),
                ],
              ),
            ),
            _DisabledPill(
              onTap: () => _showComingSoon('Espessura do traço'),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '2 px',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.mutedText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(width: 4),
                  Icon(
                    LucideIcons.chevronDown,
                    size: 14,
                    color: AppColors.mutedText,
                  ),
                ],
              ),
            ),
            _ToolButton(
              icon: LucideIcons.cloudUpload,
              label: 'Salvar anotações',
              onTap: kAnnotationToolsEnabled ? _saveAnnotations : null,
              disabledMessage: 'Em breve nesta versão',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlsRow() {
    final controller = _controller;
    if (controller == null) return const SizedBox.shrink();
    final currentPage = _currentPage;
    final pageCount = _pageCount;
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Os botões de zoom (e o texto de porcentagem) precisam da própria
            // AnimatedBuilder porque o zoom do PdfViewerController muda sem
            // passar por setState desta tela — sem isso, "isReady"/"currentZoom"
            // só seriam relidos por acaso, na próxima vez que algo IRRELEVANTE
            // (like trocar de página ou de ferramenta) desse rebuild na tela,
            // deixando os botões "presos" com o habilitado/desabilitado de
            // quando foram construídos pela última vez.
            AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                // minScale/maxScale (assim como currentZoom) só podem ser
                // lidos quando o pdfrx já terminou de calcular o layout do
                // documento — antes disso, esses getters acessam um campo
                // interno do pdfrx ainda não inicializado e lançam uma
                // exceção. Isso acontecia sempre na primeira montagem desta
                // linha (o próprio AnimatedBuilder já constrói de imediato,
                // antes do onViewerReady disparar), derrubando a tela assim
                // que o leitor abria.
                final ready = controller.isReady;
                final zoom = ready ? controller.currentZoom : 0.0;
                final canZoomOut = canZoomOutFor(
                  ready: ready,
                  zoom: zoom,
                  minScale: ready ? controller.minScale : 0.0,
                );
                final canZoomIn = canZoomInFor(
                  ready: ready,
                  zoom: zoom,
                  maxScale: ready ? controller.maxScale : 0.0,
                );
                return Row(
                  children: [
                    IconButton(
                      tooltip: 'Diminuir zoom',
                      onPressed: canZoomOut
                          ? () => controller.zoomDown()
                          : null,
                      icon: const Icon(LucideIcons.zoomOut, size: 20),
                      color: AppColors.primary,
                    ),
                    SizedBox(
                      width: 44,
                      child: Text(
                        ready ? '${(zoom * 100).round()}%' : '—',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Aumentar zoom',
                      onPressed: canZoomIn ? () => controller.zoomUp() : null,
                      icon: const Icon(LucideIcons.zoomIn, size: 20),
                      color: AppColors.primary,
                    ),
                  ],
                );
              },
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: 1,
              height: 22,
              color: AppColors.border,
            ),
            IconButton(
              tooltip: 'Primeira página',
              onPressed: (pageCount != null && (currentPage ?? 1) > 1)
                  ? () => controller.goToPage(pageNumber: 1)
                  : null,
              icon: const Icon(LucideIcons.chevronsLeft, size: 20),
              color: AppColors.primary,
            ),
            IconButton(
              tooltip: 'Página anterior',
              onPressed: currentPage != null && currentPage > 1
                  ? () => controller.goToPage(pageNumber: currentPage - 1)
                  : null,
              icon: const Icon(LucideIcons.chevronLeft, size: 20),
              color: AppColors.primary,
            ),
            SizedBox(
              width: 60,
              child: Text(
                '${currentPage ?? '-'} / ${pageCount ?? '-'}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Próxima página',
              onPressed:
                  (currentPage != null &&
                      pageCount != null &&
                      currentPage < pageCount)
                  ? () => controller.goToPage(pageNumber: currentPage + 1)
                  : null,
              icon: const Icon(LucideIcons.chevronRight, size: 20),
              color: AppColors.primary,
            ),
            IconButton(
              tooltip: 'Última página',
              onPressed: (pageCount != null && currentPage != pageCount)
                  ? () => controller.goToPage(pageNumber: pageCount)
                  : null,
              icon: const Icon(LucideIcons.chevronsRight, size: 20),
              color: AppColors.primary,
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: 1,
              height: 22,
              color: AppColors.border,
            ),
            IconButton(
              tooltip: 'Buscar no documento',
              onPressed: _searcher != null ? _toggleSearch : null,
              icon: Icon(
                LucideIcons.search,
                size: 20,
                color: _searchExpanded
                    ? AppColors.secondary
                    : AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    final searcher = _searcher;
    if (searcher == null) return const SizedBox.shrink();
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(10, 0, 4, 8),
      child: AnimatedBuilder(
        animation: searcher,
        builder: (context, _) {
          final hasMatches = searcher.hasMatches;
          final hasQuery = _searchFieldController.text.isNotEmpty;
          return Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: TextField(
                    controller: _searchFieldController,
                    autofocus: true,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Buscar no documento',
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onChanged: (value) {
                      setState(() {});
                      searcher.startTextSearch(value);
                    },
                    onSubmitted: (value) => searcher.startTextSearch(
                      value,
                      searchImmediately: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (searcher.isSearching)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (hasQuery)
                Text(
                  hasMatches
                      ? '${searcher.currentIndex! + 1}/${searcher.matches.length}'
                      : '0/0',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.mutedText,
                  ),
                ),
              IconButton(
                tooltip: 'Resultado anterior',
                onPressed: hasMatches ? () => searcher.goToPrevMatch() : null,
                icon: const Icon(LucideIcons.chevronUp, size: 18),
              ),
              IconButton(
                tooltip: 'Próximo resultado',
                onPressed: hasMatches ? () => searcher.goToNextMatch() : null,
                icon: const Icon(LucideIcons.chevronDown, size: 18),
              ),
              IconButton(
                tooltip: 'Fechar busca',
                onPressed: _toggleSearch,
                icon: const Icon(LucideIcons.x, size: 18),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildContentArea({required bool wide}) {
    debugPrint(
      'MaterialReaderPage: construindo PdfViewer para '
      '"${widget.material.fileName}" (bytes=${widget.material.bytes?.length}).',
    );
    final documentRef = _documentRef;
    if (documentRef == null) return _buildErrorContent();
    final searcher = _searcher;
    final viewer = PdfViewer(
      documentRef,
      controller: _controller,
      params: PdfViewerParams(
        backgroundColor: const Color(0xFFEFF2F6),
        margin: 16,
        // Nunca desligamos pan/zoom nativos: panEnabled/scaleEnabled são
        // lidos pelo pdfrx no build(), não por gesto — desligá-los durante
        // um arrasto já em andamento não tem efeito (o reconhecedor de
        // gesto do pdfrx já foi registrado com o valor de antes do toque),
        // e desligá-los enquanto uma ferramenta está selecionada bloqueia
        // a rolagem por inteiro. Em vez disso, é a direção do arrasto que
        // decide rolagem vs. anotação — ver [_onAnnotationPointerMove].
        panEnabled: true,
        scaleEnabled: true,
        pagePaintCallbacks: searcher != null
            ? [searcher.pageTextMatchPaintCallback]
            : null,
        onViewerReady: (document, controller) {
          debugPrint(
            'PdfViewer.onViewerReady: documento pronto com '
            '${document.pages.length} página(s).',
          );
          if (!mounted) return;
          setState(() {
            _pageCount = document.pages.length;
            _currentPage = controller.pageNumber ?? 1;
            // Só agora o controller está de fato "ready" — criar o
            // PdfTextSearcher antes disso (ex.: no initState) derrubava a
            // tela com "Unexpected null value.".
            _searcher ??= PdfTextSearcher(controller);
          });
          widget.onPageCountResolved?.call(document.pages.length);
        },
        onDocumentLoadFinished: (documentRef, loadSucceeded) {
          debugPrint(
            'PdfViewer.onDocumentLoadFinished: ${documentRef.key} '
            'sucesso=$loadSucceeded',
          );
        },
        onPageChanged: (pageNumber) {
          if (!mounted || pageNumber == null) return;
          setState(() => _currentPage = pageNumber);
        },
        loadingBannerBuilder: (context, bytesDownloaded, totalBytes) =>
            const Center(child: CircularProgressIndicator()),
        errorBannerBuilder: (context, error, stackTrace, documentRef) {
          debugPrint('PdfViewer.errorBannerBuilder: $error');
          debugPrint('PdfViewer.errorBannerBuilder stack: $stackTrace');
          return _buildErrorContent();
        },
      ),
    );

    // Sem kAnnotationToolsEnabled, nem monta a camada de anotação por cima
    // do PDF — não só ela nunca captura toque (ver os _ToolButton
    // desativados acima), como nem chega a existir na árvore de widgets,
    // eliminando de vez qualquer risco de interferir na rolagem/zoom/toque
    // nativos do PdfViewer.
    final viewerWithAnnotations = kAnnotationToolsEnabled
        ? Stack(
            children: [
              Positioned.fill(child: viewer),
              Positioned.fill(child: _buildAnnotationLayer()),
            ],
          )
        : viewer;

    if (!wide) return viewerWithAnnotations;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 150, child: _buildThumbnailList()),
        Container(width: 1, color: AppColors.border),
        Expanded(child: viewerWithAnnotations),
      ],
    );
  }

  /// Camada visual por cima do PDF: sempre desenha as marcações já feitas
  /// na página atual (mesmo no modo Mão, para que fiquem visíveis durante a
  /// leitura normal), mas só captura toque/mouse quando uma ferramenta de
  /// anotação está ativa — no modo Mão, [IgnorePointer] deixa os gestos
  /// passarem direto para o [PdfViewer] por baixo (pan/zoom/links normais).
  Widget _buildAnnotationLayer() {
    final drawingMode =
        _mode == _AnnotationMode.highlight || _mode == _AnnotationMode.pen;
    final controller = _controller;
    return LayoutBuilder(
      builder: (context, constraints) {
        final boxSize = constraints.biggest;
        final pageAnnotations = _annotations
            .where((a) => a.pageNumber == _currentPage)
            .toList();
        return IgnorePointer(
          ignoring: _mode == _AnnotationMode.hand,
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: drawingMode ? _onAnnotationPointerDown : null,
            onPointerMove: drawingMode ? _onAnnotationPointerMove : null,
            onPointerUp: drawingMode ? _onAnnotationPointerUp : null,
            onPointerCancel: drawingMode ? _onAnnotationPointerUp : null,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapUp: _mode == _AnnotationMode.eraser
                  ? (details) => _eraseNearestAnnotation(details.localPosition)
                  : null,
              // AnimatedBuilder ouvindo o controller: as marcações são
              // guardadas em fração da PÁGINA (documento), não da tela, então
              // é só reconvertê-las para a posição local atual a cada
              // notificação de scroll/zoom do PdfViewer que elas "seguem" a
              // página automaticamente (ver [pageFractionToLocal]).
              child: controller == null
                  ? CustomPaint(
                      size: boxSize,
                      painter: _AnnotationPainter(
                        annotations: pageAnnotations,
                        pageRectInDocument: null,
                        documentToLocal: null,
                        matrix: null,
                        liveHighlightStart: _liveHighlightStart,
                        liveHighlightEnd: _liveHighlightEnd,
                        liveStrokePoints: _liveStrokePoints,
                        highlightBandHeight: _highlightBandHeight,
                        highlightCornerRadius: _highlightCornerRadius,
                        liveHighlightColor: _highlightFillColor,
                      ),
                    )
                  : AnimatedBuilder(
                      animation: controller,
                      builder: (context, _) {
                        final snapshot = _annotationTransformSnapshot(
                          controller,
                        );
                        return CustomPaint(
                          size: boxSize,
                          painter: _AnnotationPainter(
                            annotations: pageAnnotations,
                            pageRectInDocument: snapshot.pageRect,
                            documentToLocal: snapshot.toLocal,
                            matrix: snapshot.matrix,
                            liveHighlightStart: _liveHighlightStart,
                            liveHighlightEnd: _liveHighlightEnd,
                            liveStrokePoints: _liveStrokePoints,
                            highlightBandHeight: _highlightBandHeight,
                            highlightCornerRadius: _highlightCornerRadius,
                            liveHighlightColor: _highlightFillColor,
                          ),
                        );
                      },
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildThumbnailList({bool closeOnTap = false}) {
    final documentRef = _documentRef;
    if (documentRef == null) return const SizedBox.shrink();
    return Container(
      color: AppColors.surface,
      child: PdfDocumentViewBuilder(
        documentRef: documentRef,
        builder: (context, document) {
          if (document == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView.builder(
            padding: const EdgeInsets.all(10),
            itemCount: document.pages.length,
            itemBuilder: (context, index) {
              final pageNumber = index + 1;
              final isCurrent = pageNumber == _currentPage;
              final page = document.pages[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    _controller?.goToPage(pageNumber: pageNumber);
                    if (closeOnTap) Navigator.maybePop(context);
                  },
                  child: Column(
                    children: [
                      AspectRatio(
                        aspectRatio: page.width / page.height,
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: isCurrent
                                  ? AppColors.secondary
                                  : AppColors.border,
                              width: isCurrent ? 2 : 1,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: PdfPageView(
                            document: document,
                            pageNumber: pageNumber,
                            maximumDpi: 90,
                            decoration: const BoxDecoration(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$pageNumber',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isCurrent
                              ? FontWeight.w800
                              : FontWeight.w500,
                          color: isCurrent
                              ? AppColors.secondary
                              : AppColors.mutedText,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildMissingContent() {
    // SingleChildScrollView (em vez de só Center) evita "bottom overflowed"
    // quando a altura disponível é pequena (ex.: janela do navegador baixa)
    // — sem isso, um Column de altura fixa maior que a área visível
    // simplesmente estourava por baixo em vez de rolar.
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              LucideIcons.fileX2,
              size: 48,
              color: AppColors.mutedText,
            ),
            const SizedBox(height: 16),
            const Text(
              'Este PDF precisa ser carregado novamente',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Nesta demonstração local, o conteúdo do PDF é mantido apenas '
              'durante a sessão atual — ele não fica salvo permanentemente. '
              'Volte para "Material de estudo" e carregue o arquivo '
              'novamente para continuar a leitura.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.mutedText, height: 1.4),
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              label: 'Voltar para Material de estudo',
              onPressed: () => Navigator.maybePop(context),
            ),
          ],
        ),
      ),
    );
  }

  /// Tela de erro exibida quando o PDF não pode ser aberto/renderizado —
  /// seja por uma exceção síncrona ao preparar o leitor ([_initError]) ou
  /// por uma falha assíncrona reportada pelo próprio `pdfrx`
  /// ([PdfViewerParams.errorBannerBuilder]). O detalhe técnico do erro só
  /// vai para o log (`debugPrint`), nunca para a tela.
  Widget _buildErrorContent() {
    // SingleChildScrollView pelo mesmo motivo de _buildMissingContent: evita
    // overflow por baixo quando a altura disponível é pequena.
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              LucideIcons.fileWarning,
              size: 48,
              color: AppColors.mutedText,
            ),
            const SizedBox(height: 16),
            const Text(
              'Não foi possível abrir este PDF.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Volte e carregue o material novamente.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.mutedText, height: 1.4),
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              label: 'Voltar para materiais',
              onPressed: () => Navigator.maybePop(context),
            ),
          ],
        ),
      ),
    );
  }
}

/// Desativa temporariamente Marca-texto/Lápis/Borracha/Desfazer/Refazer/
/// Salvar anotações (mostrados como "em breve", sem capturar toque algum) e
/// para de desenhar a camada de anotação por cima do PDF — para a entrega
/// final, priorizando um leitor de PDF simples e estável (rolagem, zoom,
/// navegação de página, miniaturas) em vez das ferramentas de marcação, que
/// tinham bugs de rolagem/coordenadas. O código de anotação continua no
/// arquivo, só desligado por esta flag, para poder ser reativado depois.
const bool kAnnotationToolsEnabled = false;

/// Espessura do traço de lápis: uma linha fina, não uma faixa grossa.
const double kPenStrokeWidth = 2;

/// Uma faixa de marca-texto real cobre uma linha de texto, não a área bruta
/// arrastada — por isso a altura é fixa ([bandHeight]), centralizada no
/// ponto médio vertical do arraste, e só a largura segue o gesto do
/// usuário. Compartilhada entre o handler de gesto (para salvar a
/// marcação) e o [_AnnotationPainter] (para desenhar a prévia "ao vivo"
/// com a mesma forma que ela terá depois de solta).
Rect computeHighlightBandRect(Offset start, Offset end, double bandHeight) {
  final left = start.dx < end.dx ? start.dx : end.dx;
  final right = start.dx < end.dx ? end.dx : start.dx;
  final centerY = (start.dy + end.dy) / 2;
  return Rect.fromLTRB(
    left,
    centerY - bandHeight / 2,
    right,
    centerY + bandHeight / 2,
  );
}

/// Converte um ponto local do leitor (onde o toque aconteceu, relativo à
/// área do [PdfViewer]) para uma fração relativa à PÁGINA no espaço de
/// "documento" do pdfrx — não à área visível da tela. Diferente de uma
/// fração da viewport (o bug original: marcação "presa na tela"), essa
/// fração não muda quando a página rola ou o zoom muda, porque tanto o
/// ponto (via [localToDocument]) quanto o retângulo da página
/// ([pageRectInDocument]) vêm do mesmo referencial estável do
/// PdfViewerController — só a CONVERSÃO de volta para a tela (ver
/// [pageFractionToLocal]) depende do scroll/zoom atuais.
Offset localToPageFraction({
  required Offset local,
  required Offset Function(Offset) localToDocument,
  required Rect pageRectInDocument,
}) {
  final doc = localToDocument(local);
  return Offset(
    (doc.dx - pageRectInDocument.left) / pageRectInDocument.width,
    (doc.dy - pageRectInDocument.top) / pageRectInDocument.height,
  );
}

/// Inverso de [localToPageFraction]: dada uma fração relativa à página (o
/// que fica guardado em [PageAnnotation.points]), devolve a posição local
/// ATUAL na tela — usando [documentToLocal], que reflete o scroll/zoom
/// correntes do PdfViewer. Chamado a cada repaint (ver o `AnimatedBuilder`
/// em `_buildAnnotationLayer`), então a marcação sempre aparece onde a
/// página está agora, nunca onde estava quando foi desenhada.
Offset pageFractionToLocal({
  required Offset fraction,
  required Offset Function(Offset) documentToLocal,
  required Rect pageRectInDocument,
}) {
  final doc = Offset(
    pageRectInDocument.left + fraction.dx * pageRectInDocument.width,
    pageRectInDocument.top + fraction.dy * pageRectInDocument.height,
  );
  return documentToLocal(doc);
}

/// Margem de tolerância ao comparar o zoom atual com min/max: o
/// PdfViewerController expõe doubles calculados (fit-to-width etc.), então
/// uma comparação estrita (`>`/`<`) pode deixar o botão "quase habilitado"
/// por causa de erro de ponto flutuante — mesma tolerância usada
/// internamente pelo pdfrx para considerar dois zooms "iguais".
const double kZoomBoundaryTolerance = 0.01;

/// Se o botão "Diminuir zoom" deve estar habilitado: só quando o visualizador
/// já carregou o documento e o zoom atual está acima do mínimo permitido.
bool canZoomOutFor({
  required bool ready,
  required double zoom,
  required double minScale,
}) => ready && zoom > minScale + kZoomBoundaryTolerance;

/// Se o botão "Aumentar zoom" deve estar habilitado: só quando o
/// visualizador já carregou o documento e o zoom atual está abaixo do
/// máximo permitido.
bool canZoomInFor({
  required bool ready,
  required double zoom,
  required double maxScale,
}) => ready && zoom < maxScale - kZoomBoundaryTolerance;

/// Desenha as marcações da página atual (destaques e traços de lápis) por
/// cima do PDF. Os pontos de cada [PageAnnotation] são fração relativa à
/// PÁGINA (espaço "documento" do pdfrx, ver [pageFractionToLocal]), então
/// são reconvertidos para a posição local ATUAL a cada repaint usando
/// [pageRectInDocument]/[documentToLocal] — é assim que a marcação
/// acompanha o scroll e o zoom em vez de ficar presa na tela. Sem esses dois
/// (documento ainda não carregou), as marcações salvas não são desenhadas,
/// mas o traço/destaque "ao vivo" ([liveHighlightStart]/[liveStrokePoints]),
/// que já está em coordenadas locais, continua aparecendo normalmente.
class _AnnotationPainter extends CustomPainter {
  final List<PageAnnotation> annotations;
  final Rect? pageRectInDocument;
  final Offset Function(Offset)? documentToLocal;
  // Só para o shouldRepaint detectar mudança de scroll/zoom: a conversão de
  // verdade usa [documentToLocal], não este valor diretamente.
  final Matrix4? matrix;
  final Offset? liveHighlightStart;
  final Offset? liveHighlightEnd;
  final List<Offset>? liveStrokePoints;
  final double highlightBandHeight;
  final double highlightCornerRadius;
  final Color liveHighlightColor;

  const _AnnotationPainter({
    required this.annotations,
    required this.pageRectInDocument,
    required this.documentToLocal,
    required this.matrix,
    required this.highlightBandHeight,
    required this.highlightCornerRadius,
    required this.liveHighlightColor,
    this.liveHighlightStart,
    this.liveHighlightEnd,
    this.liveStrokePoints,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(highlightCornerRadius);
    final pageRect = pageRectInDocument;
    final toLocal = documentToLocal;
    if (pageRect != null &&
        toLocal != null &&
        pageRect.width > 0 &&
        pageRect.height > 0) {
      Offset toScreen(List<double> p) => pageFractionToLocal(
        fraction: Offset(p[0], p[1]),
        documentToLocal: toLocal,
        pageRectInDocument: pageRect,
      );
      for (final annotation in annotations) {
        if (annotation.type == 'highlight' && annotation.points.length >= 2) {
          final p1 = toScreen(annotation.points[0]);
          final p2 = toScreen(annotation.points[1]);
          canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromPoints(p1, p2), radius),
            Paint()
              ..color = Color(annotation.color)
              ..style = PaintingStyle.fill,
          );
        } else if (annotation.type == 'pen' && annotation.points.length >= 2) {
          _drawStroke(
            canvas,
            annotation.points.map(toScreen).toList(),
            Color(annotation.color),
          );
        }
      }
    }

    if (liveHighlightStart != null && liveHighlightEnd != null) {
      final band = computeHighlightBandRect(
        liveHighlightStart!,
        liveHighlightEnd!,
        highlightBandHeight,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(band, radius),
        Paint()
          ..color = liveHighlightColor
          ..style = PaintingStyle.fill,
      );
    }
    if (liveStrokePoints != null && liveStrokePoints!.length >= 2) {
      _drawStroke(canvas, liveStrokePoints!, AppColors.primary);
    }
  }

  void _drawStroke(Canvas canvas, List<Offset> points, Color color) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = kPenStrokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _AnnotationPainter oldDelegate) =>
      oldDelegate.annotations != annotations ||
      oldDelegate.pageRectInDocument != pageRectInDocument ||
      oldDelegate.matrix != matrix ||
      oldDelegate.liveHighlightStart != liveHighlightStart ||
      oldDelegate.liveHighlightEnd != liveHighlightEnd ||
      oldDelegate.liveStrokePoints != liveStrokePoints;

  // Sem isso, o CustomPaint reivindica toda a área como "hitTestSelf" (o
  // CustomPainter.hitTest padrão é null, tratado como true), o que faz o
  // Stack parar de testar o PdfViewer por baixo assim que uma ferramenta é
  // selecionada — travando a rolagem mesmo com panEnabled/scaleEnabled
  // sempre ligados. Retornando false aqui, o CustomPaint (e os Listener/
  // GestureDetector translúcidos acima dele) continuam recebendo os
  // eventos normalmente, mas não bloqueiam mais a propagação para o
  // PdfViewer.
  @override
  bool? hitTest(Offset position) => false;
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final String? disabledMessage;

  const _ToolButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.selected = false,
    this.disabledMessage,
  });

  @override
  Widget build(BuildContext context) {
    final active = onTap != null;
    final color = active
        ? (selected ? AppColors.secondary : AppColors.primary)
        : AppColors.mutedText.withValues(alpha: 0.6);
    return Tooltip(
      message: active ? label : (disabledMessage ?? 'Em breve'),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.secondary.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 19, color: color),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DisabledPill extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;

  const _DisabledPill({required this.child, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Em breve',
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _ColorSwatchDot extends StatelessWidget {
  const _ColorSwatchDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: const BoxDecoration(
        color: AppColors.accent,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _PdfBadge extends StatelessWidget {
  const _PdfBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: AppColors.secondary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.secondary.withValues(alpha: 0.35)),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.fileText, color: AppColors.secondary, size: 18),
          Text(
            'PDF',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              color: AppColors.secondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _RoundIcon({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 24),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;

  const _InfoBanner({
    required this.icon,
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.lightBlue.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.accent, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: AppColors.primary,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  text,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: AppColors.mutedText,
                    height: 1.35,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Uma pergunta do quiz demonstrativo: [category] e [tip] só aparecem no
/// card de contexto/dica da tela — não afetam a pontuação.
/// Uma pergunta do quiz: [category] e [tip] só aparecem no card de
/// contexto/dica da tela — não afetam a pontuação. Gerada a partir do texto
/// real de um [StudyMaterial] por [generateQuizFromText], nunca fixa.
class QuizQuestion {
  final String category;
  final String question;
  final List<String> options;
  final int correct;
  final String tip;
  /// O termo-chave real do material que esta pergunta cobre (ex.:
  /// "medição", "sensor") — vazio para perguntas do tipo "qual frase é
  /// real" ([_buildSentenceQuestion]), que não giram em torno de um único
  /// termo. Usado por [_QuizScreenState] para acumular, ao longo do quiz,
  /// quais termos o usuário acertou/errou e mostrar isso de verdade em
  /// [PerformanceScreen] (pontos fortes / o que revisar), em vez de tags
  /// fixas sem relação com o PDF estudado.
  final String term;

  const QuizQuestion({
    required this.category,
    required this.question,
    required this.options,
    required this.correct,
    required this.tip,
    this.term = '',
  });
}

/// Palavras comuns em português (conectores, pronomes, verbos auxiliares)
/// ignoradas ao contar frequência em [extractKeyTerms] — sem esse filtro,
/// as palavras "mais frequentes" de qualquer PDF seriam sempre essas, nunca
/// um conceito de verdade do conteúdo.
const Set<String> kQuizStopWords = {
  'para', 'como', 'isso', 'esse', 'essa', 'esses', 'essas', 'este', 'esta',
  'estes', 'estas', 'aquele', 'aquela', 'aqueles', 'aquelas', 'sobre',
  'entre', 'quando', 'onde', 'mais', 'menos', 'muito', 'muita', 'muitos',
  'muitas', 'pouco', 'pouca', 'também', 'ainda', 'sendo', 'assim', 'então',
  'porque', 'porém', 'todos', 'todas', 'cada', 'pelo', 'pela', 'pelos',
  'pelas', 'pode', 'podem', 'deve', 'devem', 'pois', 'qual', 'quais',
  'quanto', 'quanta', 'seus', 'suas', 'seu', 'sua', 'ele', 'ela', 'eles',
  'elas', 'nesse', 'nessa', 'neste', 'nesta', 'nestes', 'nestas', 'desse',
  'dessa', 'deste', 'desta', 'destes', 'destas', 'nosso', 'nossa', 'nossos',
  'nossas', 'foram', 'foi', 'são', 'está', 'estão', 'tem', 'têm', 'haver',
  'houve', 'sido', 'toda', 'todo', 'apenas', 'outro', 'outra', 'outros',
  'outras', 'algum', 'alguma', 'alguns', 'algumas', 'mesmo', 'mesma',
  'mesmos', 'mesmas', 'antes', 'depois', 'durante', 'dentro', 'fora',
  'sempre', 'nunca', 'já', 'não', 'sim',
};

/// Termos genéricos usados como alternativa errada quando faltam termos
/// recorrentes distintos no próprio texto — usados só na pergunta "qual
/// destes termos é um conceito citado", nunca como resposta certa.
const List<String> kQuizGenericDistractorTerms = [
  'introdução',
  'resumo',
  'exercício',
  'referência',
  'anexo',
  'apêndice',
  'bibliografia',
];

/// Um "fato" curto e didático sobre um conceito do domínio (instrumentação/
/// eletrônica) — [statement] é sempre uma frase curta e limpa (nunca uma
/// citação literal longa do PDF, ver regra de "reescrever de forma limpa e
/// didática"), e [confusables] são as chaves de OUTROS conceitos do mesmo
/// campo cujo [statement] vira um distrator plausível mas conceitualmente
/// errado para este ([_buildConceptQuestion]) — a "confusão conceitual"
/// pedida (trocar sensor por atuador, entrada por saída, etc.), nunca uma
/// frase evasiva tipo "não aparece no material" que entrega a resposta por
/// eliminação. [hint] orienta o RACIOCÍNIO sobre o conceito (o papel/
/// função dele, de forma indireta) sem repetir [statement] — validado por
/// [_safeHintFor] antes de virar a dica exibida, nunca usado direto.
class _ConceptFact {
  final String statement;
  final List<String> confusables;
  final String hint;
  const _ConceptFact({
    required this.statement,
    required this.confusables,
    required this.hint,
  });
}

/// Base de conhecimento curada dos conceitos do domínio deste material
/// (instrumentação/eletrônica) — chaves em minúsculas, batendo com as
/// strings devolvidas por [extractQuizConcepts] (singular e plural de
/// termos técnicos já chegam normalizados para a forma canônica, ver
/// [_kSoloConceptCanonical]). Cada [statement] tem entre ~50 e 140
/// caracteres, do mesmo tamanho entre si, para nenhuma alternativa
/// "denunciar" a resposta certa só por ser a única tecnicamente redigida
/// ou muito mais longa que as outras.
final Map<String, _ConceptFact> _kConceptFacts = {
  'sistema de medição': const _ConceptFact(
    statement: 'Fornecer informações sobre o valor de uma grandeza física '
        'que se deseja medir.',
    confusables: ['atuadores', 'instrumentos de medição', 'malha fechada'],
    hint: 'Pense no papel de obter dados sobre algo que está sendo '
        'observado, antes de qualquer controle ou ação sobre ele.',
  ),
  'sistemas de medição': const _ConceptFact(
    statement: 'Fornecer informações sobre o valor de uma grandeza física '
        'que se deseja medir.',
    confusables: ['atuadores', 'instrumentos de medição', 'malha fechada'],
    hint: 'Pense no papel de obter dados sobre algo que está sendo '
        'observado, antes de qualquer controle ou ação sobre ele.',
  ),
  'sensores': const _ConceptFact(
    statement: 'Converter grandezas físicas em sinais elétricos que podem '
        'ser processados.',
    confusables: [
      'atuadores',
      'processamento do sinal',
      'instrumentos de medição',
    ],
    hint: 'Observe qual componente fica mais próximo do ambiente, captando '
        'o que se quer acompanhar.',
  ),
  'atuadores': const _ConceptFact(
    statement: 'Transformar sinais elétricos em outras grandezas físicas, '
        'como movimento.',
    confusables: ['sensores', 'instrumentos de medição', 'aquisição de sinais'],
    hint: 'Pense no componente que recebe um comando e provoca uma ação '
        'física perceptível.',
  ),
  'transdutores': const _ConceptFact(
    statement: 'Converter uma forma de energia em outra, ligando grandezas '
        'físicas distintas.',
    confusables: ['sensores', 'atuadores', 'sinais elétricos'],
    hint: 'Repare na ideia de uma ponte entre dois tipos diferentes de '
        'energia ou de sinal.',
  ),
  'sinais elétricos': const _ConceptFact(
    statement: 'Representar eletricamente uma grandeza física para '
        'processamento no sistema.',
    confusables: ['grandezas físicas', 'atuadores', 'processamento do sinal'],
    hint: 'Pense em como algo do mundo real vira algo que um circuito '
        'consegue interpretar.',
  ),
  'grandezas físicas': const _ConceptFact(
    statement: 'Propriedades físicas mensuráveis, como temperatura, '
        'pressão ou movimento.',
    confusables: ['sinais elétricos', 'sensores', 'instrumentos de medição'],
    hint: 'Pense em características do mundo real que existem antes de '
        'qualquer conversão eletrônica.',
  ),
  'instrumentos de medição': const _ConceptFact(
    statement: 'Fornecer ao usuário a indicação do valor da grandeza '
        'medida.',
    confusables: ['sensores', 'atuadores', 'aquisição de sinais'],
    hint: 'Pense em quem mostra ao usuário final o resultado, depois de '
        'todo o processo interno.',
  ),
  'instrumento de medição': const _ConceptFact(
    statement: 'Fornecer ao usuário a indicação do valor da grandeza '
        'medida.',
    confusables: ['sensores', 'atuadores', 'aquisição de sinais'],
    hint: 'Pense em quem mostra ao usuário final o resultado, depois de '
        'todo o processo interno.',
  ),
  'aquisição de sinais': const _ConceptFact(
    statement: 'Captar e converter sinais do ambiente para processamento '
        'posterior.',
    confusables: [
      'processamento do sinal',
      'instrumentos de medição',
      'atuadores',
    ],
    hint: 'Pense na primeira etapa, antes de qualquer tratamento, onde '
        'algo é recolhido do ambiente.',
  ),
  'processamento do sinal': const _ConceptFact(
    statement: 'Tratar o sinal obtido do sensor antes de gerar uma saída '
        'útil.',
    confusables: ['aquisição de sinais', 'atuadores', 'sensores'],
    hint: 'Pense na etapa intermediária, entre captar a informação e agir '
        'com base nela.',
  ),
  'processamento de sinal': const _ConceptFact(
    statement: 'Tratar o sinal obtido do sensor antes de gerar uma saída '
        'útil.',
    confusables: ['aquisição de sinais', 'atuadores', 'sensores'],
    hint: 'Pense na etapa intermediária, entre captar a informação e agir '
        'com base nela.',
  ),
  'malha aberta': const _ConceptFact(
    statement: 'Não realimentar o sinal de saída para controle automático '
        'do sistema.',
    confusables: ['malha fechada', 'sistema de medição', 'atuadores'],
    hint: 'Pense em um processo que segue em frente sem checar o próprio '
        'resultado.',
  ),
  'malha fechada': const _ConceptFact(
    statement: 'Realimentar o sinal de saída para permitir controle '
        'automático do sistema.',
    confusables: ['malha aberta', 'sistema de medição', 'atuadores'],
    hint: 'Pense em um processo que observa o próprio resultado para se '
        'corrigir sozinho.',
  ),
};

/// Extrai palavras de 4+ letras (com acentos) de um texto livre, em
/// minúsculas — a unidade básica usada para contar frequência em
/// [extractKeyTerms].
List<String> splitIntoWords(String text) {
  return RegExp(
    r'[A-Za-zÀ-ÿ]{4,}',
  ).allMatches(text).map((m) => m.group(0)!.toLowerCase()).toList();
}

/// Quebra um texto livre em frases (heurística simples por pontuação),
/// mantendo só as de tamanho "razoável" para virar uma alternativa de quiz
/// legível (nem uma palavra solta, nem um parágrafo inteiro).
List<String> splitIntoSentences(String text) {
  final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty) return [];
  return normalized
      .split(RegExp(r'(?<=[.!?])\s+'))
      .map((s) => s.trim())
      .where((s) => s.length >= 25 && s.length <= 220)
      .toList();
}

/// Termos que aparecem mais de uma vez no texto (ignorando
/// [kQuizStopWords]), do mais para o menos frequente — a heurística usada
/// para decidir quais "conceitos" o quiz pergunta, sem IA externa.
List<String> extractKeyTerms(String text, {int maxTerms = 10}) {
  final counts = <String, int>{};
  for (final word in splitIntoWords(text)) {
    if (kQuizStopWords.contains(word)) continue;
    counts[word] = (counts[word] ?? 0) + 1;
  }
  final recurring = counts.entries.where((e) => e.value > 1).toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return recurring.take(maxTerms).map((e) => e.key).toList();
}

/// Termos que NUNCA podem ser o conceito PRINCIPAL de uma pergunta
/// sozinhos: mesmo aparecendo bastante no texto, são genéricos demais para
/// virar uma pergunta clara por si só — "o que caracteriza 'Sistemas'?" não
/// faz sentido porque "sistemas" não é um conceito fechado (bug relatado
/// testando com o PDF real). Continuam podendo aparecer DENTRO de um
/// conceito composto (ex.: "sinais elétricos", "sistema de medição") — ver
/// [extractQuizConcepts].
const Set<String> kQuizBannedSoloConcepts = {
  'sistema', 'sistemas', 'medição', 'sinal', 'sinais', 'valor', 'valores',
  'instrumento', 'instrumentos', 'tema', 'figura', 'tabela', 'fonte',
  'segundo', 'capítulo', 'aula', 'conteúdo', 'material', 'exemplo',
  'objetivo', 'informação', 'informações',
};

/// Exceção à lista acima: termos técnicos de uma palavra só que MESMO
/// ASSIM são conceitos claros o bastante para virar pergunta sozinhos.
const Set<String> kQuizAllowedSoloTechnicalTerms = {
  'sensor', 'sensores', 'atuador', 'atuadores', 'transdutor', 'transdutores',
};

/// Forma canônica (plural) de cada termo técnico permitido — singular e
/// plural contam para o MESMO conceito em [extractQuizConcepts] (ex.:
/// "sensor" citado 6x + "sensores" citado 3x viram um só conceito
/// "sensores" com peso 9, não dois conceitos fragmentados com peso menor
/// cada), para esses termos concorrerem de forma justa com os conceitos
/// compostos na hora de escolher os 3 usados no quiz.
const Map<String, String> _kSoloConceptCanonical = {
  'sensor': 'sensores',
  'sensores': 'sensores',
  'atuador': 'atuadores',
  'atuadores': 'atuadores',
  'transdutor': 'transdutores',
  'transdutores': 'transdutores',
};

/// Conceitos compostos conhecidos do domínio deste material
/// (instrumentação/eletrônica) — checados como substring do texto (conta
/// mesmo aparecendo só 1x, diferente da detecção genérica de
/// [extractQuizConcepts] que exige recorrência) para não depender só da
/// heurística genérica em materiais mais curtos.
const List<String> kQuizKnownCompoundConcepts = [
  'sistema de medição',
  'sistemas de medição',
  'grandezas físicas',
  'sinais elétricos',
  'aquisição de sinais',
  'instrumentos de medição',
  'processamento do sinal',
  'processamento de sinal',
  'medição de temperatura',
  'medição de pressão',
  'medição de movimento',
  'malha aberta',
  'malha fechada',
];

int _countOccurrences(String haystack, String needle) {
  if (needle.isEmpty) return 0;
  var count = 0;
  var index = haystack.indexOf(needle);
  while (index != -1) {
    count++;
    index = haystack.indexOf(needle, index + needle.length);
  }
  return count;
}

final RegExp _kQuizDePattern = RegExp(
  r'\b([a-zà-ÿ]{4,})\s+(de|do|da)\s+([a-zà-ÿ]{4,})\b',
);
final RegExp _kQuizTitleCasePairPattern = RegExp(
  r'\b([A-ZÀ-Ý][a-zà-ÿ]{3,})\s+([A-ZÀ-Ý][a-zà-ÿ]{3,})\b',
);

/// Extrai os conceitos candidatos a virar pergunta de quiz — nunca uma
/// palavra genérica isolada (ver [kQuizBannedSoloConcepts]), priorizando
/// conceitos compostos e técnicos de verdade, que são sempre mais claros
/// como "o que caracteriza X?" do que uma palavra solta.
///
/// Três fontes combinadas e ordenadas por relevância:
/// 1. Conceitos compostos conhecidos do domínio
///    ([kQuizKnownCompoundConcepts]) presentes no texto (basta 1x).
/// 2. Padrão genérico "palavra DE/DO/DA palavra" (ex.: "sistema de
///    medição") e pares de palavras adjacentes com Inicial Maiúscula (ex.:
///    "Revolução Industrial") que SE REPETEM no texto (2+ vezes) — para
///    generalizar a detecção de conceitos compostos além da lista acima,
///    em qualquer material, não só neste PDF específico.
/// 3. Palavras únicas recorrentes que são termos técnicos permitidos mesmo
///    sozinhos (ver [kQuizAllowedSoloTechnicalTerms]).
List<String> extractQuizConcepts(String text, {int maxConcepts = 10}) {
  final lower = text.toLowerCase();
  final scores = <String, int>{};

  for (final phrase in kQuizKnownCompoundConcepts) {
    final count = _countOccurrences(lower, phrase);
    if (count > 0) scores[phrase] = (scores[phrase] ?? 0) + count * 5;
  }

  final dePhraseCounts = <String, int>{};
  for (final m in _kQuizDePattern.allMatches(lower)) {
    final w1 = m.group(1)!;
    final prep = m.group(2)!;
    final w2 = m.group(3)!;
    if (kQuizStopWords.contains(w1) || kQuizStopWords.contains(w2)) continue;
    // Palavras banidas como conceito solto (ex.: "segundo", "fonte") não
    // podem participar de um composto genérico detectado aqui — sem esse
    // filtro, ruído de citação bibliográfica tipo "Segundo Aguirre (2013)"
    // ou "Fonte: Adaptado de..." vazava como se fosse um conceito técnico
    // ("segundo aguirre", "fonte de referência").
    if (kQuizBannedSoloConcepts.contains(w1) ||
        kQuizBannedSoloConcepts.contains(w2)) {
      continue;
    }
    final phrase = '$w1 $prep $w2';
    dePhraseCounts[phrase] = (dePhraseCounts[phrase] ?? 0) + 1;
  }
  for (final entry in dePhraseCounts.entries) {
    if (entry.value >= 2) {
      scores[entry.key] = (scores[entry.key] ?? 0) + entry.value * 3;
    }
  }

  final titleCaseCounts = <String, int>{};
  for (final m in _kQuizTitleCasePairPattern.allMatches(text)) {
    final w1 = m.group(1)!.toLowerCase();
    final w2 = m.group(2)!.toLowerCase();
    if (kQuizStopWords.contains(w1) || kQuizStopWords.contains(w2)) continue;
    if (kQuizBannedSoloConcepts.contains(w1) ||
        kQuizBannedSoloConcepts.contains(w2)) {
      continue;
    }
    final phrase = '$w1 $w2';
    titleCaseCounts[phrase] = (titleCaseCounts[phrase] ?? 0) + 1;
  }
  for (final entry in titleCaseCounts.entries) {
    if (entry.value >= 2) {
      scores[entry.key] = (scores[entry.key] ?? 0) + entry.value * 3;
    }
  }

  for (final word in splitIntoWords(text)) {
    if (kQuizBannedSoloConcepts.contains(word)) continue;
    final canonical = _kSoloConceptCanonical[word];
    if (canonical == null) continue;
    scores[canonical] = (scores[canonical] ?? 0) + 2;
  }

  final ranked = scores.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return ranked.take(maxConcepts).map((e) => e.key).toList();
}

final RegExp _kQuizLeadingSectionNumber = RegExp(r'^\d+(\.\d+)*\s*');
final RegExp _kQuizLeadingCitation = RegExp(
  r'^.*?\bSegundo\s+[^,(]+\(\d{4}\),?\s*',
  caseSensitive: false,
);
final RegExp _kQuizCaptionOrSourcePattern = RegExp(
  r'^\s*(Figura|Tabela|Quadro|Gr[áa]fico|Fonte)\b',
  caseSensitive: false,
);
final RegExp _kQuizEllipsisPattern = RegExp(r'\[\s*(\.\.\.|…)\s*\]');
final RegExp _kQuizLeadingDigit = RegExp(r'^\d');

/// Remove ruído comum de PDF acadêmico do INÍCIO de uma frase (nunca do
/// meio/fim, para não arriscar mudar o sentido): numeração de seção solta
/// (ex.: "1.2 ") e um prefixo de citação bibliográfica (ex.: "Sistemas de
/// medição Segundo Aguirre (2013), "). Nunca inventa texto novo — só corta
/// o prefixo ruidoso, mantendo o restante como está no PDF.
String? _cleanSentenceForQuiz(String rawSentence) {
  var s = rawSentence.trim();
  s = s.replaceFirst(_kQuizLeadingSectionNumber, '');
  final citationMatch = _kQuizLeadingCitation.firstMatch(s);
  if (citationMatch != null) {
    s = s.substring(citationMatch.end);
  }
  s = s.trim();
  if (s.isEmpty) return null;
  return _capitalizeFirst(s);
}

/// Critério de qualidade para uma frase virar RESPOSTA de quiz: tamanho
/// legível (nem fragmento, nem parágrafo), sem reticências de corte
/// ("[...]"), e não é legenda/fonte bibliográfica nem começa com número —
/// sem isso, frases tipo "1.2 Sistemas..." ou "Figura 3 – ..." acabavam
/// virando alternativa de resposta sem fazer sentido isoladas.
bool _isQualityAnswerSentence(String s) {
  if (s.length < 40 || s.length > 180) return false;
  if (_kQuizEllipsisPattern.hasMatch(s)) return false;
  if (_kQuizCaptionOrSourcePattern.hasMatch(s)) return false;
  if (_kQuizLeadingDigit.hasMatch(s)) return false;
  return true;
}

/// Frases do texto já limpas ([_cleanSentenceForQuiz]) e filtradas por
/// qualidade ([_isQualityAnswerSentence]) — a única fonte de "resposta
/// certa" usada por [_buildConceptQuestion]/[_buildSentenceQuestion], para
/// nunca virar pergunta a partir de um trecho sem sentido ou incompleto.
List<String> _qualityAnswerSentences(String text) {
  final result = <String>[];
  for (final raw in splitIntoSentences(text)) {
    final cleaned = _cleanSentenceForQuiz(raw);
    if (cleaned != null && _isQualityAnswerSentence(cleaned)) {
      result.add(cleaned);
    }
  }
  return result;
}

String _capitalizeFirst(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

List<String> _pickDistractorTerms(String correctTerm, List<String> allTerms) {
  final pool = <String>[];
  for (final t in allTerms) {
    if (t != correctTerm && !pool.contains(t)) pool.add(t);
  }
  for (final t in kQuizGenericDistractorTerms) {
    if (t != correctTerm && !pool.contains(t)) pool.add(t);
  }
  return pool.take(3).toList();
}

QuizQuestion _buildTermQuestion({
  required String term,
  required List<String> allTerms,
  required String materialTitle,
}) {
  final correctOption = _capitalizeFirst(term);
  final distractors = _pickDistractorTerms(
    term,
    allTerms,
  ).map(_capitalizeFirst).toList();
  while (distractors.length < 3) {
    distractors.add('Nenhuma das alternativas anteriores');
  }
  final options = [correctOption, ...distractors]..shuffle();
  return QuizQuestion(
    category: materialTitle,
    question: 'Qual destes termos é um conceito citado no material '
        '"$materialTitle"?',
    options: options,
    correct: options.indexOf(correctOption),
    tip: 'Releia o material: palavras que se repetem costumam indicar os '
        'conceitos centrais do conteúdo.',
    term: term,
  );
}

/// Variações de formulação para a pergunta de conceito (ver
/// [_buildConceptQuestion]) — alternadas por índice para não repetir
/// sempre o mesmo template, todas neutras quanto a singular/plural (o
/// conceito pode ser "sensores" ou "sistema de medição").
final List<String Function(String materialTitle, String concept)>
_kConceptQuestionTemplates = [
  (materialTitle, concept) =>
      'De acordo com o material "$materialTitle", qual é a função de '
      '"$concept"?',
  (materialTitle, concept) =>
      'Segundo o material "$materialTitle", o que caracteriza "$concept"?',
  (materialTitle, concept) =>
      'Qual alternativa descreve corretamente "$concept" no material '
      '"$materialTitle"?',
  (materialTitle, concept) =>
      'No conteúdo de "$materialTitle", qual destas frases explica '
      '"$concept"?',
];

/// Dica genérica usada sempre que [_safeHintFor] rejeita a dica curada de
/// um conceito (ver regra 9 do pedido) — nunca revela nem sugere a
/// resposta, só orienta o aluno a comparar as alternativas com atenção.
const String _kGenericSafeHint =
    'Leia a pergunta com atenção e compare a função de cada componente '
    'citado nas alternativas.';

/// Extrai as palavras de conteúdo (4+ letras, ignorando conectores) de uma
/// frase, em minúsculas — usado só para medir sobreposição entre uma dica
/// e a resposta certa em [_safeHintFor], não para extração de conceitos.
Set<String> _contentWordSet(String text) {
  return RegExp(r'[a-zà-ÿ]{4,}')
      .allMatches(text.toLowerCase())
      .map((m) => m.group(0)!)
      .where((w) => !kQuizStopWords.contains(w))
      .toSet();
}

/// Valida que [hint] não entrega a resposta certa ([correctAnswer]) antes
/// de virar a dica exibida na pergunta: rejeita (e devolve
/// [_kGenericSafeHint] no lugar) se a dica contém a resposta certa como
/// substring, ou se mais de metade das palavras de conteúdo da resposta
/// aparece literalmente na dica — mesmo uma dica escrita para "orientar o
/// raciocínio" pode acabar repetindo palavras-chave decisivas por acidente,
/// então essa checagem roda sempre, não só quando se "acha" arriscado.
String _safeHintFor(String hint, String correctAnswer) {
  final lowerHint = hint.toLowerCase();
  final lowerAnswer = correctAnswer.toLowerCase();
  if (lowerHint.contains(lowerAnswer)) return _kGenericSafeHint;

  final answerWords = _contentWordSet(correctAnswer);
  if (answerWords.isEmpty) return hint;
  final hintWords = _contentWordSet(hint);
  final shared = answerWords.where(hintWords.contains).length;
  if (shared / answerWords.length > 0.5) return _kGenericSafeHint;

  return hint;
}

/// Pergunta sobre um conceito (composto ou técnico — nunca uma palavra
/// genérica isolada, ver [extractQuizConcepts]) cuja resposta certa é um
/// fato curto e didático sobre o conceito (ver [_kConceptFacts]) — curto,
/// limpo e do mesmo tamanho dos distratores, nunca uma citação literal
/// longa do PDF (o que deixava a resposta certa óbvia só pelo tamanho/
/// estilo). Só monta a pergunta quando o conceito está na base de fatos
/// ([_kConceptFacts]); sem isso cai para [_buildTermQuestion] (reconhecer
/// o termo solto). As alternativas erradas vêm dos fatos de conceitos
/// CONFUNDÍVEIS (ver [_ConceptFact.confusables] — trocar sensor por
/// atuador, entrada por saída etc.) — plausíveis porque pertencem ao mesmo
/// campo conceitual, mas conceitualmente erradas para ESTE conceito
/// específico. Nunca usa frases evasivas tipo "não aparece no material".
QuizQuestion? _buildConceptQuestion({
  required String concept,
  required List<String> allConcepts,
  required String materialTitle,
  required int templateIndex,
}) {
  final fact = _kConceptFacts[concept];
  if (fact == null) return null;
  final correct = fact.statement;

  final distractors = <String>[];
  for (final confusable in fact.confusables) {
    if (distractors.length == 3) break;
    final confusableFact = _kConceptFacts[confusable];
    if (confusableFact != null &&
        confusableFact.statement != correct &&
        !distractors.contains(confusableFact.statement)) {
      distractors.add(confusableFact.statement);
    }
  }
  // Completa com fatos de OUTROS conceitos presentes neste material, se os
  // confundíveis pré-definidos não bastarem.
  for (final other in allConcepts) {
    if (distractors.length == 3) break;
    if (other == concept) continue;
    final otherFact = _kConceptFacts[other];
    if (otherFact != null &&
        otherFact.statement != correct &&
        !distractors.contains(otherFact.statement)) {
      distractors.add(otherFact.statement);
    }
  }
  // Último recurso: qualquer fato conhecido do domínio ainda não usado —
  // nunca uma frase evasiva, sempre outro fato técnico real.
  final allStatements = _kConceptFacts.values.map((f) => f.statement);
  for (final statement in allStatements) {
    if (distractors.length == 3) break;
    if (statement == correct || distractors.contains(statement)) continue;
    distractors.add(statement);
  }

  final options = [correct, ...distractors]..shuffle();
  final conceptDisplay = _capitalizeFirst(concept);
  final template =
      _kConceptQuestionTemplates[templateIndex %
          _kConceptQuestionTemplates.length];
  return QuizQuestion(
    category: materialTitle,
    question: template(materialTitle, conceptDisplay),
    options: options,
    correct: options.indexOf(correct),
    tip: _safeHintFor(fact.hint, correct),
    term: concept,
  );
}

/// Reserva de última instância, usada só quando o material tem frases de
/// qualidade mas nenhum conceito coberto por [_kConceptFacts] — reconhecer
/// qual alternativa é uma frase real do material, com os distratores vindo
/// de fatos do domínio (nunca frases evasivas tipo "não aparece no
/// material"), escolhidos pelos de tamanho MAIS PARECIDO com a frase certa
/// — sem isso, uma frase real de ~170 caracteres ao lado de fatos curados
/// de ~70 caracteres denunciaria a certa só pelo tamanho.
QuizQuestion _buildSentenceQuestion({
  required String sentence,
  required String materialTitle,
}) {
  final candidates = _kConceptFacts.values
      .map((f) => f.statement)
      .where((s) => s != sentence)
      .toSet()
      .toList()
    ..sort(
      (a, b) => (a.length - sentence.length).abs().compareTo(
        (b.length - sentence.length).abs(),
      ),
    );
  final distractors = candidates.take(3).toList();
  final options = [sentence, ...distractors]..shuffle();
  return QuizQuestion(
    category: materialTitle,
    question: 'Qual alternativa representa uma informação presente no '
        'conteúdo de "$materialTitle"?',
    options: options,
    correct: options.indexOf(sentence),
    tip: 'Esta frase foi retirada diretamente do texto original do '
        'material.',
  );
}

/// Gera até [questionCount] perguntas de múltipla escolha a partir do texto
/// extraído de um material (heurística simples, sem IA externa): identifica
/// conceitos compostos/técnicos claros (ver [extractQuizConcepts] — nunca
/// uma palavra genérica isolada tipo "Sistemas"/"Medição", ver
/// [kQuizBannedSoloConcepts]) e tenta, para cada um, montar uma pergunta
/// cuja resposta certa é um fato curto e didático sobre aquele conceito
/// (ver [_buildConceptQuestion]/[_kConceptFacts]) — bem mais específico do
/// que só pedir para reconhecer a palavra solta, e com distratores por
/// confusão conceitual (nunca frases evasivas tipo "não aparece no
/// material"). Só cai para [_buildTermQuestion] (o conceito solto) quando
/// o conceito não está coberto pela base de fatos. Completa com
/// [_buildSentenceQuestion] ("qual frase é real") quando sobrarem menos
/// conceitos utilizáveis do que [questionCount].
///
/// Devolve MENOS que [questionCount] (até lista vazia) quando o material
/// não tem conceitos/frases de qualidade suficientes — nunca preenche com
/// uma pergunta ruim só para completar a contagem; o chamador ([QuizScreen])
/// mostra uma mensagem apropriada nesse caso, em vez de um quiz fraco.
List<QuizQuestion> generateQuizFromText({
  required String text,
  required String materialTitle,
  int questionCount = 3,
}) {
  final concepts = extractQuizConcepts(text);
  final sentences = _qualityAnswerSentences(text);
  if (concepts.isEmpty && sentences.isEmpty) return [];

  final questions = <QuizQuestion>[];
  final usedSentences = <String>{};
  final usedConcepts = <String>{};

  // 1ª prioridade: uma pergunta de conceito (com fato curto e didático
  // sobre o conceito) por conceito, na ordem de relevância.
  for (final concept in concepts) {
    if (questions.length >= questionCount) break;
    final question = _buildConceptQuestion(
      concept: concept,
      allConcepts: concepts,
      materialTitle: materialTitle,
      templateIndex: questions.length,
    );
    if (question == null) continue;
    final correctSentence = question.options[question.correct];
    if (usedSentences.contains(correctSentence)) continue;
    usedSentences.add(correctSentence);
    usedConcepts.add(concept);
    questions.add(question);
  }

  // 2ª prioridade: conceitos sem frase explicativa (não entraram na etapa
  // acima) caem para "qual termo é um conceito citado", até completar
  // questionCount.
  for (
    var i = 0;
    i < concepts.length && questions.length < questionCount;
    i++
  ) {
    final concept = concepts[i];
    if (usedConcepts.contains(concept)) continue;
    usedConcepts.add(concept);
    questions.add(
      _buildTermQuestion(
        term: concept,
        allTerms: concepts,
        materialTitle: materialTitle,
      ),
    );
  }

  // 3ª prioridade: se ainda faltar (poucos conceitos utilizáveis, mas há
  // frases de qualidade), completa com "qual frase é real" usando frases
  // ainda não aproveitadas como resposta certa de nenhuma pergunta
  // anterior. Se mesmo assim faltar, a lista fica com menos que
  // questionCount (ver regra de não preencher com pergunta ruim).
  var sentenceIndex = sentences.isEmpty ? 0 : sentences.length ~/ 2;
  var attempts = 0;
  while (questions.length < questionCount &&
      sentences.isNotEmpty &&
      attempts < sentences.length * 2) {
    final sentence = sentences[sentenceIndex % sentences.length];
    sentenceIndex++;
    attempts++;
    if (usedSentences.contains(sentence) && usedSentences.length < sentences.length) {
      continue;
    }
    usedSentences.add(sentence);
    questions.add(
      _buildSentenceQuestion(sentence: sentence, materialTitle: materialTitle),
    );
  }

  return questions;
}

/// Deriva um "tema" de exibição para o quiz a partir do nome do arquivo:
/// remove a extensão e um prefixo genérico do tipo "Aula 1 -", sobrando só a
/// parte que de fato identifica o assunto (ex.: "Instrumentação
/// Eletrônica.pdf" -> "Instrumentação Eletrônica"). Se não sobrar nada
/// depois de remover o prefixo genérico (ex.: "AULA 1.pdf", onde não há
/// nenhum tema real no nome), mantém o nome original completo em vez de
/// devolver uma string vazia. Usado como categoria/título do quiz — o
/// CONTEÚDO das perguntas vem sempre do texto base do material (resumo
/// digitado pelo usuário ou texto extraído do PDF), nunca do nome do
/// arquivo sozinho (ver [_QuizScreenState._prepare]).
String detectMaterialTheme(String fileName) {
  var name = fileName;
  if (name.toLowerCase().endsWith('.pdf')) {
    name = name.substring(0, name.length - 4);
  }
  final stripped = name
      .replaceFirst(
        RegExp(r'^\s*aula\s*\d*\s*[-:–]?\s*', caseSensitive: false),
        '',
      )
      .trim();
  return stripped.isNotEmpty ? stripped : fileName;
}

class QuizScreen extends StatefulWidget {
  /// Material do qual o quiz deve ser gerado. `null` quando a tela é aberta
  /// pela aba inferior/atalho da Home (sem um PDF específico escolhido) —
  /// nesse caso [_QuizScreenState] usa o material mais recente do usuário.
  final StudyMaterial? material;

  const QuizScreen({this.material, super.key});
  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  bool _loading = true;
  StudyMaterial? _resolvedMaterial;
  List<QuizQuestion> _questions = [];

  // Responder JÁ marca a alternativa e revela certo/errado na hora (ver
  // [_select]) — diferente do modelo "escolhe e só confirma o acerto no
  // fim" — porque a entrega final precisa demonstrar feedback imediato.
  // Uma vez respondida, a pergunta trava (novos toques em [_select] são
  // ignorados) até "Próxima pergunta"/"Ver resultado".
  int _index = 0;
  int _score = 0;
  int? _selected;

  // Termos reais (ver [QuizQuestion.term]) das perguntas que o usuário
  // acertou/errou, acumulados pergunta a pergunta em [_select] — usados
  // para montar "Pontos fortes"/"O que revisar" em [PerformanceScreen] com
  // base no que foi de fato respondido sobre o material, em vez de tags
  // fixas sem relação com o PDF.
  final List<String> _correctTerms = [];
  final List<String> _reviewTerms = [];

  /// `true` quando havia texto base (resumo ou extração do PDF) mas
  /// [generateQuizFromText] não achou conceitos/frases de qualidade o
  /// bastante para montar nenhuma pergunta — usado em [_buildEmptyState]
  /// para mostrar uma mensagem diferente de "não há material nenhum".
  bool _hadBaseTextButNoQuestions = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  /// Resolve QUAL material usar (o recebido, ou o mais recente do usuário
  /// se nenhum foi passado) e gera as perguntas a partir do TEXTO BASE do
  /// material (ver [_effectiveBaseText]) com [generateQuizFromText] — nunca
  /// a partir só do nome do arquivo, e nunca com perguntas genéricas de
  /// técnica de estudo. Devolve lista vazia (a tela mostra a mensagem
  /// correspondente) tanto quando não há material nenhum quanto quando há
  /// material mas nenhum texto base (nem resumo digitado, nem extração do
  /// PDF) para gerar as perguntas.
  Future<void> _prepare() async {
    var material = widget.material;
    if (material == null) {
      final email = currentAccount.value?.email;
      if (email != null) {
        final materials = await LocalStore.loadMaterials(email);
        if (materials.isNotEmpty) material = materials.last;
      }
    }
    var questions = <QuizQuestion>[];
    var hadBaseText = false;
    if (material != null) {
      final baseText = _effectiveBaseText(material);
      if (baseText != null) {
        hadBaseText = true;
        questions = generateQuizFromText(
          text: baseText,
          materialTitle: detectMaterialTheme(material.fileName),
        );
      }
    }
    if (!mounted) return;
    setState(() {
      _resolvedMaterial = material;
      _questions = questions;
      _hadBaseTextButNoQuestions = hadBaseText && questions.isEmpty;
      _loading = false;
    });
  }

  /// O texto usado para gerar o quiz: o resumo/texto base que o usuário
  /// digitou (ver "Adicionar resumo"/"Editar texto base" em
  /// [_MaterialListCard]) tem prioridade — é mais confiável do que a
  /// extração automática e é o caminho recomendado para a demonstração.
  /// Só cai para o texto extraído do PDF ([StudyMaterial.extractedText]) se
  /// não houver resumo. Devolve `null` se nenhum dos dois existir.
  String? _effectiveBaseText(StudyMaterial material) {
    final summary = material.userSummary?.trim();
    if (summary != null && summary.isNotEmpty) return summary;
    final extracted = material.extractedText.trim();
    if (extracted.isNotEmpty) return extracted;
    return null;
  }

  void _select(int optionIndex) {
    if (_selected != null) return; // já respondida: ignora novos toques.
    setState(() {
      _selected = optionIndex;
      final term = _questions[_index].term;
      final isCorrect = optionIndex == _questions[_index].correct;
      if (isCorrect) _score++;
      if (term.isNotEmpty) {
        final label = _capitalizeFirst(term);
        if (isCorrect) {
          if (!_correctTerms.contains(label)) _correctTerms.add(label);
        } else {
          if (!_reviewTerms.contains(label)) _reviewTerms.add(label);
        }
      }
    });
  }

  void _next() {
    final selected = _selected;
    if (selected == null) return;

    if (_index < _questions.length - 1) {
      setState(() {
        _index++;
        _selected = null;
      });
      return;
    }
    final feedback = _score / _questions.length * 100 >= 80
        ? 'Excelente!'
        : _score / _questions.length * 100 >= 50
        ? 'Bom, revise alguns pontos.'
        : 'Releia o material e tente novamente.';
    _persistQuizProgress();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => PerformanceScreen(
          acertos: _score,
          erros: _questions.length - _score,
          feedback: feedback,
          material: _resolvedMaterial,
          strengths: _correctTerms,
          reviewTopics: _reviewTerms,
        ),
      ),
    );
  }

  /// Updates the demo per-user stats (quizzes concluídos/acertos) shown on
  /// Início e Perfil. Fire-and-forget: doesn't block navigating to feedback.
  Future<void> _persistQuizProgress() async {
    final email = currentAccount.value?.email;
    if (email == null) return;
    final updated = currentProgress.value.copyWith(
      quizzesCompleted: currentProgress.value.quizzesCompleted + 1,
      acertosTotal: currentProgress.value.acertosTotal + _score,
    );
    currentProgress.value = updated;
    await LocalStore.saveProgress(email, updated);
  }

  Widget _buildHeaderRow() {
    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(
            LucideIcons.arrowLeft,
            color: AppColors.primary,
            size: 24,
          ),
        ),
        const Expanded(
          child: Text(
            'Quiz interativo',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w900,
              color: AppColors.primary,
              decoration: TextDecoration.none,
            ),
          ),
        ),
        IconButton(
          onPressed: () {},
          icon: const Icon(
            LucideIcons.bookmark,
            color: AppColors.secondary,
            size: 24,
          ),
        ),
      ],
    );
  }

  /// Estado exibido quando não há material nenhum (nem passado, nem
  /// nenhum carregado pelo usuário) ou quando o texto extraído não deu
  /// termos/frases suficientes para montar um quiz — nunca uma tela
  /// vermelha, sempre essa mensagem amigável com um jeito de voltar.
  Widget _buildEmptyState({required String message}) {
    return _PageList(
      children: [
        _buildHeaderRow(),
        const SizedBox(height: 40),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  LucideIcons.fileQuestion,
                  size: 48,
                  color: AppColors.mutedText,
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.mutedText,
                    height: 1.4,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 20),
                PrimaryButton(
                  label: 'Ir para Material de estudo',
                  onPressed: () {
                    mainShellTabIndex.value = 1;
                    Navigator.popUntil(context, (route) => route.isFirst);
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Indicador à esquerda de cada alternativa: um círculo neutro antes de
  /// responder; depois de respondida (ver [_select]), vira um check verde
  /// na alternativa certa ou um X vermelho na errada que foi escolhida —
  /// esse é o "feedback imediato" pedido, sem esperar o resultado final.
  Widget _buildOptionIndicator({
    required bool answered,
    required bool isSelected,
    required bool isCorrect,
  }) {
    if (answered && isCorrect) {
      return _buildFilledIndicator(
        color: const Color(0xFF2EAD68),
        icon: LucideIcons.check,
      );
    }
    if (answered && isSelected && !isCorrect) {
      return _buildFilledIndicator(color: Colors.redAccent, icon: LucideIcons.x);
    }
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.transparent,
        border: Border.all(color: AppColors.lightBlue, width: 2),
      ),
    );
  }

  Widget _buildFilledIndicator({required Color color, required IconData icon}) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      alignment: Alignment.center,
      child: Icon(icon, size: 14, color: Colors.white),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return _PageList(
        children: [
          _buildHeaderRow(),
          const SizedBox(height: 80),
          const Center(child: CircularProgressIndicator()),
        ],
      );
    }
    if (_resolvedMaterial == null) {
      return _buildEmptyState(
        message: 'Nenhum material carregado. Carregue um PDF em "Material '
            'de estudo" para gerar um quiz.',
      );
    }
    if (_questions.isEmpty) {
      return _buildEmptyState(
        message: _hadBaseTextButNoQuestions
            ? 'Não foi possível gerar perguntas suficientes com qualidade '
                  'a partir deste material.'
            : 'Adicione um resumo do material para gerar o quiz deste '
                  'PDF.',
      );
    }
    final q = _questions[_index];
    final isLastQuestion = _index == _questions.length - 1;
    final resolvedMaterial = _resolvedMaterial;
    final materialTitle = resolvedMaterial == null
        ? ''
        : detectMaterialTheme(resolvedMaterial.fileName);
    return _PageList(
      children: [
        _buildHeaderRow(),
        const SizedBox(height: 6),
        Text(
          'Quiz gerado para: $materialTitle',
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.secondary,
            decoration: TextDecoration.none,
          ),
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'Pergunta ${_index + 1} de ${_questions.length}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(LucideIcons.star, color: AppColors.accent),
                  const SizedBox(width: 5),
                  Text(
                    '$_score pts',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: LinearProgressIndicator(
            value: (_index + 1) / _questions.length,
            minHeight: 7,
            backgroundColor: const Color(0xFFE8EEF6),
            valueColor: const AlwaysStoppedAnimation(AppColors.secondary),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          decoration: kCardDecoration,
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                q.category,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.secondary,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                q.question,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: AppColors.primary,
                  height: 1.25,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Escolha a alternativa que melhor responde à pergunta.',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                  color: AppColors.mutedText,
                  height: 1.4,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 14),
              ...List.generate(q.options.length, (i) {
                final answered = _selected != null;
                final isSelected = _selected == i;
                final isCorrect = i == q.correct;

                var background = Colors.white;
                var borderColor = AppColors.border;
                var borderWidth = 1.0;
                var textColor = AppColors.primary;
                if (answered && isCorrect) {
                  background = const Color(0xFFE9F7EF);
                  borderColor = const Color(0xFF61C98B);
                  borderWidth = 2;
                  textColor = const Color(0xFF1E7A46);
                } else if (answered && isSelected) {
                  background = const Color(0xFFFFE7E7);
                  borderColor = Colors.redAccent;
                  borderWidth = 2;
                  textColor = const Color(0xFFB3261E);
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Material(
                    color: background,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      onTap: answered ? null : () => _select(i),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: borderColor,
                            width: borderWidth,
                          ),
                        ),
                        child: Row(
                          children: [
                            _buildOptionIndicator(
                              answered: answered,
                              isSelected: isSelected,
                              isCorrect: isCorrect,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                q.options[i],
                                style: TextStyle(
                                  fontSize: 15,
                                  color: textColor,
                                  height: 1.35,
                                  fontWeight: FontWeight.w600,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
              _InfoBanner(
                icon: LucideIcons.lightbulb,
                title: 'Dica',
                text: q.tip,
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                label: isLastQuestion ? 'Ver resultado' : 'Próxima pergunta',
                icon: LucideIcons.arrowRight,
                onPressed: _selected != null ? _next : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Área "hero" no topo da tela "Feedback do quiz": o troféu (que já traz
/// nuvens/confete desenhados na própria imagem, ver [kTrophyAsset]) bem
/// grande e centralizado, com círculos decorativos ao redor NA MARGEM da
/// página (não atrás da imagem) — a própria imagem já tem um fundo
/// claro/branco desenhado nela, então colocar um cartão colorido atrás
/// criava uma "moldura dupla" visível; deixando os círculos só nas bordas
/// da área, a composição fica mais parecida com a referência aprovada
/// (ilustração ocupando o topo, sem parecer um ícone pequeno solto).
class _HeroTrophyBanner extends StatelessWidget {
  const _HeroTrophyBanner();

  static const double _imageHeight = 260;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _imageHeight,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          const Align(
            alignment: Alignment(-1.05, -0.7),
            child: _DecorativeCircle(
              size: 40,
              color: AppColors.lightBlue,
              opacity: 0.55,
            ),
          ),
          const Align(
            alignment: Alignment(1.1, 0.75),
            child: _DecorativeCircle(
              size: 52,
              color: AppColors.accent,
              opacity: 0.5,
            ),
          ),
          const Align(
            alignment: Alignment(0.95, -0.85),
            child: _DecorativeCircle(
              size: 22,
              color: AppColors.secondary,
              opacity: 0.4,
            ),
          ),
          const Image(
            image: AssetImage(kTrophyAsset),
            height: _imageHeight,
            fit: BoxFit.contain,
          ),
        ],
      ),
    );
  }
}

class _DecorativeCircle extends StatelessWidget {
  final double size;
  final Color color;
  final double opacity;

  const _DecorativeCircle({
    required this.size,
    required this.color,
    required this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: opacity),
      ),
    );
  }
}

class PerformanceScreen extends StatelessWidget {
  final int acertos;
  final int erros;
  final String feedback;
  /// Material usado para gerar o quiz que originou este resultado — passado
  /// adiante para "Refazer quiz" continuar associado ao mesmo PDF.
  final StudyMaterial? material;
  /// Termos reais do material que o usuário acertou/errou durante o quiz
  /// (ver [QuizQuestion.term] e [_QuizScreenState._select]) — exibidos em
  /// "Pontos fortes"/"O que revisar" abaixo. Vazios quando a tela é aberta
  /// fora do fluxo de quiz (ex.: atalhos de demonstração na Home).
  final List<String> strengths;
  final List<String> reviewTopics;
  const PerformanceScreen({
    required this.acertos,
    required this.erros,
    required this.feedback,
    this.material,
    this.strengths = const [],
    this.reviewTopics = const [],
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final total = acertos + erros;
    final percent = total == 0 ? 0 : (acertos / total) * 100;
    final strengthTags = strengths.isNotEmpty
        ? strengths
        : ['Responda o quiz para ver seus pontos fortes'];
    final reviewTags = reviewTopics.isNotEmpty
        ? reviewTopics
        : ['Nenhum tópico para revisar agora'];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Feedback do quiz'),
        actions: [
          IconButton(
            onPressed: () => Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const MainShell()),
              (route) => false,
            ),
            icon: const Icon(
              LucideIcons.house,
              color: AppColors.primary,
              size: 24,
            ),
          ),
        ],
      ),
      body: _PageList(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          const _HeroTrophyBanner(),
          const SizedBox(height: 18),
          Text(
            percent >= 70 ? 'Muito bem!' : 'Continue praticando!',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w900,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            feedback,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, color: AppColors.mutedText),
          ),
          const SizedBox(height: 18),
          Container(
            decoration: kCardDecoration,
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                Row(
                  children: [
                    _ScoreRing(percent: percent.round()),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$acertos de $total acertos',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 5),
                          const Text(
                            'Você está no caminho certo!',
                            style: TextStyle(color: AppColors.mutedText),
                          ),
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: LinearProgressIndicator(
                              value: percent / 100,
                              minHeight: 7,
                              backgroundColor: Color(0xFFE8EEF6),
                              valueColor: AlwaysStoppedAnimation(
                                AppColors.secondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Divider(color: AppColors.border),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _MetricCard(
                        label: 'Acertos',
                        value: '$acertos',
                        color: AppColors.secondary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MetricCard(
                        label: 'Erros',
                        value: '$erros',
                        color: Colors.redAccent,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _FeedbackPanel(
            icon: LucideIcons.star,
            color: const Color(0xFF3DBB78),
            title: 'Pontos fortes',
            text: 'Você mandou bem nestes tópicos!',
            tags: strengthTags,
          ),
          const SizedBox(height: 12),
          _FeedbackPanel(
            icon: LucideIcons.bookOpen,
            color: AppColors.accent,
            title: 'O que revisar',
            text: 'Que tal revisar estes assuntos?',
            tags: reviewTags,
          ),
          const SizedBox(height: 14),
          const _InfoBanner(
            icon: LucideIcons.sparkles,
            title: 'Cada estudo te aproxima do seu melhor.',
            text: 'Pequenos passos, grandes conquistas!',
          ),
          const SizedBox(height: 16),
          PrimaryButton(
            label: 'Refazer quiz',
            icon: LucideIcons.refreshCw,
            onPressed: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => QuizScreen(material: material)),
            ),
          ),
          SecondaryTextButton(
            label: 'Voltar ao início',
            onPressed: () => Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const MainShell()),
              (route) => false,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreRing extends StatelessWidget {
  final int percent;

  const _ScoreRing({required this.percent});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 94,
      height: 94,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 90,
            height: 90,
            child: CircularProgressIndicator(
              value: percent / 100,
              strokeWidth: 8,
              backgroundColor: const Color(0xFFE8EEF6),
              valueColor: const AlwaysStoppedAnimation(AppColors.secondary),
            ),
          ),
          Text(
            '$percent%',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedbackPanel extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String text;
  final List<String> tags;

  const _FeedbackPanel({
    required this.icon,
    required this.color,
    required this.title,
    required this.text,
    required this.tags,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RoundIcon(icon: icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(text, style: const TextStyle(color: AppColors.mutedText)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: tags
                      .map(
                        (tag) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Text(
                            tag,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MetricCard({
    required this.label,
    required this.value,
    required this.color,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});
  @override
  Widget build(BuildContext context) {
    return _PageList(
      children: [
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                'Perfil e desempenho',
                style: TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w900,
                  color: AppColors.primary,
                ),
              ),
            ),
            SizedBox(width: 8),
            Icon(LucideIcons.bell, color: AppColors.primary),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            const CircleAvatar(
              radius: 38,
              backgroundColor: AppColors.lightBlue,
              child: Icon(LucideIcons.user, size: 42, color: AppColors.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: ValueListenableBuilder<UserAccount?>(
                valueListenable: currentAccount,
                builder: (context, account, _) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account?.name ?? '',
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        account?.email ?? '',
                        style: const TextStyle(
                          color: AppColors.mutedText,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Focada hoje, preparada para o amanhã. 💙',
                        style: TextStyle(
                          color: AppColors.mutedText,
                          height: 1.35,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          decoration: kCardDecoration,
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      'Resumo geral',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  Text(
                    'Esta semana',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.secondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ValueListenableBuilder<UserProgress>(
                valueListenable: currentProgress,
                builder: (context, progress, _) {
                  final hours = progress.tempoEstudoMinutos ~/ 60;
                  final minutes = progress.tempoEstudoMinutos % 60;
                  return Row(
                    children: [
                      _ScoreRing(percent: progress.percent),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          children: [
                            _SummaryLine(
                              icon: LucideIcons.bookOpen,
                              label: 'Quizzes concluídos',
                              value: '${progress.quizzesCompleted}',
                            ),
                            _SummaryLine(
                              icon: LucideIcons.checkSquare,
                              label: 'Acertos',
                              value: '${progress.acertosTotal}',
                            ),
                            _SummaryLine(
                              icon: LucideIcons.clock,
                              label: 'Tempo de estudo',
                              value: '${hours}h ${minutes}m',
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(LucideIcons.flame, color: Colors.orange),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Sequência atual',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    ValueListenableBuilder<UserProgress>(
                      valueListenable: currentProgress,
                      builder: (context, progress, _) {
                        return Text(
                          '${progress.sequenciaDias} dias',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          decoration: kCardDecoration,
          padding: const EdgeInsets.all(18),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.target, color: AppColors.secondary),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Metas da semana',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  Text(
                    '2/3',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 14),
              _GoalRow(
                icon: LucideIcons.bookOpen,
                label: 'Conclua 3 quizzes até domingo',
                progress: 0.66,
                value: '2/3',
              ),
              _GoalRow(
                icon: LucideIcons.clock,
                label: 'Estude por pelo menos 5 horas',
                progress: 1,
                value: '5h/5h',
                complete: true,
              ),
              _GoalRow(
                icon: LucideIcons.target,
                label: 'Mantenha a sequência de 5 dias',
                progress: 1,
                value: '5/5',
                complete: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          decoration: kCardDecoration,
          padding: const EdgeInsets.all(18),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '🏆  Conquistas',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppColors.primary,
                ),
              ),
              SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _AchievementBadge(
                    icon: LucideIcons.star,
                    label: 'Primeiro quiz',
                  ),
                  _AchievementBadge(
                    icon: LucideIcons.target,
                    label: 'Meta cumprida',
                  ),
                  _AchievementBadge(
                    icon: LucideIcons.bookOpen,
                    label: 'Boa leitura',
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        PrimaryButton(
          label: 'Ver desempenho',
          icon: LucideIcons.trendingUp,
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PerformanceScreen(
                acertos: 3,
                erros: 1,
                feedback:
                    'Seu planejamento está bom. Continue com consistência.',
              ),
            ),
          ),
        ),
        SecondaryTextButton(
          label: 'Sair da conta',
          icon: LucideIcons.logOut,
          onPressed: () async {
            await LocalStore.logout();
            currentAccount.value = null;
            currentProgress.value = const UserProgress();
            mainShellTabIndex.value = 0;
            if (!context.mounted) return;
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const OnboardingScreen()),
              (route) => false,
            );
          },
        ),
      ],
    );
  }
}

class _SummaryLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _SummaryLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 22, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppColors.primary),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _GoalRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final double progress;
  final String value;
  final bool complete;

  const _GoalRow({
    required this.icon,
    required this.label,
    required this.progress,
    required this.value,
    this.complete = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          _RoundIcon(icon: icon, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 7),
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: const Color(0xFFE8EEF6),
                    valueColor: const AlwaysStoppedAnimation(
                      AppColors.secondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          complete
              ? const Icon(LucideIcons.checkCircle2, color: Color(0xFF2EAD68))
              : Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: AppColors.primary,
                  ),
                ),
        ],
      ),
    );
  }
}

class _AchievementBadge extends StatelessWidget {
  final IconData icon;
  final String label;

  const _AchievementBadge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: AppColors.lightBlue.withValues(alpha: 0.28),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.secondary, size: 24),
          ),
          const SizedBox(height: 7),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}
