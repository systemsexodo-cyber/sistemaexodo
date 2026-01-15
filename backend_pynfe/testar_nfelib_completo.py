"""
Teste completo do nfelib com todos os dados preenchidos
Verifica se o XML é gerado corretamente com estrutura completa
"""

import sys
import os
from decimal import Decimal
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

print("=" * 70)
print("TESTE COMPLETO - NFELIB COM TODOS OS DADOS PREENCHIDOS")
print("=" * 70)

try:
    from nfelib.nfe.bindings.v4_0 import envi_nfe_v4_00 as envi_nfe
    from nfelib.nfe.bindings.v4_0 import nfe_v4_00 as nfe
    from nfelib.nfe.bindings.v4_0 import leiaute_nfe_v4_00 as leiaute
    print("✅ Módulos importados com sucesso!")
except ImportError as e:
    print(f"❌ Erro ao importar: {e}")
    sys.exit(1)

# Estrutura de classes
Tnfe = nfe.Tnfe
InfNfe = Tnfe.InfNfe
Det = InfNfe.Det
Imposto = Det.Imposto
Icms = Imposto.Icms

print("\n[1/6] Criando estrutura enviNFe...")
envi_nfe_obj = envi_nfe.TenviNfe()
envi_nfe_obj.versao = "4.00"
envi_nfe_obj.id_lote = "000000000000001"
envi_nfe_obj.ind_sinc = 1
print("✅ enviNFe criado")

print("\n[2/6] Criando estrutura NFe...")
nfe_obj = Tnfe()
nfe_obj.inf_nfe = InfNfe()
nfe_obj.inf_nfe.versao = "4.00"
nfe_obj.inf_nfe.id = "NFe35200100000000000000000000000000000000000000"
print("✅ NFe criada")

print("\n[3/6] Preenchendo IDE (Identificação)...")
nfe_obj.inf_nfe.ide = InfNfe.Ide()
nfe_obj.inf_nfe.ide.c_uf = 35  # SP
nfe_obj.inf_nfe.ide.c_nf = "00000001"
nfe_obj.inf_nfe.ide.nat_op = "VENDA"
nfe_obj.inf_nfe.ide.mod = 65  # NFC-e
nfe_obj.inf_nfe.ide.serie = 1
nfe_obj.inf_nfe.ide.n_nf = 1
nfe_obj.inf_nfe.ide.dh_emi = datetime.now()
nfe_obj.inf_nfe.ide.tp_nf = 1  # Saída
nfe_obj.inf_nfe.ide.id_dest = 1  # Operação interna
nfe_obj.inf_nfe.ide.c_mun_fg = 3550308  # São Paulo
nfe_obj.inf_nfe.ide.tp_imp = 4  # NFC-e
nfe_obj.inf_nfe.ide.tp_emis = 1  # Normal
nfe_obj.inf_nfe.ide.c_dv = 0
nfe_obj.inf_nfe.ide.tp_amb = 2  # Homologação
nfe_obj.inf_nfe.ide.fin_nfe = 1  # Normal
nfe_obj.inf_nfe.ide.ind_final = 1  # Consumidor final
nfe_obj.inf_nfe.ide.ind_pres = 1  # Presencial
nfe_obj.inf_nfe.ide.proc_emi = 0  # Aplicativo próprio
nfe_obj.inf_nfe.ide.ver_proc = "Sistema Exodo 1.0"
print("✅ IDE preenchido")

print("\n[4/6] Preenchendo EMIT (Emitente)...")
nfe_obj.inf_nfe.emit = InfNfe.Emit()
nfe_obj.inf_nfe.emit.cnpj = "00000000000000"
nfe_obj.inf_nfe.emit.x_nome = "EMPRESA TESTE LTDA"
nfe_obj.inf_nfe.emit.x_fant = "TESTE"
nfe_obj.inf_nfe.emit.ie = "000000000000"
nfe_obj.inf_nfe.emit.crt = 1  # Simples Nacional

# Endereço do emitente
nfe_obj.inf_nfe.emit.ender_emit = leiaute.TenderEmi()
nfe_obj.inf_nfe.emit.ender_emit.x_lgr = "Rua Teste"
nfe_obj.inf_nfe.emit.ender_emit.nro = "123"
nfe_obj.inf_nfe.emit.ender_emit.x_bairro = "Centro"
nfe_obj.inf_nfe.emit.ender_emit.c_mun = 3550308
nfe_obj.inf_nfe.emit.ender_emit.x_mun = "São Paulo"
nfe_obj.inf_nfe.emit.ender_emit.uf = "SP"
nfe_obj.inf_nfe.emit.ender_emit.cep = "01000000"
nfe_obj.inf_nfe.emit.ender_emit.c_pais = 1058
nfe_obj.inf_nfe.emit.ender_emit.x_pais = "Brasil"
print("✅ EMIT preenchido")

