from pynfe.entidades.notafiscal import NotaFiscal
from pynfe.entidades.emitente import Emitente
from pynfe.entidades.cliente import Cliente

emitente = Emitente(cnpj='00000000000000', razao_social='Teste')
cliente = Cliente(numero_documento='00000000000', razao_social='Consumidor')

nf = NotaFiscal(emitente=emitente, destinatario_remetente=cliente)
print(f"Has 'cliente'? {'cliente' in dir(nf)}")
print(f"Has 'destinatario_remetente'? {'destinatario_remetente' in dir(nf)}")
print(f"Has 'destinatario'? {'destinatario' in dir(nf)}")

# Vamos ver se ao atribuir ele muda de nome
nf.cliente = cliente
print("Manual attribution of .cliente success")
