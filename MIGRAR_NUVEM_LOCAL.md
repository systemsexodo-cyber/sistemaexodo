# Migrar ou recuperar a "nuvem local" (Supabase na VM)

Guia prático para quando a nuvem local **parar** ou precisar **mudar de máquina/disco**.

> **Regra de ouro:** o banco principal é o **PostgreSQL do Windows** (`localhost:5432`,
> dados em `C:\SistemaExodo\pgdata`). A nuvem é uma **réplica**. Se a nuvem cair, a loja
> continua vendendo; o que para é o acesso externo (site/celular fora da loja) e o espelho.

## 0. A nuvem não sobrescreve o que é mais novo no local

Toda linha baixada da nuvem passa por uma trava de versão: o `updated_at` da
nuvem precisa ser **estritamente maior** que o do banco local para o `UPDATE`
acontecer (`sincronizar_local_supabase.gravar_registros_locais`). Se a nuvem
voltar de um backup antigo, ficar parada ou devolver uma cópia velha, o banco
local **não regride**. O mesmo vale para as colunas de data guardadas como
texto (NF-e, entregas, contas a pagar etc.): a comparação converte a data com
segurança e ignora valor que não seja uma data ISO.

Alterações feitas no **site** continuam descendo normalmente porque toda
escrita no site carimba `updated_at = agora` (inclusive alteração parcial, como
só o estoque). Se uma linha estiver bloqueada por um conflito, o sincronizador
fecha sozinho os conflitos em que as duas versões são o **mesmo dado** (só
mudava o formato de número/data); conflito com conteúdo diferente continua
esperando a decisão em **Sincronia → Corrigir Conflitos**.

---

## 1. Como a nuvem está montada hoje

| Peça | Onde fica |
|---|---|
| VM | VirtualBox `Ubuntu-Supabase` (6 GB RAM, 3 CPUs) |
| Disco da VM | `F:\VMs\Ubuntu-Supabase\Ubuntu-Supabase.vdi` (60 GB virtuais, ~14 GB usados) |
| Stack Supabase | `/home/charles/supabase` (projeto compose `supabase`) |
| Banco | container `supabase-db` (PostgreSQL), base `postgres`, usuário `supabase_admin`, ~42 MB |
| Arquivos/buckets | `/home/charles/supabase/volumes/storage` (hoje quase vazio) |
| Portas (NAT) | `8001→8000` (API/Kong), `5434→5432` (Postgres), `6543→6543` (pooler), `2222→22` (SSH) |
| SSH | `ssh -i %USERPROFILE%\.ssh\id_ed25519_vm -p 2222 charles@127.0.0.1` |
| Funnel (roda no **Windows**, não na VM) | HTTPS → `127.0.0.1:8001`; TCP `10000` → `127.0.0.1:5434` |
| Endereço público | `desktop-86ut1r1.tail9b4943.ts.net` |
| Script de subida | `INICIAR_FUNNEL_SUPABASE.bat` (atalho em `shell:startup`) |
| Sincronizador | `C:\SistemaExodo\SincronizadorNuvem.exe` + `.env` (`SUPABASE_URL=http://localhost:8001`) |
| Site/app | `assets/app.env` (aponta para o Funnel) |

**Backup = 3 coisas:** dump do banco + `volumes/storage` + configuração (`.env` e
`docker-compose.yml`). O script `backup_nuvem_local.ps1` já junta as três.

Há também o backup **completo da VM** (disco inteiro, para restaurar o servidor
em outra máquina): script `backup_vm_nuvem.ps1`, tarefa semanal `BackupVMNuvem`.
Ver a seção 2.1.

---

