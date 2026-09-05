-- ==========================================================================
-- SCRIPT DE MANUTENÇÃO GLOBAL SUPABASE - SISTEMA ÊXODO
-- ==========================================================================
-- Use este script sempre que criar novas tabelas ou se encontrar erros 
-- de RLS (42501) ou Coluna Não Encontrada (PGRST204) para empresa_id.
-- ==========================================================================

DO $$ 
DECLARE
    t TEXT;
    -- ADICIONE NOVAS TABELAS NESTA LISTA ABAIXO:
    tabelas TEXT[] := ARRAY[
        'produtos', 'clientes', 'servicos', 'pedidos', 'ordens_servico', 
        'entregas', 'vendas_balcao', 'trocas_devolucoes', 'estoque_historico', 
        'produto_historico', 'aberturas_caixa', 'fechamentos_caixa', 
        'sangrias_caixa', 'suprimentos_caixa', 'motoristas', 
        'agendamentos_servico', 'notas_entrada', 'funcionarios', 
        'taxas_entrega', 'contas_pagar', 'nfces', 'nfes', 'mesas_comandas', 
        'links_vendedores', 'comissoes_vendedores', 'romaneios', 'lotes_produto'
    ];
BEGIN
    FOREACH t IN ARRAY tabelas LOOP
        -- 0. Garantir que a tabela exista
        EXECUTE 'CREATE TABLE IF NOT EXISTS ' || t || ' (id TEXT PRIMARY KEY)';
        
        -- 1. Adicionar coluna empresa_id e auditoria se não existirem
        EXECUTE 'ALTER TABLE ' || t || ' ADD COLUMN IF NOT EXISTS empresa_id TEXT';
        EXECUTE 'ALTER TABLE ' || t || ' ADD COLUMN IF NOT EXISTS created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()';
        EXECUTE 'ALTER TABLE ' || t || ' ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()';
        
        -- 2. Habilitar RLS (Row Level Security)
        EXECUTE 'ALTER TABLE ' || t || ' ENABLE ROW LEVEL SECURITY';
        
        -- 3. Criar política de Acesso Total para usuários autenticados
        -- Esta política garante que qualquer pessoa logada no app possa sincronizar dados.
        EXECUTE 'DROP POLICY IF EXISTS ' || t || '_permitir_autenticado ON ' || t;
        EXECUTE 'CREATE POLICY ' || t || '_permitir_autenticado ON ' || t || 
                ' FOR ALL TO authenticated USING (true) WITH CHECK (true)';
                
        -- 4. Criar política de Acesso Total para o service_role (Sistema/Admin)
        EXECUTE 'DROP POLICY IF EXISTS ' || t || '_admin ON ' || t;
        EXECUTE 'CREATE POLICY ' || t || '_admin ON ' || t || 
                ' FOR ALL TO service_role USING (true) WITH CHECK (true)';
                
        RAISE NOTICE 'Tabela % configurada com sucesso.', t;
    END LOOP;
END $$;

-- ==========================================================================
-- AJUSTES ESPECÍFICOS PARA COLUNAS CAMELCASE (DIFERENTES DO PADRÃO)
-- ==========================================================================

-- Notas Fiscais (NFCe)
ALTER TABLE nfces ADD COLUMN IF NOT EXISTS "vendaId" TEXT;
ALTER TABLE nfces ADD COLUMN IF NOT EXISTS "dataEmissao" TIMESTAMP WITH TIME ZONE;

-- Notas de Entrada
ALTER TABLE notas_entrada ADD COLUMN IF NOT EXISTS "dataEmissao" TIMESTAMP WITH TIME ZONE;
ALTER TABLE notas_entrada ADD COLUMN IF NOT EXISTS "valorTotal" NUMERIC;

