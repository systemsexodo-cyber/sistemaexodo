import os
import psycopg2
from dotenv import load_dotenv

load_dotenv()

conn = psycopg2.connect(
    host=os.getenv('DB_HOST', 'localhost'),
    port=int(os.getenv('DB_PORT', '5432')),
    database=os.getenv('DB_NAME'),
    user=os.getenv('DB_USER'),
    password=os.getenv('DB_PASSWORD')
)
cur = conn.cursor()

# Get company
cur.execute("SELECT id, cnpj, nome_fantasia, razao_social FROM empresas WHERE cnpj = '04829400000165';")
print('Company by CNPJ:')
for row in cur.fetchall():
    print(row)

# Get all companies in the DB
cur.execute("SELECT id, cnpj, nome_fantasia, razao_social FROM empresas;")
print('\nAll companies in DB:')
for row in cur.fetchall():
    print(row)

cur.close()
conn.close()