## 2. Fazer backup agora (e agendar)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\backup_nuvem_local.ps1
```

Gera `F:\Backups_NuvemLocal\<data_hora>\nuvem_<data_hora>.tar.gz` com:

- `exodo_nuvem.dump` — `pg_dump -Fc` do banco `postgres` (todos os schemas);
- `docker-compose.yml` e `.env` da stack — **contêm segredos** (chaves JWT/senha);
- `volumes/storage` — arquivos dos buckets.

Mantém os últimos **7 dias** (ajuste com `-ManterDias`). A pasta é restrita ao seu usuário.

Tarefas já registradas neste PC (Agendador):

| Tarefa | Quando | O que salva |
|---|---|---|
| `BackupNuvemLocal` | diário 23:30 | dump+storage+config → `F:\Backups_NuvemLocal` (7 dias) |
| `ExodoBackupLocal` | diário 03:00 | dump do banco principal `exodo_db` → `F:\ExodoBackups` (30 dias) |
| `BackupVMNuvem` | domingo 04:00 | VM COMPLETA (VDI) → `F:\Backups_VM` (3 cópias) |

### 2.1 Backup completo da VM (`backup_vm_nuvem.ps1`)

Salva o **servidor inteiro** (disco + configuração) para restaurar em outra
máquina sem reconstruir nada. A VM continua RODANDO durante o backup: o script
tira um snapshot, clona a partir dele e apaga o snapshot (~9 min, 14 GB).

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\backup_vm_nuvem.ps1
```

- Saída: `F:\Backups_VM\Ubuntu-Supabase_bk_<data>\` (`.vbox` + `.vdi` + manifesto);
- Restaurar: VirtualBox > Gerar > Importar Appliance > apontar o `.vbox` da pasta;
- **Atenção:** este backup mora no mesmo disco `F:` que o VDI original. Ele protege
  contra exclusão/correção da VM, não contra morte do disco. Para o caso de perda
  total, o dump (`backup_nuvem_local.ps1`) deve ser copiado para fora do PC.

**Teste o restore de vez em quando** (seção 5). Backup que nunca foi restaurado não é backup.

> Alternativa manual, sem o script (dentro da VM):
> ```bash
> docker exec supabase-db pg_dump -U supabase_admin -d postgres -Fc > ~/exodo_nuvem.dump
> ```

---

## 3. Cenário A — a nuvem parou (site fora / tray com HTTP 503)

Sintomas típicos: site/celular fora da loja não abre, e o log do tray repete
`HTTP 503` / `PGRST002 could not query the database for the schema cache`.

### 3.1 Triagem rápida (2 minutos)

```powershell
# 1) A VM está rodando?
& 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe' showvminfo Ubuntu-Supabase --machinereadable | Select-String '^VMState='

# 2) A API responde?
try { (Invoke-WebRequest 'http://localhost:8001/rest/v1/' -UseBasicParsing -TimeoutSec 10).StatusCode } catch { $_.Exception.Message }

# 3) O console da VM mostra erro? (gera um PNG para abrir)
& 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe' controlvm Ubuntu-Supabase screenshotpng "$env:TEMP\vm.png"
start "$env:TEMP\vm.png"
```

- **VM `poweroff`** → subir: `VBoxManage startvm Ubuntu-Supabase --type headless`
  (ou rodar `INICIAR_FUNNEL_SUPABASE.bat`).
- **Console com `Input/output error`** (disco) → seção 3.2.
- **API 200** → o problema é só o Funnel/Tailscale: `tailscale funnel status`
  e reaplicar (seção 4.6).

### 3.2 Disco da VM com erro de I/O (o caso de 20/10)

1. **Pare o tray** para não inundar o log:
   ```powershell
   Stop-Process -Name SincronizadorNuvem -Force
   ```
2. Desligue a VM com cuidado:
   ```powershell
   & 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe' controlvm Ubuntu-Supabase acpipowerbutton
   # espere ~2 min; se não desligar:
   & 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe' controlvm Ubuntu-Supabase poweroff
   ```
3. Suba de novo e espere a API:
   ```powershell
   & 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe' startvm Ubuntu-Supabase --type headless
   ```
   A API demora ~1 min; confira `http://localhost:8001/rest/v1/` até dar **200**.
4. Confira os containers:
   ```powershell
   ssh -i "$env:USERPROFILE\.ssh\id_ed25519_vm" -p 2222 charles@127.0.0.1 "docker ps --format '{{.Names}} {{.Status}}'"
   ```
   Todos devem estar `healthy`.