-- Caixa (Aberturas e Fechamentos)
ALTER TABLE aberturas_caixa ADD COLUMN IF NOT EXISTS "dataAbertura" TIMESTAMP WITH TIME ZONE;
ALTER TABLE aberturas_caixa ADD COLUMN IF NOT EXISTS "valorInicial" NUMERIC;
-- Colunas usadas pelo caixa por usuário (responsavel) e histórico — faltavam e
-- causavam PGRST204, fazendo o sync de aberturas_caixa ser descartado (caixa
-- que "não sobe" para o operador).
ALTER TABLE aberturas_caixa ADD COLUMN IF NOT EXISTS "numero" TEXT;
ALTER TABLE aberturas_caixa ADD COLUMN IF NOT EXISTS "responsavel" TEXT;
ALTER TABLE aberturas_caixa ADD COLUMN IF NOT EXISTS "observacao" TEXT;
ALTER TABLE fechamentos_caixa ADD COLUMN IF NOT EXISTS "aberturaCaixaId" TEXT;
ALTER TABLE fechamentos_caixa ADD COLUMN IF NOT EXISTS "dataFechamento" TIMESTAMP WITH TIME ZONE;
ALTER TABLE fechamentos_caixa ADD COLUMN IF NOT EXISTS "valorEsperado" NUMERIC;
ALTER TABLE fechamentos_caixa ADD COLUMN IF NOT EXISTS "valorReal" NUMERIC;
ALTER TABLE fechamentos_caixa ADD COLUMN IF NOT EXISTS "usuario_id" TEXT;
ALTER TABLE fechamentos_caixa ADD COLUMN IF NOT EXISTS "numero" TEXT;
ALTER TABLE fechamentos_caixa ADD COLUMN IF NOT EXISTS "diferenca" NUMERIC;
ALTER TABLE fechamentos_caixa ADD COLUMN IF NOT EXISTS "responsavel" TEXT;
ALTER TABLE fechamentos_caixa ADD COLUMN IF NOT EXISTS "observacao" TEXT;
ALTER TABLE fechamentos_caixa ADD COLUMN IF NOT EXISTS "sangrias" JSONB DEFAULT '[]';
ALTER TABLE fechamentos_caixa ADD COLUMN IF NOT EXISTS "suprimentos" JSONB DEFAULT '[]';
-- Sangrias e Suprimentos (mesas de caixa por operador)
ALTER TABLE sangrias_caixa ADD COLUMN IF NOT EXISTS "abertura_caixa_id" TEXT;
ALTER TABLE sangrias_caixa ADD COLUMN IF NOT EXISTS "aberturaCaixaId" TEXT;
ALTER TABLE sangrias_caixa ADD COLUMN IF NOT EXISTS "data" TIMESTAMP WITH TIME ZONE;
ALTER TABLE sangrias_caixa ADD COLUMN IF NOT EXISTS "data_operacao" TIMESTAMP WITH TIME ZONE;
ALTER TABLE sangrias_caixa ADD COLUMN IF NOT EXISTS "dataOperacao" TIMESTAMP WITH TIME ZONE;
ALTER TABLE sangrias_caixa ADD COLUMN IF NOT EXISTS "valor" NUMERIC;
ALTER TABLE sangrias_caixa ADD COLUMN IF NOT EXISTS "motivo" TEXT;
ALTER TABLE sangrias_caixa ADD COLUMN IF NOT EXISTS "responsavel" TEXT;
ALTER TABLE sangrias_caixa ADD COLUMN IF NOT EXISTS "observacao" TEXT;
ALTER TABLE suprimentos_caixa ADD COLUMN IF NOT EXISTS "abertura_caixa_id" TEXT;
ALTER TABLE suprimentos_caixa ADD COLUMN IF NOT EXISTS "aberturaCaixaId" TEXT;
ALTER TABLE suprimentos_caixa ADD COLUMN IF NOT EXISTS "data" TIMESTAMP WITH TIME ZONE;
ALTER TABLE suprimentos_caixa ADD COLUMN IF NOT EXISTS "data_operacao" TIMESTAMP WITH TIME ZONE;
ALTER TABLE suprimentos_caixa ADD COLUMN IF NOT EXISTS "dataOperacao" TIMESTAMP WITH TIME ZONE;
ALTER TABLE suprimentos_caixa ADD COLUMN IF NOT EXISTS "valor" NUMERIC;
ALTER TABLE suprimentos_caixa ADD COLUMN IF NOT EXISTS "motivo" TEXT;
ALTER TABLE suprimentos_caixa ADD COLUMN IF NOT EXISTS "responsavel" TEXT;
ALTER TABLE suprimentos_caixa ADD COLUMN IF NOT EXISTS "observacao" TEXT;

-- Auditoria e Datas Padrão (Algumas tabelas usam camelCase para updatedAt)
ALTER TABLE aberturas_caixa ADD COLUMN IF NOT EXISTS "createdAt" TIMESTAMP WITH TIME ZONE;
ALTER TABLE aberturas_caixa ADD COLUMN IF NOT EXISTS "updatedAt" TIMESTAMP WITH TIME ZONE;
ALTER TABLE fechamentos_caixa ADD COLUMN IF NOT EXISTS "createdAt" TIMESTAMP WITH TIME ZONE;
ALTER TABLE fechamentos_caixa ADD COLUMN IF NOT EXISTS "updatedAt" TIMESTAMP WITH TIME ZONE;
ALTER TABLE funcionarios ADD COLUMN IF NOT EXISTS "createdAt" TIMESTAMP WITH TIME ZONE;
ALTER TABLE funcionarios ADD COLUMN IF NOT EXISTS "updatedAt" TIMESTAMP WITH TIME ZONE;


