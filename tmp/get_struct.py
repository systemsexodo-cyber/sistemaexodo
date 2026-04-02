import urllib.request, zipfile, io, os

url = 'http://www.nfe.fazenda.gov.br/portal/exibirArquivo.aspx?conteudo=z12Rdoj/6M8='
r = urllib.request.urlopen(url)
z = zipfile.ZipFile(io.BytesIO(r.read()))
data = z.read('nfe_v4.00.xsd').decode('utf-8')
lines = data.split('\n')

start = 0
for i, l in enumerate(lines):
    if 'name="TNFe"' in l:
        start = i
        break

with open(r'c:\Users\USER\.gemini\antigravity\sistema_exodo_01-12\tmp\nfe_v4_out.txt', 'w') as f:
    for i in range(start, start + 20):
        f.write(lines[i] + '\n')
