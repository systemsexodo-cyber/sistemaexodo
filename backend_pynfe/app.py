"""
Backend Python para emissão de NFC-e usando PyNFe
API REST para comunicação com Flutter
RODANDO LOCALMENTE - Preparado para migração ao Firebase
"""

from flask import Flask, request, jsonify
from flask_cors import CORS
import os
from dotenv import load_dotenv

# Carregar variáveis de ambiente
load_dotenv()

app = Flask(__name__)

# Configurar CORS baseado em variáveis de ambiente
cors_origins = os.getenv('CORS_ORIGINS', '*').split(',')
CORS(app, origins=cors_origins)  # Permitir requisições do Flutter

# Configurar limite de upload
max_content_length = int(os.getenv('MAX_CONTENT_LENGTH', '10485760'))  # 10MB padrão
app.config['MAX_CONTENT_LENGTH'] = max_content_length

# Importar serviços (com tratamento robusto de erros)
PYNFE_DISPONIVEL = False
nfce_service = None

# Importar serviço de certificado
certificado_service = None

print("=" * 50)
print("Carregando serviços...")
print("=" * 50)

try:
    from certificado_service import CertificadoService
    certificado_service = CertificadoService()
    print("[OK] CertificadoService carregado (certificado_service.py)")
except Exception as e:
    try:
        from services.certificado_service import CertificadoService
        certificado_service = CertificadoService()
        print("[OK] CertificadoService carregado (services/certificado_service.py)")
    except Exception as e2:
        print(f"[AVISO] CertificadoService não disponível: {e2}")
        certificado_service = None

try:
    from services.nfce_service import NFCeService, NFELIB_DISPONIVEL
    nfce_service = NFCeService()
    PYNFE_DISPONIVEL = NFELIB_DISPONIVEL  # Usar nfelib agora
    if PYNFE_DISPONIVEL:
        print("[OK] NFCeService carregado (nfelib disponivel)")
    else:
        print("[AVISO] NFCeService carregado mas nfelib nao esta disponivel")
        print("[AVISO] Execute: pip install nfelib signxml cryptography")
except Exception as e:
    print(f"[AVISO] NFCeService nao disponivel: {e}")
    print("[AVISO] nfelib nao esta instalado ou ha erro de importacao")
    PYNFE_DISPONIVEL = False
    nfce_service = None

print("=" * 50)
print()

@app.route('/health', methods=['GET'])
def health():
    """Endpoint de health check"""
    status = {
        'status': 'ok',
        'message': 'Backend NFC-e está funcionando',
        'local': True,
        'pynfe_disponivel': PYNFE_DISPONIVEL,
    }
    
    if not PYNFE_DISPONIVEL:
        status['warning'] = 'nfelib não está instalado. Execute: pip install nfelib signxml cryptography'
    
    return jsonify(status)

