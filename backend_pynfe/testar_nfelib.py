"""
Script de teste rápido para verificar nfelib e geração de XML NFC-e
Execute: python testar_nfelib.py
"""

import sys
import os
from decimal import Decimal
from datetime import datetime

# Adicionar diretório atual ao path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

print("=" * 60)
print("TESTE RÁPIDO - NFELIB E GERAÇÃO DE XML NFC-e")
print("=" * 60)

# 1. Verificar se nfelib está instalado
print("\n[1/5] Verificando instalação do nfelib...")
try:
    from nfelib.nfe.bindings.v4_0 import envi_nfe_v4_00 as envi_nfe
    from nfelib.nfe.bindings.v4_0 import nfe_v4_00 as nfe
    print("✅ nfelib importado com sucesso!")
except ImportError as e:
    print(f"❌ ERRO: nfelib não está instalado: {e}")
    print("\nExecute: pip install nfelib signxml cryptography")
    sys.exit(1)

# 2. Verificar classes ICMS disponíveis
print("\n[2/5] Verificando classes ICMS disponíveis...")
try:
    # Verificar estrutura aninhada
    Tnfe = nfe.Tnfe
    InfNfe = Tnfe.InfNfe
    Det = InfNfe.Det
    Imposto = Det.Imposto
    Icms = Imposto.Icms
    
    # Listar classes ICMS na estrutura aninhada
    classes_icms = [x for x in dir(Icms) if not x.startswith('_')]
    print(f"✅ Classes ICMS encontradas: {len(classes_icms)}")
    print(f"   Primeiras 20: {classes_icms[:20]}")
    
    # Verificar classes específicas
    tem_102 = hasattr(Icms, 'ICMSSN102')
    tem_500 = hasattr(Icms, 'ICMSSN500')
    tem_icms = hasattr(Imposto, 'Icms')
    tem_imp = hasattr(Det, 'Imposto')
    
    print(f"\n   ICMSSN102: {'✅' if tem_102 else '❌'}")
    print(f"   ICMSSN500: {'✅' if tem_500 else '❌'}")
    print(f"   Icms: {'✅' if tem_icms else '❌'}")
    print(f"   Imposto: {'✅' if tem_imp else '❌'}")
    
except Exception as e:
    print(f"❌ Erro ao verificar classes: {e}")
    import traceback
    traceback.print_exc()

# 3. Testar criação de instâncias ICMS
print("\n[3/5] Testando criação de instâncias ICMS...")
try:
    # Testar estrutura aninhada ICMS
    Tnfe = nfe.Tnfe
    InfNfe = Tnfe.InfNfe
    Det = InfNfe.Det
    Imposto = Det.Imposto
    Icms = Imposto.Icms
    
    # Testar Icms
    icms_obj = Icms()
    print("✅ Icms() criado com sucesso")
    
    # Testar ICMSSN102 usando método do objeto
    if hasattr(icms_obj, 'Icmssn102') and callable(getattr(icms_obj, 'Icmssn102', None)):
        icms_102 = icms_obj.Icmssn102()
        icms_102.orig = 0
        icms_102.csosn = '102'
        print("✅ Icmssn102() criado e configurado com sucesso")
        print(f"   orig = {icms_102.orig}, csosn = {icms_102.csosn}")
    else:
        print("❌ Icmssn102 não encontrado ou não é chamável")
    
    # Testar ICMSSN500 usando método do objeto
    if hasattr(icms_obj, 'Icmssn500') and callable(getattr(icms_obj, 'Icmssn500', None)):
        icms_500 = icms_obj.Icmssn500()
        icms_500.orig = 0
        icms_500.csosn = '500'
        print("✅ Icmssn500() criado e configurado com sucesso")
        print(f"   orig = {icms_500.orig}, csosn = {icms_500.csosn}")
    else:
        print("❌ Icmssn500 não encontrado ou não é chamável")
        
