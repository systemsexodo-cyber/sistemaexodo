"""
Serviço para gerenciar certificados digitais
Suporta armazenamento local e Firebase (Storage/Firestore)
"""

import os
import base64
from typing import Optional, Dict, Any
from dotenv import load_dotenv

load_dotenv()

# Firebase (opcional)
FIREBASE_DISPONIVEL = False
try:
    import firebase_admin
    from firebase_admin import credentials, storage, firestore
    FIREBASE_DISPONIVEL = True
except ImportError:
    pass


class CertificadoService:
    """
    Serviço para obter certificados digitais
    Suporta:
    - Base64 direto (local/teste)
    - Firebase Storage (arquivo .pfx)
    - Firebase Firestore (campo base64)
    """
    
    def __init__(self):
        """Inicializa o serviço"""
        self.firebase_app = None
        self._inicializar_firebase()
    
    def _inicializar_firebase(self):
        """Inicializa Firebase se configurado"""
        if not FIREBASE_DISPONIVEL:
            return
        
        # Verificar se Firebase já foi inicializado
        try:
            self.firebase_app = firebase_admin.get_app()
        except ValueError:
            # Inicializar Firebase
            cred_path = os.getenv('FIREBASE_CREDENTIALS_PATH')
            if cred_path and os.path.exists(cred_path):
                cred = credentials.Certificate(cred_path)
                self.firebase_app = firebase_admin.initialize_app(cred, {
                    'storageBucket': os.getenv('FIREBASE_STORAGE_BUCKET')
                })
    
    def obter_certificado_base64(
        self,
        certificado_base64: Optional[str] = None,
        certificado_firebase_path: Optional[str] = None,
        certificado_firestore_collection: Optional[str] = None,
        certificado_firestore_doc: Optional[str] = None,
        certificado_firestore_field: Optional[str] = None
    ) -> str:
        """
        Obtém certificado em Base64 de diferentes fontes
        
        Prioridade:
        1. certificado_base64 (direto)
        2. Firebase Storage (arquivo .pfx)
        3. Firebase Firestore (campo base64)
        
        Args:
            certificado_base64: Certificado já em Base64 (local/teste)
            certificado_firebase_path: Caminho no Firebase Storage (ex: "certificados/empresa123.pfx")
            certificado_firestore_collection: Coleção no Firestore
            certificado_firestore_doc: Documento no Firestore
            certificado_firestore_field: Campo que contém o Base64
        
        Returns:
            Certificado em Base64
        
        Raises:
            ValueError: Se nenhuma fonte válida for encontrada
        """
        # 1. Tentar Base64 direto (local/teste)
        if certificado_base64:
            return certificado_base64.strip()
        
        # 2. Tentar Firebase Storage
        if certificado_firebase_path and FIREBASE_DISPONIVEL:
            try:
                return self._obter_do_firebase_storage(certificado_firebase_path)
            except Exception as e:
                print(f"⚠️ Erro ao obter do Firebase Storage: {e}")
        
        # 3. Tentar Firebase Firestore
        if (certificado_firestore_collection and 
            certificado_firestore_doc and 
            certificado_firestore_field and 
            FIREBASE_DISPONIVEL):
            try:
                return self._obter_do_firestore(
                    certificado_firestore_collection,
                    certificado_firestore_doc,
                    certificado_firestore_field
                )
            except Exception as e:
                print(f"⚠️ Erro ao obter do Firestore: {e}")
        
        raise ValueError(
            "Nenhuma fonte de certificado válida encontrada. "
            "Forneça certificado_base64, certificado_firebase_path ou "
            "certificado_firestore_*"
        )
    
    def _obter_do_firebase_storage(self, path: str) -> str:
        """
        Obtém certificado do Firebase Storage
        
        Args:
            path: Caminho do arquivo no Storage (ex: "certificados/empresa123.pfx")
        
        Returns:
            Certificado em Base64
        """
        if not FIREBASE_DISPONIVEL:
            raise ImportError("Firebase não está disponível")
        
        bucket = storage.bucket()
        blob = bucket.blob(path)
        
        # Baixar arquivo
        cert_bytes = blob.download_as_bytes()
        
        # Converter para Base64
        cert_base64 = base64.b64encode(cert_bytes).decode('utf-8')
        
        return cert_base64
    
    def _obter_do_firestore(
        self,
        collection: str,
        document: str,
        field: str
    ) -> str:
        """
        Obtém certificado do Firestore
        
        Args:
            collection: Nome da coleção
            document: ID do documento
            field: Nome do campo que contém o Base64
        
        Returns:
            Certificado em Base64
        """
        if not FIREBASE_DISPONIVEL:
            raise ImportError("Firebase não está disponível")
        
        db = firestore.client()
        doc_ref = db.collection(collection).document(document)
        doc = doc_ref.get()
        
        if not doc.exists:
            raise ValueError(f"Documento {document} não encontrado em {collection}")
        
        data = doc.to_dict()
        cert_base64 = data.get(field)
        
        if not cert_base64:
            raise ValueError(f"Campo {field} não encontrado no documento")
        
        return cert_base64.strip()
    
    def processar_empresa_data(self, empresa_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Processa dados da empresa e obtém certificado se necessário
        
        Args:
            empresa_data: Dados da empresa (pode conter várias formas de certificado)
        
        Returns:
            empresa_data com certificado_base64 preenchido
        """
        # Se já tem certificado_base64, retornar como está
        if empresa_data.get('certificado_base64'):
            return empresa_data
        
        # Tentar obter do Firebase
        try:
            cert_base64 = self.obter_certificado_base64(
                certificado_base64=empresa_data.get('certificado_base64'),
                certificado_firebase_path=empresa_data.get('certificado_firebase_path'),
                certificado_firestore_collection=empresa_data.get('certificado_firestore_collection'),
                certificado_firestore_doc=empresa_data.get('certificado_firestore_doc'),
                certificado_firestore_field=empresa_data.get('certificado_firestore_field', 'certificado_base64')
            )
            
            # Adicionar ao empresa_data
            empresa_data['certificado_base64'] = cert_base64
            
        except ValueError as e:
            # Se não conseguir obter, manter como está (pode ser erro posterior)
            print(f"⚠️ Aviso: {e}")
        
        return empresa_data


# Instância global
certificado_service = CertificadoService()

















