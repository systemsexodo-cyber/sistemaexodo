import base64
import os
import tempfile
from pynfe.processamento.comunicacao import ComunicacaoSefaz
from pynfe.processamento.serializacao import SerializacaoXML
from pynfe.processamento.assinatura import AssinaturaA1
from pynfe.entidades.emitente import Emitente
from pynfe.entidades.cliente import Cliente
from pynfe.entidades.produto import Produto
from pynfe.entidades.notafiscal import NotaFiscal

def emitir_nfce_pynfe(req):
    # Decodificar certificado Base64 para um arquivo temporário
    cert_data = base64.b64decode(req.empresa.certificado_base64)
    with tempfile.NamedTemporaryFile(delete=False, suffix=".pfx") as tmp_cert:
        tmp_cert.write(cert_data)
        caminho_cert = tmp_cert.name

    try:
        senha_cert = req.empresa.senha_certificado
        is_homologacao = (req.empresa.ambiente == 2)

        # Emitente
        emp = req.empresa
        emitente = Emitente(
            cnpj=emp.cnpj,
            razao_social=emp.razao_social,
            nome_fantasia=emp.nome_fantasia,
            inscricao_estadual=emp.inscricao_estadual,
            codigo_de_regime_tributario='1', # 1=Simples Nacional
            endereco_logradouro=emp.logradouro,
            endereco_numero=emp.numero,
            endereco_bairro=emp.bairro,
            endereco_cep=emp.cep,
            endereco_uf=emp.uf,
            endereco_municipio=emp.municipio,
            endereco_cod_municipio=emp.codigo_municipio
        )

        # Cliente (Destinatário)
        cliente = None
        if req.cpf_cliente:
            cliente = Cliente(
                numero_documento=req.cpf_cliente,
                razao_social='Consumidor Final',
                indicador_ie=9, # 9=Não Contribuinte
                endereco_uf=emp.uf
            )

        # Nota Fiscal
        nota_fiscal = NotaFiscal(
            emitente=emitente,
            destinatario_remetente=cliente,
            natureza_operacao='VENDA AO CONSUMIDOR',
            modelo=65, # 65=NFC-e
            serie=1,
            numero_nf=str(req.venda_numero),
            indicador_destino=1, # 1=Interna
            finalidade_emissao=1, # 1=Normal
            cliente_final=1, # 1=Sim
            indicador_presencial=1, # 1=Presencial
            valor_total_nota=req.valor_total,
            uf=emp.uf,
            forma_emissao=1 # 1=Normal
        )
        
        # Data de emissão (precisa ser um datetime object no pynfe)
        from datetime import datetime
        nota_fiscal.data_emissao = datetime.now()

        # Itens
        for item in req.itens:
            # No pynfe 0.6.5 use adicionar_produto_servico diretamente da NotaFiscal
            nota_fiscal.adicionar_produto_servico(
                codigo=item.codigo,
                descricao=item.descricao,
                ncm=item.ncm,
                cfop=item.cfop,
                unidade_comercial='UN',
                quantidade_comercial=item.quantidade,
                valor_unitario_comercial=item.valor_unitario,
                valor_total_bruto=item.valor_total,
                unidade_tributavel='UN',
                quantidade_tributavel=item.quantidade,
                valor_unitario_tributavel=item.valor_unitario,
                icms_origem=0,
                icms_csosn='102'
            )

        # Assinatura
        assinatura = AssinaturaA1(caminho_cert, senha_cert)
        serializador = SerializacaoXML()
        xml_string = serializador.exportar(nota_fiscal)
        
        from lxml import etree
        if isinstance(xml_string, str):
            xml_element = etree.fromstring(xml_string.encode('utf-8'))
        else:
            xml_element = xml_string

        xml_assinado = assinatura.assinar(xml_element)

        # Transmissão
        con = ComunicacaoSefaz(uf=emp.uf, certificado=caminho_cert, certificado_senha=senha_cert, homologacao=is_homologacao)
        status, retorno, nota_envio = con.autorizacao(modelo='nfce', nota_fiscal=xml_assinado)

        # O retorno do autorizacao na 0.6.5 é (status, resposta, nota_xml)
        # status 0 = Sucesso, 1 = Erro
        if status == 0:
            # Em caso de sucesso 'retorno' é o Elemento XML pronto (nfeProc)
            xml_final = etree.tostring(retorno, encoding="unicode")
            # Extrair chave e protocolo se possível
            namespaces = {'ns': 'http://www.portalfiscal.inf.br/nfe'}
            inf_prot = retorno.xpath('//ns:infProt', namespaces=namespaces)
            chave = ''
            protocolo = ''
            if inf_prot:
                chave = inf_prot[0].xpath('ns:chNFe', namespaces=namespaces)[0].text
                protocolo = inf_prot[0].xpath('ns:nProt', namespaces=namespaces)[0].text

            return {
                "status": "sucesso",
                "chave": chave,
                "protocolo": protocolo,
                "xml": xml_final
            }
        else:
            # Em caso de erro 'retorno' é o objeto response do requests ou similar
            try:
                # Se for response do requests
                corpo_erro = retorno.text
                return {"status": "erro", "mensagem": f"Erro SEFAZ: {corpo_erro}"}
            except:
                return {"status": "erro", "mensagem": f"Rejeição ou erro de rede: {str(retorno)}"}
            
    except Exception as e:
        import traceback
        return {"status": "erro", "mensagem": f"Erro interno: {str(e)}", "traceback": traceback.format_exc()}
    finally:
        # Limpar arquivo temporário do certificado
        if os.path.exists(caminho_cert):
            try:
                os.remove(caminho_cert)
            except:
                pass