@app.route('/api/nfce/emitir', methods=['POST'])
def emitir_nfce():
    """
    Emite uma NFC-e usando implementação manual (sem PyNFe)
    
    Body JSON esperado:
    {
        "empresa": {
            "cnpj": "12345678000190",
            "razao_social": "Empresa Teste",
            "inscricao_estadual": "123456789",
            "certificado_base64": "...",
            "senhaCertificado": "...",
            "uf": "SP",
            "codigo_municipio_ibge": "3550308",
            "serie_nfce": "1",
            "ambienteHomologacao": true
        },
        "produtos": [
            {
                "codigo": "001",
                "descricao": "Produto 1",
                "ncm": "21069090",
                "cfop": "5102",
                "unidade": "UN",
                "quantidade": 1.0,
                "valor_unitario": 10.00,
                "valor_total": 10.00,
                "icms": {"origem": "0", "cst": "102", "aliquota": 18.0}
            }
        ],
        "pagamentos": [
            {"tipo": "01", "valor": 10.00}
        ],
        "consumidor": {"cpf": "12345678901", "nome": "Consumidor Final"},
        "observacoes": "",
        "numero_nfce": 1
    }
    """
    try:
        # Importar implementação manual
        try:
            from nfce_manual_completo import NFCeManualCompleto
        except ImportError:
            return jsonify({
                'success': False,
                'error': 'Módulo nfce_manual_completo não encontrado. Instale: pip install -r requirements_manual.txt'
            }), 503
        
        data = request.get_json()
        
        if not data:
            return jsonify({
                'success': False,
                'error': 'Dados não fornecidos',
                'error_type': 'ValidationError'
            }), 400
        
        # Validar dados obrigatórios com mensagens detalhadas
        erros_validacao = []
        
        if 'empresa' not in data:
            erros_validacao.append('Campo "empresa" é obrigatório')
        else:
            empresa = data['empresa']
            
            # Normalizar nomes de campos (aceitar ambos os formatos)
            if 'senha_certificado' in empresa and 'senhaCertificado' not in empresa:
                empresa['senhaCertificado'] = empresa['senha_certificado']
            if 'senhaCertificado' in empresa and 'senha_certificado' not in empresa:
                empresa['senha_certificado'] = empresa['senhaCertificado']
            
            # Verificar campos obrigatórios (aceitar ambos os formatos)
            campos_obrigatorios_empresa = ['cnpj', 'razao_social', 'uf', 'certificado_base64']
            
            for campo in campos_obrigatorios_empresa:
                if campo not in empresa or not empresa[campo]:
                    erros_validacao.append(f'Campo "empresa.{campo}" é obrigatório')
            
            # Verificar senha (aceitar ambos os formatos)
            tem_senha = ('senhaCertificado' in empresa and empresa['senhaCertificado']) or \
                       ('senha_certificado' in empresa and empresa['senha_certificado'])
            if not tem_senha:
                erros_validacao.append('Campo "empresa.senhaCertificado" ou "empresa.senha_certificado" é obrigatório')
        
        if 'produtos' not in data or not data['produtos']:
            erros_validacao.append('Campo "produtos" é obrigatório e não pode estar vazio')
        
        if 'pagamentos' not in data or not data['pagamentos']:
            erros_validacao.append('Campo "pagamentos" é obrigatório e não pode estar vazio')
        
        if erros_validacao:
            # Log detalhado para debug
            print("\n" + "=" * 70)
            print("ERROS DE VALIDAÇÃO DETECTADOS")
            print("=" * 70)
            print(f"Total de erros: {len(erros_validacao)}")
            for i, erro in enumerate(erros_validacao, 1):
                print(f"  {i}. {erro}")
            print("\nDados recebidos:")
            print(f"  - Tem 'empresa': {'empresa' in data}")
            if 'empresa' in data:
                empresa = data['empresa']
                print(f"    Campos em 'empresa': {list(empresa.keys())}")
                print(f"    - cnpj: {'cnpj' in empresa and empresa['cnpj']}")
                print(f"    - razao_social: {'razao_social' in empresa and empresa['razao_social']}")
                print(f"    - uf: {'uf' in empresa and empresa['uf']}")
                print(f"    - certificado_base64: {'certificado_base64' in empresa and bool(empresa.get('certificado_base64'))}")
                print(f"    - senhaCertificado: {'senhaCertificado' in empresa and bool(empresa.get('senhaCertificado'))}")
            print(f"  - Tem 'produtos': {'produtos' in data}")
            if 'produtos' in data:
                print(f"    Quantidade de produtos: {len(data.get('produtos', []))}")
            print(f"  - Tem 'pagamentos': {'pagamentos' in data}")
            if 'pagamentos' in data:
                print(f"    Quantidade de pagamentos: {len(data.get('pagamentos', []))}")
            print("=" * 70 + "\n")
            
            return jsonify({
                'success': False,
                'error': 'Erros de validação',
                'error_type': 'ValidationError',
                'erros': erros_validacao,
                'dados_recebidos': {
                    'tem_empresa': 'empresa' in data,
                    'tem_produtos': 'produtos' in data and len(data.get('produtos', [])) > 0,
                    'tem_pagamentos': 'pagamentos' in data and len(data.get('pagamentos', [])) > 0,
                    'campos_empresa': list(data.get('empresa', {}).keys()) if 'empresa' in data else []
                }
            }), 400
        
        # USAR NFeLIB DIRETAMENTE (mais confiável que PyNFe para evitar erro 225)
        # O nfelib gera XML conforme o schema XSD oficial da SEFAZ
        usar_nfelib = False
        
        if nfce_service is not None:
            try:
                # Verificar se nfelib está disponível
                if hasattr(nfce_service, 'emitir_nfce'):
                    print("✅ Usando nfelib (NFCeService) para emissão - XML conforme schema XSD")
                    usar_nfelib = True
                else:
                    print("⚠️ NFCeService não tem método emitir_nfce")
            except Exception as e:
                print(f"⚠️ Erro ao verificar NFCeService: {e}")
        
        # Fallback para PyNFe apenas se nfelib não estiver disponível
        usar_pynfe = False
        nfce = None
        
        if not usar_nfelib:
            print("⚠️ nfelib não disponível, tentando PyNFe como fallback...")
            try:
                # Tentar usar a versão nova primeiro
                from nfce_pynfe_novo import criar_servico_nfce_pynfe_novo
                nfce_pynfe = criar_servico_nfce_pynfe_novo()
                if nfce_pynfe:
                    print("✅ Usando PyNFe NOVO (versão limpa) para emissão")
                    usar_pynfe = True
                    nfce = nfce_pynfe
            except Exception as e:
                print(f"❌ ERRO ao carregar PyNFe: {e}")
                import traceback
                traceback.print_exc()
        
        # Verificar se pelo menos um método está disponível
        if not usar_nfelib and not usar_pynfe:
            print("❌ Nenhum método de emissão disponível - ERRO CRÍTICO")
            return jsonify({
                'success': False,
                'error': 'Nenhum método de emissão NFC-e está disponível. É necessário instalar nfelib ou PyNFe.',
                'error_type': 'NoEmissionMethodAvailable',
                'diagnostico': {
                    'sugestao': 'Execute: pip install nfelib signxml cryptography ou pip install pynfe'
                }
            }), 503
        
        # Preparar dados da empresa
        empresa_data = data['empresa'].copy()
        
        # Processar certificado (local ou Firebase)
        if certificado_service is not None:
            try:
                if hasattr(certificado_service, 'processar_empresa_data'):
                    empresa_data = certificado_service.processar_empresa_data(empresa_data)
                    print("✅ Certificado processado (local ou Firebase)")
                else:
                    print("⚠️ CertificadoService não tem método processar_empresa_data, pulando...")
            except Exception as e:
                app.logger.warning(f"Erro ao processar certificado: {e}")
                # Continuar mesmo se falhar (pode ser base64 direto)
        
        # Mapear campos se necessário (apenas para PyNFe)
        if usar_pynfe:
            if 'senha_certificado' in empresa_data and 'senhaCertificado' not in empresa_data:
                empresa_data['senhaCertificado'] = empresa_data.pop('senha_certificado')
            
            if 'ambiente_homologacao' in empresa_data and 'ambienteHomologacao' not in empresa_data:
                empresa_data['ambienteHomologacao'] = empresa_data.pop('ambiente_homologacao')
        
        # Emitir NFC-e
        if usar_nfelib:
            # Usar nfelib (NFCeService) - gera XML conforme schema XSD
            print("🚀 Emitindo NFC-e com nfelib...")
            # Garantir que consumidor seja sempre um dicionário (não None)
            consumidor = data.get('consumidor') or {}
            resultado = nfce_service.emitir_nfce({
                'empresa': empresa_data,
                'produtos': data['produtos'],
                'pagamentos': data['pagamentos'],
                'consumidor': consumidor,
                'observacoes': data.get('observacoes', ''),
                'numero': data.get('numero_nfce', 1)
            })
        else:
            # Usar PyNFe (fallback)
            print("🚀 Emitindo NFC-e com PyNFe...")
            resultado = nfce.emitir(
                empresa_data=empresa_data,
                produtos=data['produtos'],
                pagamentos=data['pagamentos'],
                consumidor=data.get('consumidor'),
                observacoes=data.get('observacoes', ''),
                numero_nfce=data.get('numero_nfce', 1)
            )
        
        # Retornar resultado
        if resultado.get('success'):
            return jsonify(resultado), 200
        else:
            # Determinar status code baseado no tipo de erro
            error_type = resultado.get('error_type', 'UnknownError')
            
            # Log detalhado do erro
            print("\n" + "=" * 60)
            print("ERRO NA EMISSÃO NFC-e")
            print("=" * 60)
            print(f"Tipo: {error_type}")
            print(f"Erro: {resultado.get('error', 'N/A')}")
            if 'codigo_erro' in resultado:
                print(f"Código SEFAZ: {resultado['codigo_erro']}")
            print("=" * 60)
            
            # Status codes
            if error_type in ['ValidationError', 'CertificateMissing', 'CertificateError']:
                status_code = 400
            elif error_type in ['SEFAZRejection']:
                # Rejeição da SEFAZ - retornar 400 com detalhes
                status_code = 400
                # Adicionar informações úteis
                if 'codigo_erro' in resultado:
                    resultado['mensagem_sefaz'] = f"SEFAZ rejeitou com código {resultado['codigo_erro']}"
            else:
                status_code = 500
            
            return jsonify(resultado), status_code
        
    except Exception as e:
        import traceback
        error_details = traceback.format_exc()
        error_message = str(e)
        
        print("=" * 50)
        print("❌ ERRO ao emitir NFC-e")
        print("=" * 50)
        print(f"Erro: {error_message}")
        print(f"Tipo: {type(e).__name__}")
        print("")
        print("Traceback completo:")
        print(error_details)
        print("=" * 50)
        
        # Garantir que sempre há uma mensagem de erro válida
        if not error_message or error_message.strip() == '':
            error_message = f'Erro do tipo {type(e).__name__} ocorreu durante a emissão da NFC-e'
        
        # Criar mensagem de erro mais detalhada
        error_response = {
            'success': False,
            'error': error_message,
            'error_type': type(e).__name__,
        }
        
        # Sempre incluir detalhes em modo debug ou se for erro conhecido
        if os.getenv('DEBUG', 'True').lower() == 'true' or 'AttributeError' in error_details:
            error_response['details'] = error_details
            error_response['traceback'] = error_details.split('\n')[-10:]  # Últimas 10 linhas
        
        return jsonify(error_response), 500

