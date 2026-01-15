from pynfe.processamento.comunicacao import ComunicacaoSefaz
from pynfe.processamento.serializacao import SerializacaoXML
from pynfe.processamento.assinatura import AssinaturaA1
from pynfe.entidades.emitente import Emitente
from pynfe.entidades.destinatario import Destinatario
from pynfe.entidades.produto import Produto
from pynfe.entidades.notafiscal import NotaFiscal
from pynfe.entidades.fonte_dados import _FonteDados
from pynfe.utils.flags import AMBIENTE_HOMOLOGACAO, AMBIENTE_PRODUCAO

def emitir_nfce_pynfe(dados_venda):
    """
    Função principal para gerar, assinar e transmitir NFC-e usando PyNFe.
    Recebe um objeto 'dados_venda' (dict ou Pydantic model).
    """
    
    # 1. CONFIGURAÇÃO DO CERTIFICADO DIGITAL
    # Você deve colocar o caminho real do seu arquivo .pfx aqui
    certificado = "caminho/para/seu/certificado.pfx" 
    senha_certificado = "sua_senha_aqui"

    # 2. DADOS DO EMITENTE (Sua Empresa)
    emitente = Emitente(
        cnpj='12345678000199',
        razao_social='Minha Empresa Ltda',
        nome_fantasia='Minha Loja',
        inscricao_estadual='123456789',
        codigo_municipio='4106902', # Código IBGE Curitiba (Exemplo)
        uf='PR',
        logradouro='Rua Exemplo',
        numero='100',
        bairro='Centro',
        cep='80000000',
        municipio='Curitiba',
        inscricao_municipal='',
        cnae_fiscal=''
    )

    # 3. DADOS DO DESTINATÁRIO (Opcional na NFC-e se < R$ 10k)
    destinatario = None
    if dados_venda.cpf_cliente:
        destinatario = Destinatario(
            cpf=dados_venda.cpf_cliente,
            nome='Consumidor Final', # Ou nome real se tiver
            indicador_ie=9, # Não contribuinte
            # Endereço é opcional na NFC-e presencial
        )

    # 4. ITENS DA NOTA
    produtos = []
    for item in dados_venda.itens:
        prod = Produto(
            codigo=item.codigo,
            ean='SEM GTIN',
            descricao=item.descricao,
            ncm=item.ncm, # Essencial: NCM correto do produto
            cfop=item.cfop, # Geralmente 5102 para comércio
            unidade_comercial='UN',
            quantidade_comercial=item.quantidade,
            valor_unitario_comercial=item.valor_unitario,
            valor_total_bruto=item.valor_total,
            unidade_tributavel='UN',
            quantidade_tributavel=item.quantidade,
            valor_unitario_tributavel=item.valor_unitario,
            # Impostos devem ser configurados aqui (ICMS, PIS, COFINS)
            # Para Simples Nacional, usar CSOSN
            csosn='102', # Tributada pelo Simples sem permissão de crédito
            origem=0 # Nacional
        )
        produtos.append(prod)

    # 5. MONTAGEM DA NOTA FISCAL
    nota_fiscal = NotaFiscal(
        emitente=emitente,
        destinatario=destinatario,
        produtos=produtos,
        natureza_operacao='VENDA AO CONSUMIDOR',
        modelo=65, # 65 = NFC-e
        serie=1,
        numero=dados_venda.numero,
        tipo_documento=1, # 1=Saída
        id_destinao=1, # 1=Interna
        finalidade_emissao=1, # 1=Normal
        consumidor_final=1, # 1=Sim
        presenca_comprador=1, # 1=Presencial
        valor_total_nota=dados_venda.valor_total,
        valor_produtos=sum(p.valor_total_bruto for p in produtos),
        forma_pagamento=1, # A vista
        modalidade_frete=9 # Sem frete
    )

    # 6. ASSINATURA E SERIALIZAÇÃO
    # Carrega certificado A1
    assinatura = AssinaturaA1(certificado, senha_certificado)
    
    # Gera o XML
    serializador = SerializacaoXML()
    nfe_xml = serializador.exportar(nota_fiscal) # Gera XML não assinado
    
    # Assina o XML
    xml_assinado = assinatura.assinar(nfe_xml)

    # 7. TRANSMISSÃO PARA SEFAZ
    con = ComunicacaoSefaz(uf='PR', certificado=certificado, senha=senha_certificado, ambiente=AMBIENTE_HOMOLOGACAO)
    retorno = con.autorizacao(modelo='nfce', nota_fiscal=xml_assinado)

    # 8. PROCESSAMENTO DO RETORNO
    # Aqui você deve analisar 'retorno' para ver se foi 'Autorizada' ou 'Rejeitada'
    # Exemplo simplificado:
    if retorno['cStat'] == '100':
        return {
            'status': 'sucesso',
            'xml_autorizado': retorno['xml'], # XML com protocolo
            'chave': retorno['chave'],
            'protocolo': retorno['protocolo']
        }
    else:
        raise Exception(f"Erro na emissão: {retorno['xMotivo']} (Cód: {retorno['cStat']})")

