-- ============================================================
-- CORREÇÃO RLS PARA DESKTOP (Windows/Linux/Mac)
-- Permite INSERT via anon key (não requer autenticação)
-- ============================================================

-- 1. PRODUTOS - Garantir que anon pode inserir/atualizar
DROP POLICY IF EXISTS "insert_anon_produtos" ON produtos;
CREATE POLICY "insert_anon_produtos" ON produtos
FOR INSERT TO anon WITH CHECK (true);

DROP POLICY IF EXISTS "update_anon_produtos" ON produtos;
CREATE POLICY "update_anon_produtos" ON produtos
FOR UPDATE TO anon USING (true) WITH CHECK (true);

-- 2. ABERTURAS_CAIXA - Garantir que anon pode inserir
DROP POLICY IF EXISTS "insert_anon_aberturas_caixa" ON aberturas_caixa;
CREATE POLICY "insert_anon_aberturas_caixa" ON aberturas_caixa
FOR INSERT TO anon WITH CHECK (true);

DROP POLICY IF EXISTS "update_anon_aberturas_caixa" ON aberturas_caixa;
CREATE POLICY "update_anon_aberturas_caixa" ON aberturas_caixa
FOR UPDATE TO anon USING (true) WITH CHECK (true);

-- 3. PRODUTO_HISTORICO - Garantir que anon pode inserir
DROP POLICY IF EXISTS "insert_anon_produto_historico" ON produto_historico;
CREATE POLICY "insert_anon_produto_historico" ON produto_historico
FOR INSERT TO anon WITH CHECK (true);

-- 4. CLIENTES - Garantir que anon pode inserir
DROP POLICY IF EXISTS "insert_anon_clientes" ON clientes;
CREATE POLICY "insert_anon_clientes" ON clientes
FOR INSERT TO anon WITH CHECK (true);

DROP POLICY IF EXISTS "update_anon_clientes" ON clientes;
CREATE POLICY "update_anon_clientes" ON clientes
FOR UPDATE TO anon USING (true) WITH CHECK (true);

-- 5. PERMISSÕES - Grant ALL para anon
GRANT ALL ON produtos TO anon;
GRANT ALL ON aberturas_caixa TO anon;
GRANT ALL ON produto_historico TO anon;
GRANT ALL ON clientes TO anon;
GRANT ALL ON pedidos TO anon;
GRANT ALL ON vendas_balcao TO anon;
GRANT ALL ON ordens_servico TO anon;
GRANT ALL ON entregas TO anon;
GRANT ALL ON servicos TO anon;
GRANT ALL ON nfces TO anon;
GRANT ALL ON notas_entrada TO anon;
GRANT ALL ON funcionarios TO anon;
GRANT ALL ON taxas_entrega TO anon;
GRANT ALL ON contas_pagar TO anon;
GRANT ALL ON agendamentos_servico TO anon;
GRANT ALL ON mesas_comandas TO anon;
GRANT ALL ON links_vendedores TO anon;
GRANT ALL ON comissoes_vendedores TO anon;
GRANT ALL ON sangrias_caixa TO anon;
GRANT ALL ON suprimentos_caixa TO anon;
GRANT ALL ON fechamentos_caixa TO anon;

-- 6. VERIFICAR RESULTADO
SELECT 
    tablename,
    policyname,
    array_to_string(roles, ',') as roles,
    cmd as comando
FROM pg_policies 
WHERE schemaname = 'public'
AND array_to_string(roles, ',') LIKE '%anon%'
ORDER BY tablename, cmd;

SELECT '✅ Políticas RLS para DESKTOP configuradas com sucesso!' as resultado;