-- Vendedores e Auditoria na Venda Balcao
ALTER TABLE vendas_balcao ADD COLUMN IF NOT EXISTS "vendedor_id" TEXT;
ALTER TABLE vendas_balcao ADD COLUMN IF NOT EXISTS "vendedor_nome" TEXT;
ALTER TABLE vendas_balcao ADD COLUMN IF NOT EXISTS "usuario_id" TEXT;

-- Ajustes Mesas e Comandas (Snake Case para Supabase)
-- Colunas base (tipo, numero, status são usados no modelo principal)
ALTER TABLE mesas_comandas ADD COLUMN IF NOT EXISTS "tipo" TEXT;
ALTER TABLE mesas_comandas ADD COLUMN IF NOT EXISTS "numero" TEXT;
ALTER TABLE mesas_comandas ADD COLUMN IF NOT EXISTS "status" TEXT DEFAULT 'Aberta';
-- Colunas de cliente e mesa vinculada
ALTER TABLE mesas_comandas ADD COLUMN IF NOT EXISTS "cliente_id" TEXT;
ALTER TABLE mesas_comandas ADD COLUMN IF NOT EXISTS "cliente_nome" TEXT;
ALTER TABLE mesas_comandas ADD COLUMN IF NOT EXISTS "mesa_id" TEXT;
-- Itens e datas
ALTER TABLE mesas_comandas ADD COLUMN IF NOT EXISTS "itens" JSONB;
ALTER TABLE mesas_comandas ADD COLUMN IF NOT EXISTS "data_abertura" TIMESTAMP WITH TIME ZONE;
ALTER TABLE mesas_comandas ADD COLUMN IF NOT EXISTS "data_fechamento" TIMESTAMP WITH TIME ZONE;
ALTER TABLE mesas_comandas ADD COLUMN IF NOT EXISTS "observacao" TEXT;
-- NOTA: 'total' é um campo CALCULADO no Dart (getter totalCalculado).
-- Removido do payload antes do upsert em data_service.dart.
-- Mantido aqui apenas como fallback para compatibilidade com versões antigas:
ALTER TABLE mesas_comandas ADD COLUMN IF NOT EXISTS "total" NUMERIC DEFAULT 0;
-- Pagamentos e couvert
ALTER TABLE mesas_comandas ADD COLUMN IF NOT EXISTS "historico_pagamentos" JSONB;
ALTER TABLE mesas_comandas ADD COLUMN IF NOT EXISTS "itens_pagos" JSONB;
ALTER TABLE mesas_comandas ADD COLUMN IF NOT EXISTS "couvert_pago" NUMERIC DEFAULT 0;
-- Couvert artístico
ALTER TABLE mesas_comandas ADD COLUMN IF NOT EXISTS "valor_couvert" NUMERIC;
ALTER TABLE mesas_comandas ADD COLUMN IF NOT EXISTS "quantidade_pessoas_couvert" INTEGER;
ALTER TABLE mesas_comandas ADD COLUMN IF NOT EXISTS "valor_couvert_por_pessoa" NUMERIC;
ALTER TABLE mesas_comandas ADD COLUMN IF NOT EXISTS "nome_quem_pagou_couvert" TEXT;
-- Garçom / Taxa de serviço
ALTER TABLE mesas_comandas ADD COLUMN IF NOT EXISTS "valor_garcom" NUMERIC;
ALTER TABLE mesas_comandas ADD COLUMN IF NOT EXISTS "garcom_retirado" BOOLEAN DEFAULT false;
ALTER TABLE mesas_comandas ADD COLUMN IF NOT EXISTS "garcom_nome" TEXT;
-- Auditoria
ALTER TABLE mesas_comandas ADD COLUMN IF NOT EXISTS "usuario_criou" TEXT;
ALTER TABLE mesas_comandas ADD COLUMN IF NOT EXISTS "usuario_modificou" TEXT;

