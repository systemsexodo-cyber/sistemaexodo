from pynfe.entidades.notafiscal import NotaFiscal
from pynfe.entidades.emitente import Emitente
from pynfe.entidades.cliente import Cliente

emitente = Emitente(cnpj='00000000000000', razao_social='Teste')
cliente = Cliente(numero_documento='00000000000', razao_social='Consumidor')

nf = NotaFiscal(emitente=emitente, destinatario=cliente) # Testando 'destinatario'
print(f"Attributes with 'destinatario': {dir(nf)}")

nf2 = NotaFiscal(emitente=emitente, destinatario_remetente=cliente) # Testando 'destinatario_remetente'
print(f"Attributes with 'destinatario_remetente': {dir(nf2)}")
