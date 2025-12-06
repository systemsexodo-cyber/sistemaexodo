# Script para fazer deploy da estrutura do Firebase
# Requer Firebase CLI instalado: npm install -g firebase-tools

Write-Host "╔════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  DEPLOY ESTRUTURA FIREBASE - SISTEMA ÊXODO   ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Verificar se Firebase CLI está instalado
$firebaseInstalled = Get-Command firebase -ErrorAction SilentlyContinue
if (-not $firebaseInstalled) {
    Write-Host "❌ Firebase CLI não encontrado!" -ForegroundColor Red
    Write-Host "📦 Instale com: npm install -g firebase-tools" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

Write-Host "✓ Firebase CLI encontrado" -ForegroundColor Green
Write-Host ""

# Verificar se está logado
Write-Host "🔐 Verificando autenticação..." -ForegroundColor Yellow
$firebaseUser = firebase login:list 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Você precisa fazer login no Firebase!" -ForegroundColor Red
    Write-Host "🔑 Execute: firebase login" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

Write-Host "✓ Autenticado no Firebase" -ForegroundColor Green
Write-Host ""

# Menu de opções
Write-Host "Selecione a opção:" -ForegroundColor Cyan
Write-Host "1. Deploy apenas das Regras de Segurança" -ForegroundColor White
Write-Host "2. Deploy apenas dos Índices" -ForegroundColor White
Write-Host "3. Deploy Completo (Regras + Índices)" -ForegroundColor White
Write-Host "4. Verificar estrutura atual" -ForegroundColor White
Write-Host "5. Cancelar" -ForegroundColor White
Write-Host ""

$opcao = Read-Host "Digite o número da opção"

switch ($opcao) {
    "1" {
        Write-Host ""
        Write-Host "📤 Fazendo deploy das Regras de Segurança..." -ForegroundColor Yellow
        firebase deploy --only firestore:rules
        if ($LASTEXITCODE -eq 0) {
            Write-Host ""
            Write-Host "✓ Regras de Segurança deployadas com sucesso!" -ForegroundColor Green
        } else {
            Write-Host ""
            Write-Host "❌ Erro ao fazer deploy das regras" -ForegroundColor Red
        }
    }
    "2" {
        Write-Host ""
        Write-Host "📤 Fazendo deploy dos Índices..." -ForegroundColor Yellow
        firebase deploy --only firestore:indexes
        if ($LASTEXITCODE -eq 0) {
            Write-Host ""
            Write-Host "✓ Índices deployados com sucesso!" -ForegroundColor Green
        } else {
            Write-Host ""
            Write-Host "❌ Erro ao fazer deploy dos índices" -ForegroundColor Red
        }
    }
    "3" {
        Write-Host ""
        Write-Host "📤 Fazendo deploy completo (Regras + Índices)..." -ForegroundColor Yellow
        Write-Host ""
        
        Write-Host "1/2 - Deploy das Regras..." -ForegroundColor Cyan
        firebase deploy --only firestore:rules
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ Erro ao fazer deploy das regras" -ForegroundColor Red
            exit 1
        }
        
        Write-Host ""
        Write-Host "2/2 - Deploy dos Índices..." -ForegroundColor Cyan
        firebase deploy --only firestore:indexes
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ Erro ao fazer deploy dos índices" -ForegroundColor Red
            exit 1
        }
        
        Write-Host ""
        Write-Host "╔════════════════════════════════════════════════╗" -ForegroundColor Green
        Write-Host "║  ✓ DEPLOY COMPLETO REALIZADO COM SUCESSO!     ║" -ForegroundColor Green
        Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Green
    }
    "4" {
        Write-Host ""
        Write-Host "📊 Verificando estrutura atual..." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Coleções configuradas:" -ForegroundColor Cyan
        Write-Host "  - clientes" -ForegroundColor White
        Write-Host "  - produtos" -ForegroundColor White
        Write-Host "  - servicos" -ForegroundColor White
        Write-Host "  - pedidos" -ForegroundColor White
        Write-Host "  - ordens_servico" -ForegroundColor White
        Write-Host "  - entregas" -ForegroundColor White
        Write-Host "  - vendas_balcao" -ForegroundColor White
        Write-Host "  - trocas_devolucoes" -ForegroundColor White
        Write-Host "  - estoque_historico" -ForegroundColor White
        Write-Host "  - aberturas_caixa" -ForegroundColor White
        Write-Host "  - fechamentos_caixa" -ForegroundColor White
        Write-Host "  - motoristas" -ForegroundColor White
        Write-Host "  - config" -ForegroundColor White
        Write-Host ""
        Write-Host "📄 Arquivos de configuração:" -ForegroundColor Cyan
        Write-Host "  - firestore.rules (Regras de Segurança)" -ForegroundColor White
        Write-Host "  - firestore.indexes.json (Índices Compostos)" -ForegroundColor White
        Write-Host ""
    }
    "5" {
        Write-Host ""
        Write-Host "❌ Operação cancelada" -ForegroundColor Yellow
        exit 0
    }
    default {
        Write-Host ""
        Write-Host "❌ Opção inválida!" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""
Write-Host "✅ Processo concluído!" -ForegroundColor Green
Write-Host ""

