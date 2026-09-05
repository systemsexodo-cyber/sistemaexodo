import os
import json
import urllib.request
import psycopg2
from datetime import datetime, timezone
from dotenv import load_dotenv

load_dotenv()

supabase_url = os.getenv('SUPABASE_URL')
api_key = os.getenv('SUPABASE_SERVICE_ROLE_KEY') or os.getenv('SUPABASE_ANON_KEY')

def parse_id_to_datetime(row_id):
    if not row_id:
        return None
    
    # Try parsing as milliseconds since epoch
    if row_id.isdigit():
        try:
            val = int(row_id)
            # If it's a valid epoch timestamp (milliseconds or seconds)
            if val > 9999999999: # Milliseconds
                return datetime.fromtimestamp(val / 1000.0, tz=timezone.utc)
            else: # Seconds
                return datetime.fromtimestamp(val, tz=timezone.utc)
        except Exception:
            pass
            
    # Try parsing as ISO 8601 date string
    for fmt in ("%Y-%m-%dT%H:%M:%S.%f%z", "%Y-%m-%dT%H:%M:%S%z", "%Y-%m-%d %H:%M:%S.%f%z", "%Y-%m-%d %H:%M:%S%z", "%Y-%m-%d"):
        try:
            # Clean up Z offset to +00:00
            clean_id = row_id.replace('Z', '+00:00')
            return datetime.strptime(clean_id, fmt)
        except Exception:
            pass
            
    # Fallback to tryParse
    try:
        from dateutil import parser
        return parser.parse(row_id).astimezone(timezone.utc)
    except Exception:
        pass
        
    return None

conn = psycopg2.connect(
    host=os.getenv('DB_HOST', 'localhost'),
    port=int(os.getenv('DB_PORT', '5432')),
    database=os.getenv('DB_NAME'),
    user=os.getenv('DB_USER'),
    password=os.getenv('DB_PASSWORD')
)
cur = conn.cursor()

# ─────────────────────────────────────────────────────────────────────────────
# REPARAR FECHAMENTOS_CAIXA
# ─────────────────────────────────────────────────────────────────────────────
print("Reparando fechamentos_caixa...")
cur.execute('SELECT id FROM fechamentos_caixa;')
fechamentos_ids = [row[0] for row in cur.fetchall()]

reparados_fechamentos = 0
for fid in fechamentos_ids:
    dt = parse_id_to_datetime(fid)
    if dt:
        dt_str = dt.isoformat()
        print(f"  • ID: {fid} -> Data: {dt_str}")
        
        # Update local DB
        cur.execute("SET LOCAL exodo.sync_mode = 'on';")
        cur.execute("""
            UPDATE fechamentos_caixa 
            SET data_fechamento = %s, created_at = %s, updated_at = %s,
                "dataFechamento" = NULL, "createdAt" = NULL, "updatedAt" = NULL
            WHERE id = %s;
        """, (dt_str, dt_str, dt_str, fid))
        
        # Update Supabase
        try:
            url = f"{supabase_url.rstrip('/')}/rest/v1/fechamentos_caixa?id=eq.{fid}"
            headers = {
                'Content-Type': 'application/json',
                'apikey': api_key,
                'Authorization': f'Bearer {api_key}',
            }
            data = json.dumps({
                'data_fechamento': dt_str,
                'created_at': dt_str,
                'updated_at': dt_str,
                'dataFechamento': None,
                'createdAt': None,
                'updatedAt': None
            }).encode('utf-8')
            req = urllib.request.Request(url, headers=headers, data=data, method='PATCH')
            with urllib.request.urlopen(req, timeout=5) as r:
                pass
        except Exception as e_sup:
            print(f"    ⚠️ Erro ao atualizar fechamento {fid} no Supabase: {e_sup}")
            
        reparados_fechamentos += 1

# ─────────────────────────────────────────────────────────────────────────────
# REPARAR ABERTURAS_CAIXA
# ─────────────────────────────────────────────────────────────────────────────
print("\nReparando aberturas_caixa...")
cur.execute('SELECT id FROM aberturas_caixa;')
aberturas_ids = [row[0] for row in cur.fetchall()]

reparados_aberturas = 0
for aid in aberturas_ids:
    dt = parse_id_to_datetime(aid)
    if dt:
        dt_str = dt.isoformat()
        print(f"  • ID: {aid} -> Data: {dt_str}")
        
        # Update local DB
        cur.execute("SET LOCAL exodo.sync_mode = 'on';")
        cur.execute("""
            UPDATE aberturas_caixa 
            SET data_abertura = %s, created_at = %s, updated_at = %s,
                "dataAbertura" = NULL, "createdAt" = NULL, "updatedAt" = NULL
            WHERE id = %s;
        """, (dt_str, dt_str, dt_str, aid))
        
        # Update Supabase
        try:
            url = f"{supabase_url.rstrip('/')}/rest/v1/aberturas_caixa?id=eq.{aid}"
            headers = {
                'Content-Type': 'application/json',
                'apikey': api_key,
                'Authorization': f'Bearer {api_key}',
            }
            data = json.dumps({
                'data_abertura': dt_str,
                'created_at': dt_str,
                'updated_at': dt_str,
                'dataAbertura': None,
                'createdAt': None,
                'updatedAt': None
            }).encode('utf-8')
            req = urllib.request.Request(url, headers=headers, data=data, method='PATCH')
            with urllib.request.urlopen(req, timeout=5) as r:
                pass
        except Exception as e_sup:
            print(f"    ⚠️ Erro ao atualizar abertura {aid} no Supabase: {e_sup}")
            
        reparados_aberturas += 1

conn.commit()
print(f"\nReparação completa finalizada!")
print(f"Total de fechamentos reparados: {reparados_fechamentos}")
print(f"Total de aberturas reparadas: {reparados_aberturas}")

cur.close()
conn.close()