-- Ajustes para Links de Vendedores e Comissões
ALTER TABLE links_vendedores ADD COLUMN IF NOT EXISTS "funcionarioId" TEXT;
ALTER TABLE links_vendedores ADD COLUMN IF NOT EXISTS "funcionarioNome" TEXT;
ALTER TABLE links_vendedores ADD COLUMN IF NOT EXISTS "codigoLink" TEXT;
ALTER TABLE links_vendedores ADD COLUMN IF NOT EXISTS "urlCompleta" TEXT;
ALTER TABLE links_vendedores ADD COLUMN IF NOT EXISTS "percentualComissao" NUMERIC;
ALTER TABLE links_vendedores ADD COLUMN IF NOT EXISTS "totalVendas" INTEGER;
ALTER TABLE links_vendedores ADD COLUMN IF NOT EXISTS "totalComissao" NUMERIC;
ALTER TABLE links_vendedores ADD COLUMN IF NOT EXISTS "createdAt" TIMESTAMP WITH TIME ZONE;
ALTER TABLE links_vendedores ADD COLUMN IF NOT EXISTS "updatedAt" TIMESTAMP WITH TIME ZONE;

ALTER TABLE comissoes_vendedores ADD COLUMN IF NOT EXISTS "linkVendedorId" TEXT;
ALTER TABLE comissoes_vendedores ADD COLUMN IF NOT EXISTS "funcionarioId" TEXT;
ALTER TABLE comissoes_vendedores ADD COLUMN IF NOT EXISTS "funcionarioNome" TEXT;
ALTER TABLE comissoes_vendedores ADD COLUMN IF NOT EXISTS "pedidoId" TEXT;
ALTER TABLE comissoes_vendedores ADD COLUMN IF NOT EXISTS "pedidoNumero" TEXT;
ALTER TABLE comissoes_vendedores ADD COLUMN IF NOT EXISTS "valorPedido" NUMERIC;
ALTER TABLE comissoes_vendedores ADD COLUMN IF NOT EXISTS "percentualComissao" NUMERIC;
ALTER TABLE comissoes_vendedores ADD COLUMN IF NOT EXISTS "valorComissao" NUMERIC;
ALTER TABLE comissoes_vendedores ADD COLUMN IF NOT EXISTS "dataPagamento" TIMESTAMP WITH TIME ZONE;
ALTER TABLE comissoes_vendedores ADD COLUMN IF NOT EXISTS "createdAt" TIMESTAMP WITH TIME ZONE;
ALTER TABLE comissoes_vendedores ADD COLUMN IF NOT EXISTS "updatedAt" TIMESTAMP WITH TIME ZONE;

-- Romaneios
ALTER TABLE romaneios ADD COLUMN IF NOT EXISTS "numero" TEXT;
ALTER TABLE romaneios ADD COLUMN IF NOT EXISTS "entregaIds" JSONB;
ALTER TABLE romaneios ADD COLUMN IF NOT EXISTS "dataCriacao" TIMESTAMP WITH TIME ZONE;
ALTER TABLE romaneios ADD COLUMN IF NOT EXISTS "dataSaida" TIMESTAMP WITH TIME ZONE;
ALTER TABLE romaneios ADD COLUMN IF NOT EXISTS "dataRetorno" TIMESTAMP WITH TIME ZONE;
ALTER TABLE romaneios ADD COLUMN IF NOT EXISTS "motoristaId" TEXT;
ALTER TABLE romaneios ADD COLUMN IF NOT EXISTS "motoristaNome" TEXT;
ALTER TABLE romaneios ADD COLUMN IF NOT EXISTS "veiculoId" TEXT;
ALTER TABLE romaneios ADD COLUMN IF NOT EXISTS "veiculoPlaca" TEXT;
ALTER TABLE romaneios ADD COLUMN IF NOT EXISTS "status" TEXT;
ALTER TABLE romaneios ADD COLUMN IF NOT EXISTS "observacoes" TEXT;
ALTER TABLE romaneios ADD COLUMN IF NOT EXISTS "pedidosEntregues" JSONB;
ALTER TABLE romaneios ADD COLUMN IF NOT EXISTS "pesoTotal" NUMERIC;
ALTER TABLE romaneios ADD COLUMN IF NOT EXISTS "valorTotal" NUMERIC;

-- Pedidos
ALTER TABLE pedidos ADD COLUMN IF NOT EXISTS "data_entrega" TIMESTAMP WITH TIME ZONE;
ALTER TABLE pedidos ADD COLUMN IF NOT EXISTS "delivery_info" JSONB;