print("\n[5/6] Preenchendo DET (Produtos)...")
nfe_obj.inf_nfe.det = []

# Produto 1
det1 = Det()
det1.n_item = 1
det1.prod = Det.Prod()
det1.prod.c_prod = "001"
det1.prod.c_ean = "SEM GTIN"
det1.prod.x_prod = "PRODUTO TESTE 1"
det1.prod.ncm = "00000000"
det1.prod.cfop = "5102"
det1.prod.u_com = "UN"
det1.prod.q_com = Decimal("1.0000")
det1.prod.v_un_com = Decimal("10.00")
det1.prod.v_prod = Decimal("10.00")
det1.prod.c_ean_trib = "SEM GTIN"
det1.prod.u_trib = "UN"
det1.prod.q_trib = Decimal("1.0000")
det1.prod.v_un_trib = Decimal("10.00")
det1.prod.ind_tot = 1

# Impostos do produto 1
det1.imposto = Imposto()
det1.imposto.v_tot_trib = Decimal("0.00")

# ICMS
det1.imposto.icms = Icms()
icms_item1 = det1.imposto.icms.Icmssn102()
icms_item1.orig = 0
icms_item1.csosn = "102"
det1.imposto.icms.icmssn102 = icms_item1

# PIS
det1.imposto.pis = Imposto.Pis()
pis_item1 = det1.imposto.pis.Pisoutr()
pis_item1.cst = "99"
pis_item1.v_bc = Decimal("0.00")
pis_item1.p_pis = Decimal("0.00")
pis_item1.v_pis = Decimal("0.00")
det1.imposto.pis.pis_outr = pis_item1

# COFINS
det1.imposto.cofins = Imposto.Cofins()
cofins_item1 = det1.imposto.cofins.Cofinsoutr()
cofins_item1.cst = "99"
cofins_item1.v_bc = Decimal("0.00")
cofins_item1.p_cofins = Decimal("0.00")
cofins_item1.v_cofins = Decimal("0.00")
det1.imposto.cofins.cofins_outr = cofins_item1

nfe_obj.inf_nfe.det.append(det1)
print("✅ Produto 1 adicionado")

# Produto 2
det2 = Det()
det2.n_item = 2
det2.prod = Det.Prod()
det2.prod.c_prod = "002"
det2.prod.c_ean = "SEM GTIN"
det2.prod.x_prod = "PRODUTO TESTE 2"
det2.prod.ncm = "00000000"
det2.prod.cfop = "5102"
det2.prod.u_com = "UN"
det2.prod.q_com = Decimal("2.0000")
det2.prod.v_un_com = Decimal("5.00")
det2.prod.v_prod = Decimal("10.00")
det2.prod.c_ean_trib = "SEM GTIN"
det2.prod.u_trib = "UN"
det2.prod.q_trib = Decimal("2.0000")
det2.prod.v_un_trib = Decimal("5.00")
det2.prod.ind_tot = 1

# Impostos do produto 2
det2.imposto = Imposto()
det2.imposto.v_tot_trib = Decimal("0.00")

# ICMS
det2.imposto.icms = Icms()
icms_item2 = det2.imposto.icms.Icmssn500()
icms_item2.orig = 0
icms_item2.csosn = "500"
det2.imposto.icms.icmssn500 = icms_item2

# PIS
det2.imposto.pis = Imposto.Pis()
pis_item2 = det2.imposto.pis.Pisoutr()
pis_item2.cst = "99"
pis_item2.v_bc = Decimal("0.00")
pis_item2.p_pis = Decimal("0.00")
pis_item2.v_pis = Decimal("0.00")
det2.imposto.pis.pis_outr = pis_item2

# COFINS
det2.imposto.cofins = Imposto.Cofins()
cofins_item2 = det2.imposto.cofins.Cofinsoutr()
cofins_item2.cst = "99"
cofins_item2.v_bc = Decimal("0.00")
cofins_item2.p_cofins = Decimal("0.00")
cofins_item2.v_cofins = Decimal("0.00")
det2.imposto.cofins.cofins_outr = cofins_item2

nfe_obj.inf_nfe.det.append(det2)
print("✅ Produto 2 adicionado")