5. Suba o tray de novo:
   ```powershell
   Start-Process 'C:\SistemaExodo\SincronizadorNuvem.exe' -WorkingDirectory 'C:\SistemaExodo'
   ```
6. Valide: sem `HTTP 503` novo no log, fila `_exodo_sync_log = 0`, heartbeat em
   `sync_status` atualizado.

> Se o console continuar com erro de I/O ou a VM não bootar, o VDI pode ter corrompido:
> vá para o cenário C (restaurar backup em uma VM nova). **Não fique reiniciando** —
> cada boot escreve no disco com problema.

**Causa raiz em 20/10:** o VDI fica em um **HD externo USB** (`F:`). Um pico de falha
de gravação atrasada do Windows (evento NTFS 50) invalidou o handle do disco na VM.
Recomendações: conferir cabo/alimentação, desativar suspensão seletiva de USB, rodar
`chkdsk F: /scan` e, se possível, mover o VDI para um SSD interno.

---

## 4. Cenário B — migrar para outro PC (ou outro disco)

### 4.1 Antes de começar

- Reserve uma janela sem movimento (o corte derruba o acesso externo por alguns minutos).
- **Não** deixe duas nuvens ativas ao mesmo tempo (duas VMs/Funnels com o mesmo tray =
  dados divergentes). Escolha uma e desligue a outra.
- Tenha o backup mais recente **copiado para fora** do PC antigo.

### 4.2 No PC antigo (congelar)

```powershell
Stop-Process -Name SincronizadorNuvem -Force
powershell -NoProfile -ExecutionPolicy Bypass -File .\backup_nuvem_local.ps1
```

Opcional (migração "idêntica", mais rápida): desligar a VM e exportar/ copiar o disco.

```powershell
& 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe' controlvm Ubuntu-Supabase acpipowerbutton
# depois de desligada:
& 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe' export Ubuntu-Supabase -o 'F:\export\Ubuntu-Supabase.ova'
```

O `.ova` sai com alguns GB (ou copie `F:\VMs\Ubuntu-Supabase\Ubuntu-Supabase.vdi`).
O pacote do `backup_nuvem_local.ps1` (2–3 MB) já basta para o caminho limpo.

### 4.3 No PC novo — opção 1: importar a VM (recomendado se for Windows igual)

1. Instale VirtualBox.
2. `VBoxManage import "F:\export\Ubuntu-Supabase.ova"` (ou dê duplo clique no `.ova`).
3. Confira as portas NAT (Devices → Network → Advanced → Port Forwarding):
   `8001→8000`, `5434→5432`, `6543→6543`, `2222→22`.
4. Inicie a VM (`--type headless`) e espere a API responder em `localhost:8001`.
5. Pule para **4.6** (Funnel) e **4.7** (configurações).

### 4.4 No PC novo — opção 2: VM limpa + restaurar backup

1. Instale VirtualBox, crie uma VM Ubuntu 24.04 (6 GB RAM, 3 CPUs, disco 60 GB),
   instale o Ubuntu Server e o Docker + plugin compose.
2. Copie para a VM a pasta da stack e o pacote de backup:
   ```powershell
   scp -i "$env:USERPROFILE\.ssh\id_ed25519_vm" -P 2222 -r .\supabase charles@127.0.0.1:/home/charles/
   scp -i "$env:USERPROFILE\.ssh\id_ed25519_vm" -P 2222 .\nuvem_AAAAMMDD_HHMMSS.tar.gz charles@127.0.0.1:/tmp/
   ```
3. Extraia o pacote **sobre** a pasta da stack:
   ```bash
   cd /home/charles/supabase
   tar xzf /tmp/nuvem_*.tar.gz
   # o pacote contém docker-compose.yml, .env, volumes/storage e exodo_nuvem.dump
   ```
4. Suba a stack e espere ficar saudável:
   ```bash
   docker compose up -d
   docker ps --format '{{.Names}} {{.Status}}'
   ```