-- Histórico de Estoque e Perfis Tributários
ALTER TABLE estoque_historico ADD COLUMN IF NOT EXISTS "observacao" TEXT;
ALTER TABLE estoque_historico ADD COLUMN IF NOT EXISTS "fornecedor_nome" TEXT;
ALTER TABLE estoque_historico ADD COLUMN IF NOT EXISTS "fornecedor_id" TEXT;
ALTER TABLE estoque_historico ADD COLUMN IF NOT EXISTS "usuario" TEXT;
-- Custo da mercadoria na movimentação (quebras/perdas registram o valor de custo)
ALTER TABLE estoque_historico ADD COLUMN IF NOT EXISTS "custo_unitario" NUMERIC;
ALTER TABLE estoque_historico ADD COLUMN IF NOT EXISTS "valor_custo" NUMERIC;
ALTER TABLE produtos ADD COLUMN IF NOT EXISTS "perfil_tributario_id" TEXT;
ALTER TABLE produtos ADD COLUMN IF NOT EXISTS "impressora_producao_extra" JSONB;
-- Composto que NÃO baixa o próprio estoque (ex.: Chop controlado pelo Barril em ml)
ALTER TABLE produtos ADD COLUMN IF NOT EXISTS "baixar_estoque_proprio" BOOLEAN DEFAULT TRUE;

-- Departamentos (setores de preparação: Cozinha, Bar, Sobremesas, etc.)
ALTER TABLE produtos ADD COLUMN IF NOT EXISTS "departamento_id" TEXT;

-- Venda por caixa/unidade + quantidade de baixa no estoque
ALTER TABLE produtos ADD COLUMN IF NOT EXISTS "unidade_venda" TEXT DEFAULT 'unidade';
ALTER TABLE produtos ADD COLUMN IF NOT EXISTS "quantidade_baixa" NUMERIC DEFAULT 1;
-- Múltiplas formas de venda do mesmo produto (cada uma com preço e baixa próprios)
ALTER TABLE produtos ADD COLUMN IF NOT EXISTS "formas_venda" JSONB;
ALTER TABLE produtos ADD COLUMN IF NOT EXISTS "promocoes" JSONB;
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS "configuracoes" JSONB;

-- Configuração de senhas nos pedidos e vendas
ALTER TABLE pedidos ADD COLUMN IF NOT EXISTS "senha" TEXT;
ALTER TABLE vendas_balcao ADD COLUMN IF NOT EXISTS "senha" TEXT;


-- Entregas: coluna faltante que causava PGRST204 (sync descartado)
ALTER TABLE entregas ADD COLUMN IF NOT EXISTS "enderecoEntrega" TEXT;

-- ==========================================================================
-- CONTROLE DE VALIDADE/LOTE DE PRODUTOS (pet shop: ração, medicamentos, etc.)
-- ==========================================================================
-- Tabela de lotes por produto. A baixa de estoque nas vendas segue FEFO
-- (vence antes, sai antes).
CREATE TABLE IF NOT EXISTS lotes_produto (
    id TEXT PRIMARY KEY,
    produto_id TEXT,
    numero_lote TEXT,
    fornecedor_id TEXT,
    fornecedor_nome TEXT,
    data_fabricacao TIMESTAMP WITH TIME ZONE,
    data_validade TIMESTAMP WITH TIME ZONE,
    quantidade NUMERIC DEFAULT 0,
    empresa_id TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Lote atrelado ao fornecedor: colunas em tabelas já existentes
ALTER TABLE lotes_produto ADD COLUMN IF NOT EXISTS fornecedor_id TEXT;
ALTER TABLE lotes_produto ADD COLUMN IF NOT EXISTS fornecedor_nome TEXT;

-- Índices para consulta rápida de validade/vencimento
CREATE INDEX IF NOT EXISTS idx_lotes_produto_produto_id ON lotes_produto(produto_id);
CREATE INDEX IF NOT EXISTS idx_lotes_produto_data_validade ON lotes_produto(data_validade);
CREATE INDEX IF NOT EXISTS idx_lotes_produto_empresa_id ON lotes_produto(empresa_id);

-- RLS para a nova tabela (acesso via app e service_role)
ALTER TABLE lotes_produto ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS lotes_produto_permitir_autenticado ON lotes_produto;
CREATE POLICY lotes_produto_permitir_autenticado ON lotes_produto
    FOR ALL TO authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS lotes_produto_admin ON lotes_produto;
CREATE POLICY lotes_produto_admin ON lotes_produto
    FOR ALL TO service_role USING (true) WITH CHECK (true);
