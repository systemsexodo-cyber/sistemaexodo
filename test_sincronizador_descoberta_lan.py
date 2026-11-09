import json
import tempfile
import unittest
import uuid
from pathlib import Path

import sincronizador_descoberta_lan as lan


class DescobertaLanTest(unittest.TestCase):
    def test_identidade_e_persistente(self):
        with tempfile.TemporaryDirectory() as pasta:
            arquivo = Path(pasta) / "device.json"
            primeiro = lan.carregar_ou_criar_device_id(arquivo)
            segundo = lan.carregar_ou_criar_device_id(arquivo)
            self.assertEqual(primeiro, segundo)
            uuid.UUID(primeiro)

    def test_identidade_invalida_e_regenerada(self):
        with tempfile.TemporaryDirectory() as pasta:
            arquivo = Path(pasta) / "device.json"
            arquivo.write_text('{"device_id":"invalido"}', encoding="utf-8")
            novo = lan.carregar_ou_criar_device_id(arquivo)
            uuid.UUID(novo)

    def test_anuncio_nao_contem_credenciais(self):
        device_id = str(uuid.uuid4())
        anuncio = json.loads(lan.criar_anuncio(device_id, 5432))
        self.assertEqual(anuncio["protocol"], lan.PROTOCOLO)
        self.assertEqual(anuncio["device_id"], device_id)
        self.assertNotIn("password", anuncio)
        self.assertNotIn("user", anuncio)
        self.assertNotIn("dbname", anuncio)

    def test_anuncio_valido_e_aceito(self):
        meu = str(uuid.uuid4())
        outro = str(uuid.uuid4())
        par = lan.validar_anuncio(
            lan.criar_anuncio(outro, 5433), "192.168.0.107", meu
        )
        self.assertEqual(par, {
            "device_id": outro, "host": "192.168.0.107", "port": 5433
        })

    def test_ignora_proprio_anuncio(self):
        meu = str(uuid.uuid4())
        self.assertIsNone(lan.validar_anuncio(
            lan.criar_anuncio(meu), "192.168.0.108", meu
        ))

    def test_ignora_protocolo_desconhecido(self):
        meu = str(uuid.uuid4())
        payload = json.dumps({
            "protocol": "outro", "version": 1,
            "device_id": str(uuid.uuid4()), "postgres_port": 5432
        }).encode()
        self.assertIsNone(lan.validar_anuncio(payload, "192.168.0.107", meu))

    def test_ignora_porta_invalida(self):
        meu = str(uuid.uuid4())
        payload = json.dumps({
            "protocol": lan.PROTOCOLO, "version": 1,
            "device_id": str(uuid.uuid4()), "postgres_port": 70000
        }).encode()
        self.assertIsNone(lan.validar_anuncio(payload, "192.168.0.107", meu))


if __name__ == "__main__":
    unittest.main()
