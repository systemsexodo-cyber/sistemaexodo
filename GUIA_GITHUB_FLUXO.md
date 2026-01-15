# Guia de Fluxo de Trabalho GitHub (Sistema Êxodo)

Este guia explica como usar as automações que configuramos para o seu projeto.

## 1. O Robô Analista (CI)
Toda vez que você envia código (`push`) para o GitHub, o workflow **"Verificação de Código (CI)"** entra em ação.
- **O que ele faz?** Ele baixa o seu código, instala as dependências e verifica se existem erros óbvios ou se os testes automáticos passam.
- **Onde vejo?** Na aba **Actions** do seu repositório no GitHub.

## 2. Deploy Automático (Firebase)
Ao enviar código para as branches `master`, `main` ou `modo-dev`:
- **O que ele faz?** Gera a versão Web do seu sistema e envia automaticamente para o Firebase Hosting.
- **URL:** [https://exodosystems-1541d.web.app](https://exodosystems-1541d.web.app)

## 3. Como criar uma Nova Versão (Release) e Gerar APK
Sempre que você atingir um marco importante (ex: "Sistema de Agendamento Finalizado"), você deve criar uma Versão:

1. Vá no site do GitHub do seu projeto.
2. No menu à direita, clique em **Releases**.
3. Clique em **Draft a new release**.
4. **Tag:** Digite algo como `v1.0.1`.
5. **Título:** "Versão 1.0.1 - Ajustes de Agendamento".
6. Clique em **Publish release**.

**O que acontece depois?**
- O robô **"Gerar APK de Versão"** vai começar a trabalhar sozinho.
- Ele vai gerar o arquivo `.apk` (para instalar no Android) e vai **anexar automaticamente** na página dessa versão que você acabou de criar.

## 4. Dicas de Segurança
- **Não apague a branch master**: Ela é sua base.
- **Use Pull Requests**: Se começar a trabalhar com mais pessoas, peça para elas criarem branches e você revisa o código antes de aceitar.

## 5. Próximos Passos
Para subir essas configurações agora:
1. No terminal do VS Code, digite:
   ```powershell
   git add .github/workflows/
   git commit -m "feat: Configurando workflows de CI, Deploy e Release APK"
   .\push_para_github.ps1
   ```
