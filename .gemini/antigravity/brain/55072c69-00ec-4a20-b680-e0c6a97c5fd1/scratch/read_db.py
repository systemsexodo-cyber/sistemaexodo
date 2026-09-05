import sqlite3
import os
import json

def find_db():
    documents = os.path.join(os.path.expanduser("~"), "Documents")
    db_path = os.path.join(documents, "exodo_local.db")
    if os.path.exists(db_path):
        return db_path
    
    # Try alternate paths if needed
    return None

def read_tables(db_path):
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
    tables = cursor.fetchall()
    
    results = {}
    for table_name in tables:
        table_name = table_name[0]
        
        # Get row count
        cursor.execute(f"SELECT COUNT(*) FROM {table_name}")
        count = cursor.fetchone()[0]
        
        # Get column names
        cursor.execute(f"PRAGMA table_info({table_name});")
        columns = [col[1] for col in cursor.fetchall()]

        if table_name == 'cache_dados':
            cursor.execute("SELECT chave, length(valor_json), ultima_atualizacao FROM cache_dados")
            rows = cursor.fetchall()
            results[table_name] = {
                "columns": ["Chave", "Tamanho JSON", "Última Atualização"],
                "rows": rows,
                "count": count
            }
        else:
            cursor.execute(f"SELECT * FROM {table_name} LIMIT 10;")
            rows = cursor.fetchall()
            results[table_name] = {
                "columns": columns,
                "rows": rows,
                "count": count
            }
    
    conn.close()
    return results

if __name__ == "__main__":
    db = find_db()
    if db:
        print(f"### Banco de Dados Local (SQLite): {db}")
        data = read_tables(db)
        for table, content in data.items():
            print(f"\n#### Tabela: {table} ({content['count']} registros)")
            print(" | ".join(content["columns"]))
            print("-" * 80)
            for row in content["rows"]:
                print(" | ".join(str(item)[:60] + ("..." if len(str(item)) > 60 else "") for item in row))
    else:
        print("Banco de dados exodo_local.db não encontrado.")