print("\n[6/6] Preenchendo TOTAL...")
nfe_obj.inf_nfe.total = InfNfe.Total()
nfe_obj.inf_nfe.total.icms_tot = InfNfe.Total.Icmstot()
nfe_obj.inf_nfe.total.icms_tot.v_bc = Decimal("0.00")
nfe_obj.inf_nfe.total.icms_tot.v_icms = Decimal("0.00")
nfe_obj.inf_nfe.total.icms_tot.v_icms_deson = Decimal("0.00")
nfe_obj.inf_nfe.total.icms_tot.v_fcp = Decimal("0.00")
nfe_obj.inf_nfe.total.icms_tot.v_bcst = Decimal("0.00")
nfe_obj.inf_nfe.total.icms_tot.v_st = Decimal("0.00")
nfe_obj.inf_nfe.total.icms_tot.v_fcpst = Decimal("0.00")
nfe_obj.inf_nfe.total.icms_tot.v_prod = Decimal("20.00")
nfe_obj.inf_nfe.total.icms_tot.v_frete = Decimal("0.00")
nfe_obj.inf_nfe.total.icms_tot.v_seg = Decimal("0.00")
nfe_obj.inf_nfe.total.icms_tot.v_desc = Decimal("0.00")
nfe_obj.inf_nfe.total.icms_tot.v_ii = Decimal("0.00")
nfe_obj.inf_nfe.total.icms_tot.v_ipi = Decimal("0.00")
nfe_obj.inf_nfe.total.icms_tot.v_ipi_devol = Decimal("0.00")
nfe_obj.inf_nfe.total.icms_tot.v_pis = Decimal("0.00")
nfe_obj.inf_nfe.total.icms_tot.v_cofins = Decimal("0.00")
nfe_obj.inf_nfe.total.icms_tot.v_outro = Decimal("0.00")
nfe_obj.inf_nfe.total.icms_tot.v_nf = Decimal("20.00")
print("✅ TOTAL preenchido")

# Transporte
print("\n[EXTRA] Preenchendo TRANSP...")
nfe_obj.inf_nfe.transp = InfNfe.Transp()
nfe_obj.inf_nfe.transp.mod_frete = 9  # Sem frete
print("✅ TRANSP preenchido")

# Pagamento
print("\n[EXTRA] Preenchendo PAG...")
nfe_obj.inf_nfe.pag = InfNfe.Pag()
nfe_obj.inf_nfe.pag.det_pag = []

det_pag1 = InfNfe.Pag.DetPag()
det_pag1.ind_pag = 0
det_pag1.t_pag = "01"  # Dinheiro
det_pag1.v_pag = Decimal("20.00")
nfe_obj.inf_nfe.pag.det_pag.append(det_pag1)
print("✅ PAG preenchido")

# Adicionar NFe ao enviNFe
envi_nfe_obj.nfe = [nfe_obj]
print("\n✅ NFe adicionada ao enviNFe")

# Gerar XML
print("\n" + "=" * 70)
print("GERANDO XML...")
print("=" * 70)

try:
    xml_str = envi_nfe_obj.to_xml(pretty_print=False)
    print(f"✅ XML gerado com sucesso!")
    print(f"   Tamanho: {len(xml_str)} caracteres")
    
    # Salvar XML
    xml_file = "teste_nfelib_completo.xml"
    with open(xml_file, 'w', encoding='utf-8') as f:
        f.write(xml_str)
    print(f"✅ XML salvo em: {xml_file}")
    
    # Mostrar primeiras linhas
    print("\nPrimeiras 500 caracteres do XML:")
    print("-" * 70)
    print(xml_str[:500])
    print("-" * 70)
    
    # Verificar elementos importantes
    print("\nVerificando elementos no XML:")
    elementos = {
        'enviNFe': 'enviNFe' in xml_str or 'TEnviNFe' in xml_str,
        'NFe': 'NFe' in xml_str or 'TNFe' in xml_str,
        'infNFe': 'infNFe' in xml_str,
        'ide': 'ide' in xml_str or 'Ide' in xml_str,
        'emit': 'emit' in xml_str or 'Emit' in xml_str,
        'det': 'det' in xml_str or 'Det' in xml_str,
        'prod': 'prod' in xml_str or 'Prod' in xml_str,
        'imposto': 'imposto' in xml_str or 'Imposto' in xml_str,
        'ICMS': 'ICMS' in xml_str or 'Icms' in xml_str,
        'ICMSSN102': 'ICMSSN102' in xml_str or 'Icmssn102' in xml_str,
        'total': 'total' in xml_str or 'Total' in xml_str,
        'pag': 'pag' in xml_str or 'Pag' in xml_str,
    }
    
    for elemento, presente in elementos.items():
        status = "✅" if presente else "❌"
        print(f"   {status} {elemento}")
    
    if len(xml_str) > 1000:
        print(f"\n✅ XML parece completo! ({len(xml_str)} caracteres)")
    else:
        print(f"\n⚠️  XML muito pequeno ({len(xml_str)} caracteres) - pode estar incompleto")
    
except Exception as e:
    print(f"❌ Erro ao gerar XML: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)

print("\n" + "=" * 70)
print("✅ TESTE COMPLETO CONCLUÍDO!")
print("=" * 70)






