@app.route('/api/nfce/consultar', methods=['POST'])
def consultar_nfce():
    """
    Consulta status de uma NFC-e
    
    Body JSON esperado:
    {
        "chave_acesso": "35200112345678000190650010000000011234567890",
        "empresa": {
            "cnpj": "12345678000190",
            "certificado_base64": "...",
            "senha_certificado": "...",
            "ambiente_homologacao": true
        }
    }
    """
    if not PYNFE_DISPONIVEL:
        return jsonify({
            'success': False,
            'error': 'nfelib não está instalado'
        }), 503
    
    try:
        data = request.get_json()
        
        if not data or 'chave_acesso' not in data:
            return jsonify({
                'success': False,
                'error': 'Chave de acesso não fornecida'
            }), 400
        
        resultado = nfce_service.consultar_nfce(data)
        
        return jsonify(resultado)
        
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

@app.route('/api/nfce/cancelar', methods=['POST'])
def cancelar_nfce():
    """Cancela uma NFC-e autorizada"""
    try:
        data = request.get_json(silent=True)
        if not data:
            return jsonify({
                'success': False, 
                'error': 'Dados não fornecidos ou JSON inválido',
                'raw_data': request.get_data().decode('utf-8', errors='ignore')
            }), 400
            
        print(f'>>> [API] Recebida solicitação de cancelamento: {data.get("chave_acesso")}')
        
        if not nfce_service:
            return jsonify({'success': False, 'error': 'Serviço NFCe não inicializado (nfce_service = None)'}), 503
            
        resultado = nfce_service.cancelar_nfce(data)
        
        # Garantir que resultado é serializável ou converter para dict básico
        if not isinstance(resultado, dict):
             resultado = {'success': False, 'error': f'Resultado do serviço inválido: {type(resultado)}'}
             
        return jsonify(resultado), 200 if resultado.get('success') else 500
    except Exception as e:
        import traceback
        print(f'>>> [API] ❌ Erro ao processar cancelamento: {e}')
        traceback.print_exc()
        return jsonify({'success': False, 'error': str(e), 'traceback': traceback.format_exc()}), 500