5. Restaure o banco **com o pg_restore de dentro do container** (a versão do
   Postgres é a mesma; o `pg_restore` do Windows/PG16 não lê esse dump):
   ```bash
   # pare quem usa o banco, para o --clean não esbarrar em objetos em uso
   docker compose stop supabase-rest supabase-meta supabase-auth supabase-storage supabase-realtime
   docker cp exodo_nuvem.dump supabase-db:/tmp/
   docker exec supabase-db pg_restore -U supabase_admin -d postgres \
       --clean --if-exists --no-owner /tmp/exodo_nuvem.dump
   docker compose up -d
   ```
   É normal aparecerem alguns avisos de objeto que já existe; o que importa é o
   comando terminar e a API voltar a responder. Se aparecer erro de conexão/lock,
   repita com a stack parada (`docker compose stop`), restaure e suba de novo.
6. Valide a API: `http://localhost:8001/rest/v1/` deve dar **200**.

### 4.5 Restaurar só o banco (nuvem existente, dados perdidos/corrompidos)

Mesmos comandos do item 4.4.5. O `--clean --if-exists` **substitui** os objetos do
banco `postgres` pelo conteúdo do dump — é o comportamento desejado em restauração,
mas confirme que é o backup certo antes de rodar.

### 4.6 Tailscale Funnel no PC novo

Instale o Tailscale, entre na mesma conta e publique as duas portas:

```powershell
& 'C:\Program Files\Tailscale\tailscale.exe' funnel --bg --tls-terminated-tcp=10000 tcp://127.0.0.1:5434
& 'C:\Program Files\Tailscale\tailscale.exe' funnel --bg http://127.0.0.1:8001
& 'C:\Program Files\Tailscale\tailscale.exe' funnel status
```

> O Funnel roda no **Windows**, não dentro da VM. O `INICIAR_FUNNEL_SUPABASE.bat`
> faz isso automaticamente no logon.

**Atenção:** o hostname do Tailscale muda se o PC novo tiver outro nome
(`desktop-xxxx.tail9b4943.ts.net`). Se mudar, atualize os endereços (4.7).

### 4.7 Atualizar configurações (só se URL/chaves mudarem)

| Arquivo | O que conferir |
|---|---|
| `C:\SistemaExodo\.env` | `SUPABASE_URL=http://localhost:8001` (mesmo PC) ou a URL do Funnel (nuvem em outro PC); chaves `SUPABASE_ANON_KEY` / `SERVICE_ROLE_KEY` |
| `assets/app.env` (repo) | `NEON_DATA_API_URL` / `DB_CLOUD_HOST` com o hostname novo; chaves |
| `.env.neon` | só se o provedor for Neon (hoje não é o caso) |

Se o site/app precisa ser republicado:

```powershell
flutter build web --release
firebase deploy --only hosting
```

No celular/APK, o `assets/app.env` vai **embutido**: mudar o hostname exige gerar
um APK novo e reinstalar.

### 4.8 Ligar o sincronizador e validar

```powershell
Start-Process 'C:\SistemaExodo\SincronizadorNuvem.exe' -WorkingDirectory 'C:\SistemaExodo'
```

Checklist:

- [ ] `http://localhost:8001/rest/v1/` → 200
- [ ] Contagens batem com o banco local (`empresas`, `clientes`, `produtos`, `vendas_balcao`, `pedidos`, `nfces`)
- [ ] `_exodo_sync_log` = 0 no Postgres local
- [ ] `sync_status.ultima_sincronizacao` atualizando
- [ ] Log do tray sem `HTTP 503`
- [ ] Login no site e uma venda de teste aparecendo nos dois lados
- [ ] Celular no 4G (fora da loja) acessando pelo Funnel

---

## 5. Cenário C — perdi a VM/o HD (reconstruir do zero)

