UPDATE empresas 
SET configuracoes = jsonb_set(
    jsonb_set(configuracoes, '{perfis_tributarios}', 
        '[
            {"id": "padrao_tributado_simples", "nome": "Tributado (Simples Nacional)", "cfop": "5102", "csosn": "102", "icms_cst": "", "pis_cst": "99", "cofins_cst": "000", "cst_ibs": "000", "aliquota_ibs": 0.1, "cst_cbs": "000", "aliquota_cbs": 0.9, "c_class_trib": "000001", "is_default": true},
            {"id": "padrao_nao_tributado_simples", "nome": "Nao Tributado (Simples Nacional)", "cfop": "5102", "csosn": "400", "icms_cst": "", "pis_cst": "99", "cofins_cst": "000", "cst_ibs": "000", "aliquota_ibs": 0.1, "cst_cbs": "000", "aliquota_cbs": 0.9, "c_class_trib": "000001", "is_default": false},
            {"id": "padrao_substituicao_simples", "nome": "Substituicao Tributaria (Simples Nacional)", "cfop": "5405", "csosn": "500", "icms_cst": "", "pis_cst": "49", "cofins_cst": "49", "cst_ibs": "000", "aliquota_ibs": 0.1, "cst_cbs": "000", "aliquota_cbs": 0.9, "c_class_trib": "000001", "is_default": false},
            {"id": "padrao_tributado_normal", "nome": "Tributado (Regime Normal)", "cfop": "5102", "csosn": null, "icms_cst": "00", "pis_cst": null, "cofins_cst": null, "cst_ibs": "000", "aliquota_ibs": 0.1, "cst_cbs": "000", "aliquota_cbs": 0.9, "c_class_trib": "000001", "is_default": true},
            {"id": "padrao_nao_tributado_normal", "nome": "Nao Tributado (Regime Normal)", "cfop": "5102", "csosn": null, "icms_cst": "41", "pis_cst": null, "cofins_cst": null, "cst_ibs": "000", "aliquota_ibs": 0.1, "cst_cbs": "000", "aliquota_cbs": 0.9, "c_class_trib": "000001", "is_default": false},
            {"id": "padrao_substituicao_normal", "nome": "Substituicao Tributaria (Regime Normal)", "cfop": "5405", "csosn": null, "icms_cst": "60", "pis_cst": null, "cofins_cst": null, "cst_ibs": "000", "aliquota_ibs": 0.1, "cst_cbs": "000", "aliquota_cbs": 0.9, "c_class_trib": "000001", "is_default": false}
        ]'::jsonb, true),
    '{perfis_tributarios_atualizado_em}', '"2026-11-06T03:23:00.000Z"'::jsonb, true),
    updated_at = NOW()
WHERE id = 'bd45d75b-fee4-4ac2-8975-0f36f61d01bf';

SELECT configuracoes->>'perfis_tributarios_atualizado_em' as carimbo, jsonb_array_length(configuracoes->'perfis_tributarios') as qtd FROM empresas WHERE id='bd45d75b-fee4-4ac2-8975-0f36f61d01bf';