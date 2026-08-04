# Estudo em Foco

Aplicativo Flutter Web para organização de estudos: carregamento de materiais
em PDF, geração automática de resumo e quiz a partir do conteúdo do arquivo, e
acompanhamento de desempenho.

**Aplicativo publicado:** https://priiscillasantos.github.io/estudo_em_foco/

## Como testar o aplicativo

### 1. Acesse o app publicado

https://priiscillasantos.github.io/estudo_em_foco/

### 2. Primeiro acesso

- Clique em **Começar**.
- Crie uma conta com nome, e-mail e senha.
- Depois do cadastro, você entra direto no aplicativo.

### 3. Login

- Após o primeiro acesso, o app lembra o último e-mail usado.
- Por segurança, a senha **não** é salva pelo aplicativo.
- Para sair da conta, use a opção **Sair da conta** na aba **Perfil**.

### 4. Carregar material

- Acesse a aba **Estudos**.
- Clique em **Carregar PDF**.
- Selecione um PDF com texto selecionável.
- O app tentará extrair o texto e gerar um resumo automaticamente.

### 5. Ler material

- Após carregar o PDF, clique em **Ler material**.
- O leitor permite visualizar as páginas do PDF.
- Durante a sessão atual, o PDF pode ser aberto novamente sem novo upload.

### 6. Gerar quiz

- Para responder ao quiz, o PDF precisa ter texto selecionável.
- Clique em **Responder quiz**.
- O app gera perguntas com base no conteúdo extraído do PDF.

### 7. Feedback

Ao finalizar o quiz, o app mostra:

- porcentagem;
- acertos;
- erros;
- pontos fortes;
- tópicos para revisar;
- orientação para continuar estudando.

### 8. Perfil e desempenho

- Acesse a aba **Perfil** para acompanhar o desempenho salvo localmente.

### 9. Observações importantes

- Este aplicativo é um MVP acadêmico.
- O app não utiliza backend.
- Os dados são salvos localmente no navegador/dispositivo.
- Se os dados do navegador forem apagados, contas, materiais e progresso
  também podem ser removidos.
- PDFs escaneados ou compostos por imagem podem ser lidos, mas talvez não
  gerem resumo e quiz.
- Para resumo e quiz automático, utilize PDFs com texto selecionável.
- Se o navegador for fechado e o PDF precisar ser lido novamente, carregue o
  arquivo outra vez, caso solicitado.

## Tecnologias utilizadas

- Flutter Web
- Armazenamento local no navegador
- Extração de texto de PDF
- Geração local de resumo e quiz por regras heurísticas

## Como executar localmente

```bash
flutter pub get
flutter run -d chrome
```

## Deploy no GitHub Pages

O workflow em [.github/workflows/deploy_web.yml](.github/workflows/deploy_web.yml) publica a build web em GitHub Pages com base-href `/estudo_em_foco/`.

Para publicar:
1. Envie o projeto para o GitHub.
2. Ative o GitHub Pages no repositório.
3. Selecione a opção "GitHub Actions" como fonte.
4. A ação será publicada automaticamente na branch `main`.
