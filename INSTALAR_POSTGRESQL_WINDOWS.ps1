# Script para instalar e configurar PostgreSQL no Windows
# Execute como Administrador

$ErrorActionPreference = 'Stop'

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "INSTALACAO DO POSTGRESQL PARA EXODO" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Verificar se está rodando como Administrador
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

if (-not $isAdmin) {
    Write-Host "[ERRO] Este script requer privilegios de administrador!" -ForegroundColor Red
    Write-Host "Execute o PowerShell como Administrador e tente novamente." -ForegroundColor Yellow
    exit 1
}

# Verificar se Chocolatey está instalado
Write-Host "`n📦 Verificando Chocolatey..." -ForegroundColor Cyan
$chocoCheck = Get-Command choco -ErrorAction SilentlyContinue

if (-not $chocoCheck) {
    Write-Host "❌ Chocolatey não encontrado!" -ForegroundColor Red
    Write-Host "`n📝 Para instalar Chocolatey, execute em PowerShell (como Admin):" -ForegroundColor Yellow
    Write-Host @"
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
Invoke-RestMethod -Uri https://community.chocolatey.org/install.ps1 | Invoke-Expression
"@
    Write-Host "`nDepois execute este script novamente." -ForegroundColor Yellow
    exit 1
} else {
    Write-Host "✅ Chocolatey encontrado" -ForegroundColor Green
}

# Instalar PostgreSQL
Write-Host "`n📥 Instalando PostgreSQL..." -ForegroundColor Cyan
choco install postgresql --version=15.0 -y

# Verificar instalação
Write-Host "`n🔍 Verificando PostgreSQL..." -ForegroundColor Cyan
$psqlCheck = Get-Command psql -ErrorAction SilentlyContinue

if (-not $psqlCheck) {
    Write-Host "❌ Falha na instalação do PostgreSQL" -ForegroundColor Red
    exit 1
}

$version = psql --version
Write-Host "✅ PostgreSQL instalado com sucesso!" -ForegroundColor Green
Write-Host "   $version" -ForegroundColor Green

# Iniciar serviço PostgreSQL
$postgresService = Get-Service | Where-Object { $_.DisplayName -match 'PostgreSQL' -or $_.Name -match 'postgresql' } | Select-Object -First 1

if (-not $postgresService) {
    Write-Host "❌ Serviço PostgreSQL não encontrado" -ForegroundColor Red
    exit 1
}

Write-Host "`n🚀 Iniciando serviço PostgreSQL ($($postgresService.Name))..." -ForegroundColor Cyan
Start-Service -Name $postgresService.Name -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5
$postgresService.Refresh()

if ($postgresService.Status -ne 'Running') {
    Write-Host "❌ Não foi possível iniciar o serviço PostgreSQL" -ForegroundColor Red
    Write-Host "   Verifique o serviço no Gerenciador de Serviços do Windows." -ForegroundColor Yellow
    exit 1
}

Write-Host "✅ Serviço PostgreSQL em execução" -ForegroundColor Green

# Configurar senha do banco via variável de ambiente ou padrão
$dbPassword = $env:EXODO_DB_PASSWORD
if ([string]::IsNullOrWhiteSpace($dbPassword)) {
    $dbPassword = 'sua_senha_super_segura_aqui'
    Write-Host "ℹ️  Usando senha padrão para o banco. Defina EXODO_DB_PASSWORD para personalizar." -ForegroundColor Yellow
}

# Criar usuário e banco de dados
Write-Host "`n🛠️  Configurando usuário e banco PostgreSQL..." -ForegroundColor Cyan

$setupSql = @"
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'exodo_user') THEN
        CREATE ROLE exodo_user LOGIN PASSWORD '$dbPassword';
    ELSE
        ALTER ROLE exodo_user WITH PASSWORD '$dbPassword';
    END IF;
END
$$;

ALTER ROLE exodo_user CREATEDB;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'exodo_db') THEN
        CREATE DATABASE exodo_db OWNER exodo_user;
    END IF;
END
$$;

GRANT ALL PRIVILEGES ON DATABASE exodo_db TO exodo_user;
"@

$setupSql | & psql -U postgres -d postgres -v ON_ERROR_STOP=1 -q

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Falha ao criar usuário e banco PostgreSQL" -ForegroundColor Red
    exit 1
}

Write-Host "✅ Usuário e banco configurados" -ForegroundColor Green

# Criar .env de exemplo
Write-Host "`n📝 Criando arquivo .env de exemplo..." -ForegroundColor Cyan

$envContent = @"
# Banco de Dados PostgreSQL
DB_HOST=localhost
DB_PORT=5432
DB_NAME=exodo_db
DB_USER=exodo_user
DB_PASSWORD=$dbPassword

# SQLAlchemy (opcional)
DATABASE_URL=postgresql://exodo_user:$dbPassword@localhost:5432/exodo_db
SQLALCHEMY_ECHO=false

# Flask
FLASK_ENV=development
"@

$envPath = Join-Path (Get-Location) ".env"
if (-not (Test-Path $envPath)) {
    $envContent | Out-File -FilePath $envPath -Encoding UTF8
    Write-Host "✅ Arquivo .env criado: $envPath" -ForegroundColor Green
} else {
    Write-Host "ℹ️  Arquivo .env já existe, não será sobrescrito" -ForegroundColor Yellow
}

# Testar conexão
Write-Host "`n🧪 Testando conexão com o PostgreSQL..." -ForegroundColor Cyan
$connectionSql = "SELECT 1;"
$connectionSql | & psql -h localhost -p 5432 -U exodo_user -d exodo_db -v ON_ERROR_STOP=1 -q

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Falha ao conectar ao PostgreSQL com o usuário exodo_user" -ForegroundColor Red
    exit 1
}

Write-Host "✅ Conexão com PostgreSQL validada" -ForegroundColor Green

# Resumo e próximos passos
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "RESUMO DA CONFIGURACAO" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "✅ PostgreSQL instalado e em execução" -ForegroundColor Green
Write-Host "✅ Usuário exodo_user configurado" -ForegroundColor Green
Write-Host "✅ Banco exodo_db criado" -ForegroundColor Green
Write-Host "✅ Arquivo .env preparado" -ForegroundColor Green

Write-Host "`n📌 Próximos passos:" -ForegroundColor Yellow
Write-Host "1. Instalar dependências Python:" -ForegroundColor Gray
Write-Host "   cd backend_pynfe"
Write-Host "   pip install psycopg2-binary sqlalchemy alembic"

Write-Host "`n2. Validar conexão da aplicação:" -ForegroundColor Gray
Write-Host "   python test_postgres_connection.py"

Write-Host "`n3. Executar migrations:" -ForegroundColor Gray
Write-Host "   flask db upgrade"

Write-Host "`n💡 Comandos úteis:" -ForegroundColor Gray
Write-Host "   Parar PostgreSQL: pg_ctl -D 'C:\Program Files\PostgreSQL\15\data' stop"
Write-Host "   Iniciar PostgreSQL: pg_ctl -D 'C:\Program Files\PostgreSQL\15\data' start"
Write-Host "   Verificar status: Get-Service | Where-Object { \$_.DisplayName -match 'PostgreSQL' }"

Write-Host "`n✅ PostgreSQL está pronto para uso!" -ForegroundColor Green
