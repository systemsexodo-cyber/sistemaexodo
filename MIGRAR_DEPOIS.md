# MIGRAR DEPOIS — pacote de migração para outro PC (gerado em 20/10/2026)

Este guia lista o que JÁ ESTÁ SALVO e os passos para migrar o sistema
(Sincronizador + PostgreSQL local + Supabase local na VM) para outro PC,
quando for a hora. Detalhes e justificativas: ver `MIGRAR_NUVEM_LOCAL.md`.

---

## 1. O que já está salvo (pasta `F:\Backups_NuvemLocal\`)

| Arquivo | Conteúdo |
|---|---|
| `20261020_141038\nuvem_20261020_141038.tar.gz` | **Nuvem local completa**: dump do banco `postgres` da VM + `volumes/storage` + `docker-compose.yml` + `.env` da stack Supabase |
| `_backup_pc_antigo\exodo_db_local_20261020_141054.dump` | **Banco local** (`exodo_db`, o principal) em formato `pg_dump -Fc` |
| `_backup_pc_antigo\env_repo_*.env` | `.env` da raiz do repo (inclui `SUPABASE_SERVICE_ROLE_KEY`) |
| `_backup_pc_antigo\env_SistemaExodo_*.env` | `.env` do `C:\SistemaExodo` (o que o tray usa) |
| `_backup_pc_antigo\app_env_*.env` | `assets/app.env` (chaves embutidas no APK/site) |
| `_backup_pc_antigo\env_neon_*.env` | `.env.neon` (provedor reserva) |
| `_backup_pc_antigo\vm_ssh_key_id_ed25519` | Chave SSH da VM (porta 2222, usuário `charles`) |

> **IMPORTANTE:** `_backup_pc_antigo` contém SENHAS. Não comite no Git e não
> compartilhe. Copie para um local seguro (disco externo/nuvem privada) antes
> de desfazer o PC antigo.

Antes de migrar de verdade, rode de novo (para pegar o estado mais fresco):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\backup_nuvem_local.ps1
```

---

## 2. Passo a passo resumido (versão curta)

1. **PC antigo:** pare o tray (`Stop-Process -Name SincronizadorNuvem -Force`),
   rode o `backup_nuvem_local.ps1` e faça o dump do banco local (comando abaixo).
2. **PC novo:** instale VirtualBox + Tailscale + PostgreSQL 16.
3. **Restaure a nuvem:** VM limpa (Ubuntu 24.04 + Docker) **ou** importe o `.ova`
   se tiver exportado com a VM parada. Extraia o `tar.gz` sobre a stack e rode o
   `pg_restore` **de dentro do container** (detalhes em `MIGRAR_NUVEM_LOCAL.md` §4.4).
4. **Restaure o banco local:** `pg_restore` do dump `exodo_db_local_*.dump`.
5. **Copie os `.env`** de volta (`C:\SistemaExodo\.env` e o do repo).
6. **Reaplique o Funnel** (duas portas: 10000→5434 e `/`→8001).
7. **Atualize o hostname**, se o PC novo tiver outro nome Tailscale
   (`assets/app.env`: `DB_CLOUD_HOST` e `NEON_DATA_API_URL`) e gere APK/site novos.
8. **Ligue o tray** e valide (checklist §4).

---

## 3. Comandos exatos

### 3.1 Dump do banco local (PC antigo, antes de ir embora)

```powershell
cd <pasta do repo>
$env_db = Get-Content .env | Where-Object { $_ -match '^DB_PASSWORD=' } | ForEach-Object { ($_ -split '=',2)[1] }
$env:PGPASSWORD = $env_db
& 'C:\SistemaExodo\postgresql\bin\pg_dump.exe' -h localhost -p 5432 -U exodo_user -d exodo_db -Fc `
  -f "F:\Backups_NuvemLocal\_backup_pc_antigo\exodo_db_local_$(Get-Date -Format yyyyMMdd_HHmmss).dump"
```