except Exception as e:
    print(f"❌ Erro ao criar instâncias ICMS: {e}")
    import traceback
    traceback.print_exc()

# 4. Testar criação de estrutura básica
print("\n[4/5] Testando criação de estrutura básica NFC-e...")
try:
    # Criar enviNFe
    envi_nfe_obj = envi_nfe.TenviNfe()
    envi_nfe_obj.versao = "4.00"
    envi_nfe_obj.id_lote = "000000000000001"
    envi_nfe_obj.ind_sinc = 1
    print("✅ enviNFe criado")
    
    # Criar NFe
    Tnfe = nfe.Tnfe
    InfNfe = Tnfe.InfNfe
    nfe_obj = Tnfe()
    nfe_obj.inf_nfe = InfNfe()
    nfe_obj.inf_nfe.versao = "4.00"
    nfe_obj.inf_nfe.id = "NFe35200100000000000000000000000000000000000000"
    print("✅ NFe criada")
    
    # Criar IDE
    nfe_obj.inf_nfe.ide = InfNfe.Ide()
    nfe_obj.inf_nfe.ide.c_uf = 35  # SP
    nfe_obj.inf_nfe.ide.c_nf = "00000001"
    nfe_obj.inf_nfe.ide.nat_op = "VENDA"
    nfe_obj.inf_nfe.ide.mod = 65  # NFC-e
    nfe_obj.inf_nfe.ide.serie = 1
    nfe_obj.inf_nfe.ide.n_nf = 1
    nfe_obj.inf_nfe.ide.dh_emi = datetime.now()
    nfe_obj.inf_nfe.ide.tp_nf = 1
    nfe_obj.inf_nfe.ide.id_dest = 1
    nfe_obj.inf_nfe.ide.c_mun_fg = 3550308
    nfe_obj.inf_nfe.ide.tp_imp = 4
    nfe_obj.inf_nfe.ide.tp_emis = 1
    nfe_obj.inf_nfe.ide.c_dv = 0
    nfe_obj.inf_nfe.ide.tp_amb = 2
    nfe_obj.inf_nfe.ide.fin_nfe = 1
    nfe_obj.inf_nfe.ide.ind_final = 1
    nfe_obj.inf_nfe.ide.ind_pres = 1
    nfe_obj.inf_nfe.ide.proc_emi = 0
    nfe_obj.inf_nfe.ide.ver_proc = "Sistema Exodo"
    print("✅ IDE criado")
    
    # Criar EMIT
    nfe_obj.inf_nfe.emit = InfNfe.Emit()
    nfe_obj.inf_nfe.emit.cnpj = "00000000000000"
    nfe_obj.inf_nfe.emit.x_nome = "TESTE LTDA"
    nfe_obj.inf_nfe.emit.x_fant = "TESTE"
    print("✅ EMIT criado")
    
    # Criar DET com produto e ICMS
    Det = InfNfe.Det
    det = Det()
    det.n_item = 1
    det.prod = Det.Prod()
    det.prod.c_prod = "001"
    det.prod.c_ean = "SEM GTIN"
    det.prod.x_prod = "PRODUTO TESTE"
    det.prod.ncm = "00000000"
    det.prod.cfop = "5102"
    det.prod.u_com = "UN"
    det.prod.q_com = Decimal("1.0000")
    det.prod.v_un_com = Decimal("10.00")
    det.prod.v_prod = Decimal("10.00")
    det.prod.c_ean_trib = "SEM GTIN"
    det.prod.u_trib = "UN"
    det.prod.q_trib = Decimal("1.0000")
    det.prod.v_un_trib = Decimal("10.00")
    det.prod.ind_tot = 1
    print("✅ PROD criado")
    
    # Criar IMPOSTO
    Imposto = Det.Imposto
    Icms = Imposto.Icms
    det.imposto = Imposto()
    det.imposto.v_tot_trib = Decimal("0.00")
    print("✅ IMPOSTO criado")
    
    # Criar ICMS
    det.imposto.icms = Icms()
    if hasattr(det.imposto.icms, 'Icmssn102') and callable(getattr(det.imposto.icms, 'Icmssn102', None)):
        icms_item = det.imposto.icms.Icmssn102()
        icms_item.orig = 0
        icms_item.csosn = "102"
        det.imposto.icms.icmssn102 = icms_item
        print("✅ ICMS SN102 criado e atribuído")
    else:
        print("⚠️  Icmssn102 não encontrado, pulando ICMS")
    
    # Adicionar DET à NFe
    nfe_obj.inf_nfe.det = [det]
    print("✅ DET adicionado à NFe")
    
    # Criar TOTAL
    nfe_obj.inf_nfe.total = InfNfe.Total()
    nfe_obj.inf_nfe.total.icms_tot = InfNfe.Total.Icmstot()
    nfe_obj.inf_nfe.total.icms_tot.v_bc = Decimal("0.00")
    nfe_obj.inf_nfe.total.icms_tot.v_icms = Decimal("0.00")
    nfe_obj.inf_nfe.total.icms_tot.v_icms_deson = Decimal("0.00")
    nfe_obj.inf_nfe.total.icms_tot.v_fcp = Decimal("0.00")
    nfe_obj.inf_nfe.total.icms_tot.v_bcst = Decimal("0.00")
    nfe_obj.inf_nfe.total.icms_tot.v_st = Decimal("0.00")
    nfe_obj.inf_nfe.total.icms_tot.v_fcpst = Decimal("0.00")
    nfe_obj.inf_nfe.total.icms_tot.v_prod = Decimal("10.00")
    nfe_obj.inf_nfe.total.icms_tot.v_frete = Decimal("0.00")
    nfe_obj.inf_nfe.total.icms_tot.v_seg = Decimal("0.00")
    nfe_obj.inf_nfe.total.icms_tot.v_desc = Decimal("0.00")
    nfe_obj.inf_nfe.total.icms_tot.v_ii = Decimal("0.00")
    nfe_obj.inf_nfe.total.icms_tot.v_ipi = Decimal("0.00")
    nfe_obj.inf_nfe.total.icms_tot.v_ipi_devol = Decimal("0.00")
    nfe_obj.inf_nfe.total.icms_tot.v_pis = Decimal("0.00")
    nfe_obj.inf_nfe.total.icms_tot.v_cofins = Decimal("0.00")
    nfe_obj.inf_nfe.total.icms_tot.v_outro = Decimal("0.00")
    nfe_obj.inf_nfe.total.icms_tot.v_nf = Decimal("10.00")
    print("✅ TOTAL criado")
    
    # Adicionar NFe ao enviNFe
    envi_nfe_obj.nfe = [nfe_obj]
    print("✅ NFe adicionada ao enviNFe")
    
except Exception as e:
    print(f"❌ Erro ao criar estrutura: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)

# 5. Testar geração de XML
print("\n[5/5] Testando geração de XML...")
try:
    xml_str = envi_nfe_obj.to_xml(pretty_print=False)
    print("✅ XML gerado com sucesso!")
    print(f"   Tamanho: {len(xml_str)} caracteres")
    print(f"   Primeiras 200 caracteres:")
    print("   " + xml_str[:200] + "...")
    
    # Salvar XML de teste
    xml_file = "teste_nfelib.xml"
    with open(xml_file, 'w', encoding='utf-8') as f:
        f.write(xml_str)
    print(f"✅ XML salvo em: {xml_file}")
    
except Exception as e:
    print(f"❌ Erro ao gerar XML: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)

print("\n" + "=" * 60)
print("✅ TESTE CONCLUÍDO COM SUCESSO!")
print("=" * 60)
print("\nPróximos passos:")
print("1. Verifique o arquivo 'teste_nfelib.xml' gerado")
print("2. Se o ICMS funcionou, o XML deve conter <ICMSSN102>")
print("3. Se houver erros, verifique as mensagens acima")
print("\n")

