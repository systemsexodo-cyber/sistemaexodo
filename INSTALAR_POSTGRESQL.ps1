param(
    [switch]$Admin
)

# Verificar se esta rodando como Administrador
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

if (-not $isAdmin) {
    Write-Host "Este script requer privilegios de administrador!" -ForegroundColor Red
    Write-Host "Execute novamente como Administrador." -ForegroundColor Yellow
    exit 1
}

Write-Host "`n======== INSTALACAO DO POSTGRESQL ========`n" -ForegroundColor Cyan

# Verificar Chocolatey
Write-Host "[1/3] Verificando Chocolatey..." -ForegroundColor Yellow
$chocoCheck = Get-Command choco -ErrorAction SilentlyContinue

if (-not $chocoCheck) {
    Write-Host "Chocolatey nao encontrado. Instalando..." -ForegroundColor Yellow
    Set-ExecutionPolicy Bypass -Scope Process -Force
    iex ((New-Object System.Net.ServicePointManager).ServerCertificateValidationCallback = {$true}; Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1')))
} else {
    Write-Host "[OK] Chocolatey encontrado" -ForegroundColor Green
}

# Instalar PostgreSQL
Write-Host "`n[2/3] Instalando PostgreSQL..." -ForegroundColor Yellow
choco install postgresql --version=15.0 -y

# Verificar instalacao
Write-Host "`n[3/3] Verificando PostgreSQL..." -ForegroundColor Yellow
$psqlCheck = Get-Command psql -ErrorAction SilentlyContinue

if ($psqlCheck) {
    Write-Host "[OK] PostgreSQL instalado com sucesso!" -ForegroundColor Green
    psql --version
} else {
    Write-Host "[ERRO] Falha na instalacao!" -ForegroundColor Red
    exit 1
}

# Criar .env
Write-Host "`n[CRIANDO] Arquivo .env..." -ForegroundColor Yellow

$envPath = ".env"
if (-not (Test-Path $envPath)) {
    $envContent = @"
DB_HOST=localhost
DB_PORT=5432
DB_NAME=exodo_db
DB_USER=exodo_user
DB_PASSWORD=senha123

DATABASE_URL=postgresql://exodo_user:senha123@localhost:5432/exodo_db
SQLALCHEMY_ECHO=false
"@
    $envContent | Out-File -FilePath $envPath -Encoding UTF8
    Write-Host "[OK] Arquivo .env criado" -ForegroundColor Green
} else {
    Write-Host "[INFO] Arquivo .env ja existe" -ForegroundColor Yellow
}

# Instrucoes finais
Write-Host "`n========================================`n" -ForegroundColor Cyan
Write-Host "PROXIMAS ETAPAS:" -ForegroundColor Yellow
Write-Host "`n1. Criar banco de dados (execute como Admin):`n" -ForegroundColor Cyan

Write-Host "   psql -U postgres`n`n" -ForegroundColor White

Write-Host "   Dentro do psql, execute:`n" -ForegroundColor Cyan

$sqlCommands = @"
   CREATE USER exodo_user WITH PASSWORD 'senha123';
   CREATE DATABASE exodo_db OWNER exodo_user;
   GRANT ALL PRIVILEGES ON DATABASE exodo_db TO exodo_user;
   ALTER ROLE exodo_user CREATEDB;
   \q
"@

Write-Host $sqlCommands -ForegroundColor White

Write-Host "`n2. Instalar driver Python:`n" -ForegroundColor Cyan
Write-Host "   cd backend_pynfe" -ForegroundColor White
Write-Host "   pip install psycopg2-binary`n" -ForegroundColor White

Write-Host "`n3. Testar conexao:`n" -ForegroundColor Cyan
Write-Host "   python ../test_postgres_connection.py`n" -ForegroundColor White

Write-Host "[CONCLUIDO] PostgreSQL instalado! Siga as instrucoes acima." -ForegroundColor Green
Write-Host ""