### 3.2 Backup da nuvem local (PC antigo)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\backup_nuvem_local.ps1
```

### 3.3 Restaurar o banco local (PC novo)

```powershell
$env:PGPASSWORD = '<senha do DB_PASSWORD>'
& 'C:\SistemaExodo\postgresql\bin\pg_restore.exe' -h localhost -p 5432 -U exodo_user -d exodo_db `
  --clean --if-exists --no-owner 'F:\Backups_NuvemLocal\_backup_pc_antigo\exodo_db_local_<data>.dump'
```

### 3.4 Restaurar a nuvem (dentro da VM, PC novo)

```bash
cd /home/charles/supabase
tar xzf /tmp/nuvem_<data>.tar.gz            # contém dump, compose, .env, storage
docker compose stop supabase-rest supabase-meta supabase-auth supabase-storage supabase-realtime
docker cp exodo_nuvem.dump supabase-db:/tmp/
docker exec supabase-db pg_restore -U supabase_admin -d postgres \
    --clean --if-exists --no-owner /tmp/exodo_nuvem.dump
docker compose up -d
```

### 3.5 Tailscale Funnel (PC novo, roda no Windows)

```powershell
& 'C:\Program Files\Tailscale\tailscale.exe' funnel --bg --tls-terminated-tcp=10000 tcp://127.0.0.1:5434
& 'C:\Program Files\Tailscale\tailscale.exe' funnel --bg http://127.0.0.1:8001
& 'C:\Program Files\Tailscale\tailscale.exe' funnel status
```

Instale o atalho `INICIAR_FUNNEL_SUPABASE.bat` no `shell:startup` do PC novo.

### 3.6 Portas NAT da VM (conferir no VirtualBox)

`8001→8000` (Kong/API), `5434→5432` (Postgres), `6543→6543` (pooler), `2222→22` (SSH).

---

## 4. Checklist de validação (PC novo, tudo ligado)

- [ ] `http://localhost:8001/rest/v1/` → **200** (com apikey)
- [ ] `docker ps` na VM: todos os containers `healthy` (inclusive `realtime-dev`)
- [ ] Tray (`SincronizadorNuvem.exe`) subiu e log mostra `Nuvem: supabase (http://localhost:8001)`
- [ ] `_exodo_sync_log = 0` no banco local
- [ ] `sync_status.ultima_sincronizacao` atualizando
- [ ] Log sem `HTTP 503` / `HTTP 401` / `42501` (RLS)
- [ ] Contagens batem: `empresas`, `clientes`, `produtos`, `vendas_balcao`, `pedidos`, `nfces`
- [ ] Realtime: `temp\valida_postgres_changes.js` PASSA (INSERT chega em <1s)
- [ ] Site abre pelo Funnel e mostra dados
- [ ] Celular no 4G (fora da loja) acessa
- [ ] Venda de teste no PC aparece no site

---

## 5. Cuidados conhecidos (a lição de 20/10/2026)

- **RLS sem policies:** a nuvem local tem RLS habilitado em 59 tabelas e NENHUMA
  policy. Só a `service_role` lê/escreve. O `.env` que o tray carrega **precisa**
  ter `SUPABASE_SERVICE_ROLE_KEY` — sem ela, o sync sobe com a anon e todo
  INSERT/UPDATE morre com `401/42501` e o site fica desatualizado.
- **Duas nuvens ativas = divergência.** Nunca deixe o PC antigo e o novo
  sincronizando ao mesmo tempo. Desligue um antes de ligar o outro.
- **Hostname Tailscale muda** se o nome do PC novo for diferente — atualize
  `assets/app.env` e gere APK + deploy do site novos.
- **`empresas` não sobe pelo re-enfileiramento** (tabela somente-leitura no sync);
  se precisar reconstruir a nuvem do zero, recrie as empresas antes.
- O HD externo `F:` teve evento NTFS 50 em 20/10 (o VDI estava nele). Se for
  mover a VM para outro disco, faça agora — antes de precisar migrar com pressa.