1. Crie a VM nova e a stack (4.4.1–4.4.4).
2. Restaure o backup mais recente (4.4.5).
3. Se **não houver backup**, ainda dá para reerguer a nuvem a partir do banco local:
   - crie o schema com os SQLs do repo (`CRIAR_TODAS_TABELAS_SUPABASE.sql`,
     `CRIAR_TABELAS_SUPABASE_FALTANTES.sql`, `CONSERTAR_SUPABASE.sql`, RLS etc.);
   - **pare o tray**, reenfileire tudo e suba o tray (são ~17 mil registros no
     estado atual, então pode levar bastante tempo):

   ```sql
   -- Roda no PostgreSQL LOCAL. Reenfileira todas as tabelas que têm trigger de sync.
   DO $$
   DECLARE r record;
   BEGIN
     FOR r IN
       SELECT c.relname AS tabela
       FROM pg_trigger t
       JOIN pg_class c ON c.oid = t.tgrelid
       WHERE t.tgname LIKE 'trg_exodo_sync_log_%' AND NOT t.tgisinternal
     LOOP
       EXECUTE format($f$
         INSERT INTO _exodo_sync_log (table_name, record_id, operation)
         SELECT %L,
                COALESCE(to_jsonb(x)->>'id', to_jsonb(x)->>'chave',
                         to_jsonb(x)->>'key', to_jsonb(x)->>'empresa_id'),
                'UPDATE'
         FROM %I x
         WHERE COALESCE(to_jsonb(x)->>'id', to_jsonb(x)->>'chave',
                        to_jsonb(x)->>'key', to_jsonb(x)->>'empresa_id') IS NOT NULL
         ON CONFLICT (table_name, record_id)
         DO UPDATE SET operation = 'UPDATE', created_at = NOW()
       $f$, r.tabela, r.tabela);
     END LOOP;
   END $$;
   ```

   - **`empresas` não sobe por esse caminho** (o sincronizador trata essa tabela como
     somente leitura). Recrie as empresas na nuvem manualmente/SQL antes de subir o
     restante, senão o site fica sem empresa.
   - **Limitação:** só sobe o que existe no banco local. Dados criados apenas na nuvem
     (ex.: pedidos do celular fora da loja) não voltam. Por isso o backup é importante.

> Se a nuvem ainda estiver **legível** mas com problema, faça um dump dela **antes** de
> apagar/recriar qualquer coisa.

---

## 6. Rotina recomendada

| Frequência | Ação |
|---|---|
| Diária (23:30) | `backup_nuvem_local.ps1` (7 dias) |
| Semanal | copiar a pasta de backup para outro disco/nuvem (Google Drive, OneDrive) |
| Mensal | conferir espaço em `C:` e `F:`; conferir saúde do HD externo |
| Trimestral | **testar o restore** em uma VM de teste |
| Sempre | manter uma cópia de `C:\SistemaExodo\.env` e `assets/app.env` fora do PC (têm chaves) |

Sinais de alerta no Windows: eventos **NTFS 50** ("falha na gravação atrasada"),
**disk 7/11/51/153**, ou o `VBox.log` parar de crescer. Nesses casos, pare o tray,
desligue a VM e faça backup **antes** de reiniciar.

---

## 7. Comandos úteis (cola rápida)

```powershell
# Estado da VM
& 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe' showvminfo Ubuntu-Supabase --machinereadable | Select-String 'VMState|Forwarding'

# Subir VM
& 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe' startvm Ubuntu-Supabase --type headless

# Console (PNG)
& 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe' controlvm Ubuntu-Supabase screenshotpng "$env:TEMP\vm.png"

# Containers
ssh -i "$env:USERPROFILE\.ssh\id_ed25519_vm" -p 2222 charles@127.0.0.1 "docker ps --format '{{.Names}} {{.Status}}'"

# Logs do Postgres/PostgREST
ssh -i "$env:USERPROFILE\.ssh\id_ed25519_vm" -p 2222 charles@127.0.0.1 "docker logs --tail 100 supabase-db; docker logs --tail 100 supabase-rest"

# Backup manual
powershell -NoProfile -ExecutionPolicy Bypass -File .\backup_nuvem_local.ps1

# Fila de sincronização (Postgres local)
psql -h localhost -U exodo_user -d exodo_db -c "SELECT count(*) FROM _exodo_sync_log;"
```