@app.route('/api/certificado/validar', methods=['POST'])
def validar_certificado():
    """
    Valida um certificado digital antes de usar na emissão (SOLUÇÃO DEFINITIVA)
    
    Body JSON esperado:
    {
        "certificado_base64": "...",
        "senha": "..."
    }
    """
    try:
        data = request.get_json()
        
        if not data:
            return jsonify({
                'success': False,
                'error': 'Dados não fornecidos',
                'error_type': 'ValidationError'
            }), 400
        
        # Buscar certificado de múltiplas fontes
        certificado_base64 = (data.get('certificado_base64') or 
                             data.get('certificado') or
                             data.get('configuracoes', {}).get('certificadoDigitalBytes'))
        
        # Buscar senha de múltiplas fontes
        senha = (data.get('senha') or 
                data.get('senhaCertificado') or 
                data.get('senha_certificado'))
        
        if not certificado_base64:
            return jsonify({
                'success': False,
                'error': 'Certificado não fornecido. Verifique se o campo certificado_base64 está preenchido.',
                'error_type': 'CertificateMissing',
                'diagnostico': {
                    'certificado_base64': data.get('certificado_base64') is not None,
                    'certificado': data.get('certificado') is not None,
                    'configuracoes_certificadoDigitalBytes': data.get('configuracoes', {}).get('certificadoDigitalBytes') is not None,
                }
            }), 400
        
        if not senha:
            return jsonify({
                'success': False,
                'error': 'Senha não fornecida. Verifique se o campo senha está preenchido.',
                'error_type': 'CertificateMissing'
            }), 400
        
        # Usar a mesma lógica de preparação do certificado (SOLUÇÃO DEFINITIVA)
        from nfce_pynfe_completo import NFCePyNFeCompleto
        nfce = NFCePyNFeCompleto()
        
        try:
            print("\n" + "=" * 70)
            print("VALIDAÇÃO DE CERTIFICADO - TESTE COMPLETO")
            print("=" * 70)
            cert_path = nfce._preparar_certificado(certificado_base64, senha)
            
            # Limpar arquivo temporário
            if os.path.exists(cert_path):
                try:
                    os.remove(cert_path)
                except:
                    pass
            
            print("=" * 70)
            print("✅ CERTIFICADO VALIDADO COM SUCESSO!")
            print("=" * 70)
            
            return jsonify({
                'success': True,
                'message': 'Certificado válido e carregado com sucesso',
                'validado': True,
                'certificado_tamanho': len(certificado_base64)
            }), 200
            
        except ValueError as e:
            error_msg = str(e)
            print("=" * 70)
            print("❌ ERRO NA VALIDAÇÃO DO CERTIFICADO")
            print("=" * 70)
            print(f"Erro: {error_msg}")
            print("=" * 70)
            
            return jsonify({
                'success': False,
                'error': error_msg,
                'error_type': 'CertificateError',
                'validado': False,
                'diagnostico': {
                    'certificado_tamanho': len(certificado_base64) if certificado_base64 else 0,
                    'senha_fornecida': bool(senha),
                    'tipo_erro': 'validacao'
                }
            }), 400
        except Exception as e:
            import traceback
            error_msg = str(e)
            traceback_str = traceback.format_exc()
            
            print("=" * 70)
            print("❌ ERRO DESCONHECIDO NA VALIDAÇÃO")
            print("=" * 70)
            print(f"Erro: {error_msg}")
            print(f"Traceback: {traceback_str}")
            print("=" * 70)
            
            return jsonify({
                'success': False,
                'error': f'Erro ao validar certificado: {error_msg}',
                'error_type': 'CertificateError',
                'validado': False,
                'details': error_msg,
                'traceback': traceback_str.split('\n')[-10:],
                'diagnostico': {
                    'certificado_tamanho': len(certificado_base64) if certificado_base64 else 0,
                    'senha_fornecida': bool(senha),
                    'tipo_erro': 'erro_desconhecido'
                }
            }), 400
            
    except Exception as e:
        import traceback
        return jsonify({
            'success': False,
            'error': f'Erro ao processar validação: {str(e)}',
            'error_type': 'UnknownError',
            'details': traceback.format_exc()
        }), 500

if __name__ == '__main__':
    port = int(os.getenv('PORT', 5000))
    debug = os.getenv('DEBUG', 'True').lower() == 'true'
    
    print('=' * 50)
    print('🚀 Backend NFC-e - Modo LOCAL')
    print('=' * 50)
    print(f'📝 Porta: {port}')
    print(f'🐛 Debug: {debug}')
    print(f'🌐 URL: http://localhost:{port}')
    print(f'📡 Health: http://localhost:{port}/health')
    print('=' * 50)
    print('')
    
    if not PYNFE_DISPONIVEL:
        print('⚠️  AVISO: nfelib não está instalado!')
        print('⚠️  Execute: pip install nfelib signxml cryptography')
        print('')
    
    print('Pressione Ctrl+C para parar')
    print('')
    
    try:
        app.run(host='0.0.0.0', port=port, debug=debug, use_reloader=False)
    except Exception as e:
        print(f"❌ ERRO ao iniciar servidor: {e}")
        import traceback
        traceback.print_exc()
        import sys
        sys.exit(1)
