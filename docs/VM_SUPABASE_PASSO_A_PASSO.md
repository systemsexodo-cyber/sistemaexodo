# 📘 Passo a Passo — Acessando a VM `Ubuntu-Supabase` via SSH

Guia rápido para abrir a máquina virtual (Supabase local) pelo SSH, para os próximos passos.

## Pré-requisitos

- A VM **Ubuntu-Supabase** deve estar **RODANDO** (VirtualBox).
- O **portproxy** deve estar ativo nas portas **2222** (SSH) e **8001** (Kong).
- Chave SSH: `C:\Users\charles\.ssh\id_ed25519_vm`

## Passo 1 — Verificar se a VM está rodando

```powershell
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" list runningvms
```

## Passo 2 — Verificar as portas (2222 = SSH, 8001 = Kong)

```powershell
Get-NetTCPConnection -LocalPort 2222 -State Listen -ErrorAction SilentlyContinue
Get-NetTCPConnection -LocalPort 8001 -State Listen -ErrorAction SilentlyContinue
```

## Passo 3 — Conectar via SSH

```powershell
ssh -i "$env:USERPROFILE\.ssh\id_ed25519_vm" -p 2222 charles@127.0.0.1
```

> Se a VM responder, você verá algo como: `SSH_OK` / hostname `ubuntu-supabase`.

## Passo 4 — Dentro da VM

Comandos úteis:

```bash
# Ver containers em execução
docker ps

# Reiniciar o storage (quando der 503 no /storage)
docker restart supabase-storage

# Ver logs do storage
docker logs supabase-storage --tail 50

# Parar/iniciar containers específicos
docker start supabase-storage
docker stop supabase-storage

# Status geral
docker ps --format '{{.Names}}|{{.Status}}'
```

## Passos comuns

### 🔹 Storage retornando 503

```bash
docker restart supabase-storage
```

Aguardar ~15s e testar:

```bash
curl http://127.0.0.1:8001/storage/v1/object/list?bucket=atualizacoes
```

### 🔹 Kong/PostgREST indisponível

Reiniciar o container do Kong ou subir a VM novamente.

### 🔹 Verificar se o portal está ok

```bash
curl http://127.0.0.1:8090/admin/tabelas
```

## Observações

- A VM fica em `F:\VMs\Ubuntu-Supabase\`.
- O SSH usa porta **2222** (portproxy → guest 22).
- O Kong usa porta **8001** (portproxy → guest 8000).
- Se o SSH não responder, verificar se o portproxy está rodando e se a VM está de fato up.
