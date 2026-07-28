# Estudo em Foco

Aplicativo Flutter para organização de estudos, materiais em PDF simulados, quizzes interativos e acompanhamento de desempenho.

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
