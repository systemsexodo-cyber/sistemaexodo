import psycopg2, json

conn = psycopg2.connect(dbname='exodo_db', user='exodo_user', password='ex@#$', host='localhost', port=5432)
cur = conn.cursor()
cur.execute('SELECT id, razao_social, configuracoes, "senhaCertificado", csc, "cscIdToken", "ambienteHomologacao" FROM empresas WHERE id = %s;', ('22ae2c16-a730-43f3-a4f9-19f105eb0d13',))
row = cur.fetchone()
conn.close()

data = {'id': row[0], 'razao_social': row[1], 'configuracoes': row[2], 'senha': row[3], 'csc': row[4], 'csc_id': row[5], 'homologacao': row[6]}
with open('empresa_dump.json', 'w') as f:
    json.dump(data, f)
print('Dumped successfully')
