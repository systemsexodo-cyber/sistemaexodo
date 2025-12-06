# Script de Configuração do Git para Sistema Êxodo
# Execute este script no PowerShell para configurar suas credenciais do Git

Write-Host "=== Configuração do Git para Sistema Êxodo ===" -ForegroundColor Cyan
Write-Host ""

# Solicitar nome do usuário
$nome = Read-Host "Digite seu nome completo"
if ($nome) {
    git config --global user.name "$nome"
    Write-Host "✓ Nome configurado: $nome" -ForegroundColor Green
} else {
    Write-Host "✗ Nome não fornecido" -ForegroundColor Red
}

Write-Host ""

# Solicitar email do usuário
$email = Read-Host "Digite seu email"
if ($email) {
    git config --global user.email "$email"
    Write-Host "✓ Email configurado: $email" -ForegroundColor Green
} else {
    Write-Host "✗ Email não fornecido" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Verificação da Configuração ===" -ForegroundColor Cyan
Write-Host ""

# Verificar configurações
$nomeConfigurado = git config --global user.name
$emailConfigurado = git config --global user.email

Write-Host "Nome configurado: $nomeConfigurado" -ForegroundColor Yellow
Write-Host "Email configurado: $emailConfigurado" -ForegroundColor Yellow

Write-Host ""
Write-Host "=== Informações do Repositório ===" -ForegroundColor Cyan

# Verificar remote
$remote = git remote get-url origin 2>$null
if ($remote) {
    Write-Host "Repositório remoto: $remote" -ForegroundColor Yellow
} else {
    Write-Host "Nenhum repositório remoto configurado" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Status do Repositório ===" -ForegroundColor Cyan
git status --short

Write-Host ""
Write-Host "=== Próximos Passos ===" -ForegroundColor Cyan
Write-Host "1. Configure autenticação no GitHub (Token ou SSH)" -ForegroundColor White
Write-Host "2. Veja o arquivo CONFIGURACAO_GIT.md para instruções detalhadas" -ForegroundColor White
Write-Host "3. Faça commit das suas mudanças: git add . && git commit -m 'mensagem'" -ForegroundColor White
Write-Host "4. Envie para o GitHub: git push origin main" -ForegroundColor White
Write-Host ""

