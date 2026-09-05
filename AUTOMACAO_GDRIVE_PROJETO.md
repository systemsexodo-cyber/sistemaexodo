# 🚀 Automação de Backup do Projeto no Google Drive

Este guia explica como configurar e usar a automação para salvar automaticamente todo o código do seu projeto no Google Drive, garantindo que você nunca perca o seu trabalho.

## 📌 Como Funciona
O sistema utiliza dois componentes:
1.  **Script PowerShell (`backup_projeto_gdrive_automatico.ps1`)**: Orquestra a criação do arquivo ZIP (ignorando pastas pesadas como `build` e `node_modules`) e chama o serviço de upload.
2.  **Script Dart (`lib/scripts/gdrive_backup.dart`)**: Realiza a comunicação segura com a API do Google Drive via Conta de Serviço.

---

## 🛠️ Passo a Passo para Configuração

### 1. Criar uma Conta de Serviço (Service Account)
Como se trata de uma automação de linha de comando, não podemos usar o login de navegador comum. Precisamos de uma "Conta de Serviço":

1.  Acesse o [Google Cloud Console](https://console.cloud.google.com/).
2.  Crie um novo projeto (ou use um existente).
3.  Vá em **APIs e Serviços > Biblioteca** e ative a **Google Drive API**.
4.  Vá em **IAM e Administrador > Contas de Serviço**.
5.  Clique em **Criar Conta de Serviço**. Dê um nome (ex: `backup-exodo`).
6.  Após criar, entre na conta, vá na aba **Chaves**, clique em **Adicionar Chave > Criar nova chave (JSON)**.
7.  O download de um arquivo `.json` será feito. **Renomeie-o para `gdrive_service_account.json`** e coloque na raiz da pasta do seu projeto.

### 2. Dar Permissão na Pasta do Drive
A Conta de Serviço tem seu próprio "espaço". Para que os backups apareçam no seu Drive pessoal:
1.  Abra o arquivo `gdrive_service_account.json` e copie o endereço de e-mail (campo `client_email`). Ele será algo como `backup-exodo@seu-projeto.iam.gserviceaccount.com`.
2.  No seu Google Drive, crie uma pasta chamada **SistemaExodo_Projeto_Backups** (ou qualquer outra).
3.  Compartilhe essa pasta com o e-mail da Conta de Serviço que você copiou, dando permissão de **Editor**.

---

## 🏃 Como Executar

### Backup Manual
Sempre que quiser salvar o projeto no Drive, abra o terminal na pasta do projeto e execute:
```powershell
.\backup_projeto_gdrive_automatico.ps1
```

### Backup Automático (Agendado)
Para não ter que rodar o comando manualmente, eu criei um script que configura o Windows para fazer isso por você todo dia às 02:00 da manhã:

1.  Abra o terminal na pasta do projeto.
2.  Execute o comando:
    ```powershell
    .\agendar_backup_gdrive.ps1
    ```
3.  Pronto! O Windows agora cuidará do resto.

*Nota: Se o agendamento falhar, abra o VS Code em modo Administrador e tente novamente.*

---

## 📄 Notas Importantes
- **Exclusões**: O backup ignora automaticamente as pastas `build/`, `.dart_tool/`, `node_modules/`, e `.git/` para o arquivo não ficar gigante.
- **Segurança**: Nunca envie o arquivo `gdrive_service_account.json` para o GitHub (ele já está no `.gitignore` padrão do projeto).
- **Google Drive for Desktop**: Se você já usa o programa do Google Drive no computador, uma alternativa ainda mais simples é apenas configurar o script `backup_projeto_zip.ps1` para salvar direto na pasta mapeada (ex: `G:\Meu Drive\...`).

---
*Configurado por Antigravity em $(Get-Date)*
