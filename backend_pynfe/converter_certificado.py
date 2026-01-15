#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Script para converter certificado digital (.pfx/.p12) para Base64

Uso:
    python converter_certificado.py caminho/do/certificado.pfx
    python converter_certificado.py  # Pergunta o caminho interativamente
"""

import base64
import sys
import os

def converter_certificado_para_base64(caminho_certificado):
    """
    Converte certificado digital para Base64
    
    Args:
        caminho_certificado: Caminho do arquivo .pfx ou .p12
    
    Returns:
        String Base64 do certificado
    """
    try:
        # Verificar se arquivo existe
        if not os.path.exists(caminho_certificado):
            raise FileNotFoundError(f"Arquivo não encontrado: {caminho_certificado}")
        
        # Ler arquivo
        with open(caminho_certificado, 'rb') as f:
            cert_bytes = f.read()
        
        # Converter para Base64
        cert_base64 = base64.b64encode(cert_bytes).decode('utf-8')
        
        return cert_base64
    
    except Exception as e:
        raise Exception(f"Erro ao converter certificado: {str(e)}")


def main():
    """Função principal"""
    print("=" * 70)
    print("CONVERSOR DE CERTIFICADO DIGITAL PARA BASE64")
    print("=" * 70)
    
    # Obter caminho do certificado
    if len(sys.argv) > 1:
        caminho = sys.argv[1]
    else:
        caminho = input("\nDigite o caminho do certificado (.pfx ou .p12): ").strip()
        
        # Remover aspas se houver
        caminho = caminho.strip('"').strip("'")
    
    if not caminho:
        print("\nERRO: Caminho nao fornecido!")
        return
    
    try:
        print(f"\nConvertendo: {caminho}")
        cert_base64 = converter_certificado_para_base64(caminho)
        
        print("\n" + "=" * 70)
        print("CONVERSAO CONCLUIDA!")
        print("=" * 70)
        print("\nCertificado em Base64 (copie e cole no codigo):")
        print("-" * 70)
        print(cert_base64)
        print("-" * 70)
        
        # Salvar em arquivo também
        arquivo_saida = "certificado_base64.txt"
        with open(arquivo_saida, 'w', encoding='utf-8') as f:
            f.write(cert_base64)
        
        print(f"\nCertificado tambem salvo em: {arquivo_saida}")
        print(f"Tamanho: {len(cert_base64)} caracteres")
        
    except FileNotFoundError as e:
        print(f"\nERRO: {e}")
        print("\nDicas:")
        print("   - Verifique se o caminho esta correto")
        print("   - Use caminho absoluto se necessario")
        print("   - Exemplo: C:\\Users\\SeuUsuario\\certificado.pfx")
    
    except Exception as e:
        print(f"\nERRO: {e}")
        import traceback
        print("\nDetalhes:")
        print(traceback.format_exc())


if __name__ == "__main__":
    main()

