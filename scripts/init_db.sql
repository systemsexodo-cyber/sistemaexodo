-- ============================================================================
-- INIT_DB.SQL - SISTEMA EXODO (GERADO AUTOMATICAMENTE do schema de referencia)
-- ----------------------------------------------------------------------------
-- Este arquivo e GERADO a partir do pg_dump --schema-only do banco de dados
-- de referencia (dev). NAO edite manualmente: para alterar o schema, altere o
-- banco de referencia e regenere este arquivo.
--
-- Caracteristicas importantes:
--  * Colunas de id/empresa_id sao TEXT (iguais ao Supabase/cloud)
--  * Nao ha tabelas fantasma (itens_pedido/pagamentos/app_update_config)
--  * Triggers outbox (_exodo_sync_log) incluidos
--  * Totalmente IDEMPOTENTE (pode ser executado varias vezes sem erro)
-- ============================================================================

--
-- PostgreSQL database dump
--

-- Dumped from database version 18.4
-- Dumped by pg_dump version 18.4

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: log_sync_event(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.log_sync_event() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
        DECLARE
            rec_id text;
        BEGIN
            -- Se o sincronizador estiver fazendo o insert/update, ignoramos (evita loop infinito)
            IF current_setting('exodo.sync_mode', true) = 'on' THEN
                IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
            END IF;

            -- Se for um UPDATE e nada mudou, ignora o log e notificação (evita loop de re-save do Flutter)
            IF TG_OP = 'UPDATE' AND (NEW IS NOT DISTINCT FROM OLD) THEN
                RETURN NEW;
            END IF;

            IF TG_OP = 'DELETE' THEN
                rec_id := COALESCE(to_jsonb(OLD)->>'id', to_jsonb(OLD)->>'chave', to_jsonb(OLD)->>'key', to_jsonb(OLD)->>'empresa_id');
                IF rec_id IS NOT NULL THEN
                    INSERT INTO _exodo_sync_log (table_name, record_id, operation)
                    VALUES (TG_TABLE_NAME, rec_id, TG_OP)
                    ON CONFLICT (table_name, record_id)
                    DO UPDATE SET operation = EXCLUDED.operation, created_at = NOW();

                    PERFORM pg_notify('exodo_sync_event', TG_TABLE_NAME);
                END IF;
                RETURN OLD;
            ELSE
                rec_id := COALESCE(to_jsonb(NEW)->>'id', to_jsonb(NEW)->>'chave', to_jsonb(NEW)->>'key', to_jsonb(NEW)->>'empresa_id');
                IF rec_id IS NOT NULL THEN
                    INSERT INTO _exodo_sync_log (table_name, record_id, operation)
                    VALUES (TG_TABLE_NAME, rec_id, TG_OP)
                    ON CONFLICT (table_name, record_id)
                    DO UPDATE SET operation = EXCLUDED.operation, created_at = NOW();

                    PERFORM pg_notify('exodo_sync_event', TG_TABLE_NAME);
                END IF;
                RETURN NEW;
            END IF;
        END;
        $$;

--
-- Name: set_sincronizado_false(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.set_sincronizado_false() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    BEGIN
        NEW._sincronizado_nuvem = FALSE;
        RETURN NEW;
    END;
    $$;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: _exodo_sync_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public._exodo_sync_log (
    id integer NOT NULL,
    table_name text NOT NULL,
    record_id text NOT NULL,
    operation text NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);

--
-- Name: _exodo_sync_log_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE IF NOT EXISTS public._exodo_sync_log_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: _exodo_sync_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public._exodo_sync_log_id_seq OWNED BY public._exodo_sync_log.id;

--
-- Name: _sync_controle; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public._sync_controle (
    chave text NOT NULL,
    valor text
);

--
-- Name: aberturas_caixa; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.aberturas_caixa (
    id text NOT NULL,
    empresa_id text,
    operador text,
    valor_inicial bigint,
    data_abertura text,
    observacoes text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    "dataAbertura" timestamp with time zone,
    "valorInicial" numeric,
    "createdAt" timestamp with time zone,
    "updatedAt" timestamp with time zone,
    numero text,
    observacao text,
    responsavel text,
    usuario_id text,
    sync boolean DEFAULT false
);

--
-- Name: agendamentos_servico; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.agendamentos_servico (
    id text NOT NULL,
    empresa_id text,
    numero text,
    data_hora text,
    cliente_id text,
    cliente_nome text,
    pet_id text,
    pet_nome text,
    servicos text,
    valor_total numeric,
    status text,
    operador text,
    observacoes text,
    created_at text,
    updated_at text,
    sync boolean DEFAULT false
);

--
-- Name: bridge_commands; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.bridge_commands (
    id text NOT NULL,
    comando text NOT NULL,
    status text,
    target_pc text,
    resultado text,
    sucesso boolean,
    processor_pc text,
    extra_data text,
    created_at text
);

--
-- Name: bridge_status; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.bridge_status (
    id text NOT NULL,
    pc_name text,
    online boolean,
    ultimo_cnpj text,
    versao_windows text,
    versao_software text,
    ultima_atualizacao text,
    configuracoes text
);

--
-- Name: cache_dados; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.cache_dados (
    chave text NOT NULL,
    valor_json text,
    ultima_atualizacao text
);

--
-- Name: clientes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.clientes (
    id text NOT NULL,
    empresa_id text,
    nome text,
    tipo_pessoa text,
    cpf_cnpj text,
    rg_ie text,
    email text,
    telefone text,
    whatsapp text,
    endereco text,
    numero text,
    bairro text,
    cidade text,
    estado text,
    cep text,
    limite_crediario bigint,
    saldo_crediario bigint,
    pets jsonb,
    ativo boolean,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    bloqueado boolean,
    complemento text,
    nome_fantasia text,
    ponto_referencia text,
    data_nascimento text,
    profissao text,
    foto_path text,
    dados_extras text,
    enderecos jsonb,
    limite_credito numeric,
    saldo_devedor numeric,
    motivo_bloqueio text,
    senha text,
    email_login text,
    habilita_taxi_dog boolean,
    logradouro text,
    observacoes text,
    telefone2 text,
    sync boolean DEFAULT false,
    perfil_preco character varying
);

--
-- Name: comissoes_vendedores; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.comissoes_vendedores (
    id text NOT NULL,
    empresa_id text,
    vendedor_id text,
    vendedor_nome text,
    venda_id text,
    valor_venda numeric,
    percentual numeric,
    valor_comissao numeric,
    status text,
    data_venda text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    "linkVendedorId" text,
    "funcionarioId" text,
    "funcionarioNome" text,
    "pedidoId" text,
    "pedidoNumero" text,
    "valorPedido" numeric,
    "percentualComissao" numeric,
    "valorComissao" numeric,
    "dataPagamento" text,
    "createdAt" timestamp with time zone,
    "updatedAt" timestamp with time zone
);

--
-- Name: contas_pagar; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.contas_pagar (
    id text NOT NULL,
    empresa_id text,
    descricao text NOT NULL,
    valor numeric,
    data_vencimento text,
    data_pagamento text,
    categoria text,
    status text,
    fornecedor text,
    created_at text,
    updated_at text,
    sync boolean DEFAULT false
);

--
-- Name: empresas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.empresas (
    id text NOT NULL,
    razao_social text,
    nome_fantasia text,
    cnpj text,
    email text,
    telefone text,
    endereco text,
    numero text,
    bairro text,
    cidade text,
    estado text,
    cep text,
    slug text,
    certificado_digital_url text,
    senha_certificado text,
    configuracoes jsonb,
    ativo boolean,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    "razaoSocial" text,
    "nomeFantasia" text,
    "inscricaoEstadual" text,
    "inscricaoMunicipal" text,
    crt bigint,
    celular text,
    site text,
    "codigoIBGE" text,
    "logoUrl" text,
    "corPrimaria" text,
    "corSecundaria" text,
    "certificadoDigitalUrl" text,
    "senhaCertificado" text,
    csc text,
    "cscIdToken" text,
    "serieNFCe" text,
    "ambienteHomologacao" boolean,
    "focusNFeToken" text,
    "telasPermitidas" jsonb,
    "whatsappApiUrl" text,
    "whatsappApiKey" text,
    "whatsappInstanceName" text,
    "whatsappTipo" text,
    "whatsappAtivo" boolean,
    "moduloPet" boolean,
    "modelosAdicionais" jsonb,
    "emailContabilidade" text,
    "envioFiscalAutomatico" boolean,
    complemento text,
    "createdAt" timestamp with time zone,
    "updatedAt" timestamp with time zone,
    sync boolean DEFAULT false,
    perfis_de_preco jsonb,
    "perfisDePreco" jsonb
);

--
-- Name: entregas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.entregas (
    id text NOT NULL,
    empresa_id text,
    pedido_id text,
    cliente_id text,
    cliente_nome text,
    motorista_id text,
    motorista_nome text,
    endereco_entrega text,
    status text,
    valor_frete numeric,
    created_at text,
    updated_at text,
    assinatura_recebedor text,
    "assinaturaRecebedor" text,
    "dataEntrega" text,
    "pedidoId" text,
    "pedidoNumero" text,
    "clienteNome" text,
    "clienteTelefone" text,
    logradouro text,
    numero text,
    bairro text,
    cidade text,
    estado text,
    cep text,
    complemento text,
    "pontoReferencia" text,
    "valorFrete" numeric,
    "previsaoEntrega" text,
    observacoes text,
    "codigoRastreio" text,
    sync boolean DEFAULT false
);

--
-- Name: estoque_historico; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.estoque_historico (
    id text NOT NULL,
    empresa_id text,
    produto_id text,
    produto_nome text,
    tipo text,
    quantidade numeric,
    estoque_anterior bigint,
    estoque_atual bigint,
    motivo text,
    operador text,
    data_operacao text,
    created_at timestamp with time zone,
    data timestamp with time zone,
    updated_at timestamp with time zone,
    sync boolean DEFAULT false
);

--
-- Name: exodo_config; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.exodo_config (
    chave text NOT NULL,
    valor text NOT NULL,
    updated_at timestamp without time zone DEFAULT now()
);

--
-- Name: exodo_sync_conflitos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.exodo_sync_conflitos (
    id text NOT NULL,
    tabela text NOT NULL,
    registro_id text NOT NULL,
    dados_locais jsonb,
    dados_nuvem jsonb,
    resolvido boolean DEFAULT false,
    empresa_id text DEFAULT ''::text NOT NULL,
    criado_em timestamp with time zone DEFAULT now()
);

--
-- Name: fechamentos_caixa; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.fechamentos_caixa (
    id text NOT NULL,
    empresa_id text,
    abertura_caixa_id text,
    operador text,
    valor_final bigint,
    data_fechamento text,
    totais jsonb,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    "aberturaCaixaId" timestamp with time zone,
    "dataFechamento" timestamp with time zone,
    "valorEsperado" numeric,
    "valorReal" numeric,
    diferenca numeric,
    sangrias jsonb,
    suprimentos jsonb,
    "createdAt" timestamp with time zone,
    "updatedAt" timestamp with time zone,
    observacao text,
    responsavel text,
    usuario_id text,
    sync boolean DEFAULT false,
    numero character varying
);

--
-- Name: funcionarios; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.funcionarios (
    id text NOT NULL,
    empresa_id text,
    nome text,
    cargo text,
    salario bigint,
    cpf text,
    telefone text,
    ativo boolean,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    email text,
    senha text,
    "createdAt" timestamp with time zone,
    "updatedAt" timestamp with time zone,
    observacoes text,
    "temAcesso" boolean,
    "porcentagemComissao" numeric,
    "tipoComissao" text,
    "valorComissao" numeric,
    sync boolean DEFAULT false
);

--
-- Name: imagens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.imagens (
    id text NOT NULL,
    empresa_id text,
    categoria text,
    nome text,
    url text NOT NULL,
    tamanho_bytes bigint,
    created_at text
);

--
-- Name: links_vendedores; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.links_vendedores (
    id text NOT NULL,
    empresa_id text,
    nome text,
    slug text,
    vendedor_id text,
    vendedor_nome text,
    ativo boolean,
    created_at text,
    updated_at text,
    "funcionarioId" text,
    "funcionarioNome" text,
    "codigoLink" text,
    "urlCompleta" text,
    "percentualComissao" numeric,
    "totalVendas" numeric,
    "totalComissao" numeric,
    "createdAt" text,
    "updatedAt" text
);

--
-- Name: mesas_comandas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.mesas_comandas (
    id text NOT NULL,
    empresa_id text,
    numero text,
    tipo text,
    status text,
    garcom_id text,
    garcom_nome text,
    itens jsonb,
    pagamentos jsonb,
    valor_total numeric,
    clientes_count bigint,
    observacoes text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    cliente_id text,
    cliente_nome text,
    mesa_id text,
    data_abertura timestamp with time zone,
    data_fechamento text,
    historico_pagamentos jsonb,
    itens_pagos jsonb,
    couvert_pago numeric,
    usuario_criou text,
    usuario_modificou text,
    valor_couvert text,
    quantidade_pessoas_couvert text,
    valor_couvert_por_pessoa text,
    nome_quem_pagou_couvert text,
    valor_garcom numeric,
    garcom_retirado boolean,
    observacao text,
    total numeric,
    sync boolean DEFAULT false
);

--
-- Name: motoristas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.motoristas (
    id text NOT NULL,
    empresa_id text,
    nome text NOT NULL,
    telefone text,
    placa text,
    ativo boolean,
    created_at text,
    updated_at text,
    sync boolean DEFAULT false
);

--
-- Name: nfces; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.nfces (
    id text NOT NULL,
    empresa_id text,
    numero text,
    serie text,
    chave_acesso text,
    protocolo text,
    status text,
    valor_total numeric,
    cpf_cnpj_consumidor text,
    nome_consumidor text,
    qr_code text,
    xml_autorizado text,
    data_emissao text,
    itens jsonb,
    pagamentos jsonb,
    created_at text,
    updated_at text,
    "vendaId" text,
    "dataEmissao" text,
    sync boolean DEFAULT false
);

--
-- Name: nfes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.nfes (
    id text NOT NULL,
    numero text,
    serie text,
    data_emissao timestamp with time zone,
    empresa_id text NOT NULL DEFAULT ''::text,
    itens jsonb,
    valor_total numeric,
    cpf_cnpj_consumidor text,
    nome_consumidor text,
    pagamentos jsonb,
    chave_acesso text,
    protocolo text,
    modelo integer DEFAULT 55,
    status text,
    xml_enviado text,
    xml_retorno text,
    qr_code text,
    venda_id text,
    venda_numero text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    sync boolean DEFAULT false
);

--
-- Name: notas_entrada; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.notas_entrada (
    id text NOT NULL,
    empresa_id text,
    numero text,
    fornecedor_nome text,
    itens text,
    valor_total numeric,
    data_entrada text,
    status text,
    created_at text,
    updated_at text,
    "dataEmissao" text,
    "valorTotal" numeric,
    sync boolean DEFAULT false
);

--
-- Name: ordens_servico; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.ordens_servico (
    id text NOT NULL,
    empresa_id text,
    numero text,
    data_abertura text,
    cliente_id text,
    cliente_nome text,
    itens text,
    valor_total numeric,
    status text,
    tecnico text,
    created_at text,
    updated_at text,
    sync boolean DEFAULT false
);

--
-- Name: pedidos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.pedidos (
    id text NOT NULL,
    empresa_id text,
    numero text,
    data_pedido timestamp with time zone,
    cliente_id text,
    cliente_nome text,
    itens jsonb,
    pagamentos jsonb,
    valor_total bigint,
    status text,
    operador text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    cliente_cpf_cnpj text,
    cliente_endereco text,
    vendedor_id text,
    vendedor_nome text,
    link_vendedor_id text,
    link_vendedor_codigo text,
    origem_ecommerce boolean,
    produtos jsonb,
    servicos jsonb,
    materiais_consumidos jsonb,
    delivery_info jsonb,
    cliente_telefone text,
    origem text,
    total numeric,
    observacoes text,
    data_entrega text,
    sync boolean DEFAULT false,
    senha character varying
);

--
-- Name: produto_historico; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.produto_historico (
    id text NOT NULL,
    empresa_id text,
    produto_id text,
    produto_nome text,
    produto_codigo text,
    usuario_id text,
    usuario_nome text,
    usuario_email text,
    tipo_operacao text,
    campos_alterados text,
    valores_anteriores jsonb,
    valores_novos jsonb,
    resumo_mudancas text,
    data_alteracao timestamp with time zone,
    created_at timestamp with time zone,
    updated_at timestamp with time zone
);

--
-- Name: produtos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.produtos (
    id text NOT NULL,
    empresa_id text,
    codigo text,
    codigo_barras text,
    nome text,
    descricao text,
    unidade text,
    grupo text,
    preco numeric,
    preco_custo numeric,
    preco_promocional text,
    tem_promocao boolean,
    estoque numeric,
    estoque_minimo numeric,
    estoque_por_fornecedor jsonb,
    fornecedor_id text,
    fornecedor_nome text,
    fotos jsonb,
    exibir_na_loja boolean,
    em_destaque boolean,
    ncm text,
    cfop text,
    csosn text,
    origem text,
    icms_cst text,
    icms_aliquota text,
    pis_cst text,
    cofins_cst text,
    ativo boolean,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    adicionais jsonb,
    altura_cm text,
    largura_cm text,
    profundidade_cm text,
    peso_gramas text,
    promocao_inicio text,
    promocao_fim text,
    codigos_fornecedor jsonb,
    exibir_na_lo_loja boolean,
    fotos_urls jsonb,
    foto_principal_url text,
    descricao_ecommerce text,
    tags jsonb,
    variacoes jsonb,
    tem_variacoes boolean,
    tem_adicionais boolean,
    observacao_padrao text,
    pedido_compra_gerado boolean,
    data_ultimo_pedido text,
    cest text,
    para_cozinha boolean,
    para_bar boolean,
    cofins_aliquota text,
    pis_aliquota text,
    ipi_aliquota text,
    ipi_cst text,
    simples_nacional_aliquota text,
    iss_aliquota text,
    eh_composto boolean,
    composicao jsonb,
    sync boolean DEFAULT false,
    envia_balanca boolean DEFAULT false,
    perfil_tributario_id character varying,
    perguntas_selecao jsonb,
    exibir_composicao_pdv boolean DEFAULT false,
    precos_por_perfil jsonb,
    regras_quantidade jsonb
);

--
-- Name: romaneios; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.romaneios (
    id text NOT NULL,
    empresa_id text,
    numero text,
    "entregaIds" jsonb,
    "dataCriacao" timestamp with time zone,
    "dataSaida" timestamp with time zone,
    "dataRetorno" text,
    "motoristaId" text,
    "motoristaNome" text,
    "veiculoId" text,
    "veiculoPlaca" text,
    status text,
    observacoes text,
    "pesoTotal" numeric,
    "valorTotal" numeric,
    "pedidosEntregues" jsonb,
    updated_at timestamp with time zone,
    created_at timestamp with time zone,
    sync boolean DEFAULT false
);

--
-- Name: sangrias_caixa; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.sangrias_caixa (
    id text NOT NULL,
    empresa_id text,
    abertura_caixa_id text,
    operador text,
    valor numeric,
    motivo text,
    data_operacao text,
    created_at text,
    updated_at text
);

--
-- Name: servicos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.servicos (
    id text NOT NULL,
    empresa_id text,
    nome text NOT NULL,
    descricao text,
    preco numeric,
    duracao_minutos bigint,
    ativo boolean,
    created_at text,
    updated_at text,
    sync boolean DEFAULT false
);

--
-- Name: suprimentos_caixa; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.suprimentos_caixa (
    id text NOT NULL,
    empresa_id text,
    abertura_caixa_id text,
    operador text,
    valor numeric,
    motivo text,
    data_operacao text,
    created_at text,
    updated_at text
);

--
-- Name: sync_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.sync_logs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    empresa_id text DEFAULT ''::text NOT NULL,
    pc_name text DEFAULT ''::text NOT NULL,
    evento text DEFAULT ''::text NOT NULL,
    detalhes text DEFAULT ''::text,
    erro text DEFAULT ''::text,
    created_at timestamp with time zone DEFAULT now()
);

--
-- Name: sync_status; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.sync_status (
    empresa_id text NOT NULL,
    pc_name text DEFAULT ''::text NOT NULL,
    ultima_sincronizacao timestamp with time zone,
    ultimo_erro text DEFAULT ''::text,
    ultimo_erro_data timestamp with time zone,
    fila_pendente integer DEFAULT 0,
    versao_app text DEFAULT ''::text,
    online boolean DEFAULT false,
    online_data timestamp with time zone,
    updated_at timestamp with time zone DEFAULT now()
);

--
-- Name: taxas_entrega; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.taxas_entrega (
    id text NOT NULL,
    empresa_id text,
    bairro text,
    cidade text,
    valor numeric,
    ativo boolean,
    created_at text,
    updated_at text,
    sync boolean DEFAULT false
);

--
-- Name: trocas_devolucoes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.trocas_devolucoes (
    id text NOT NULL,
    empresa_id text,
    tipo text,
    venda_original_id text,
    cliente_id text,
    cliente_nome text,
    itens text,
    valor_total numeric,
    motivo text,
    operador text,
    data_operacao text,
    created_at text,
    updated_at text,
    sync boolean DEFAULT false
);

--
-- Name: usuarios; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.usuarios (
    id text NOT NULL,
    email text,
    nome text,
    telefone text,
    perfil text,
    email_confirmado boolean DEFAULT false,
    ultimo_acesso text,
    criado_em text,
    atualizado_em text,
    dados_usuario jsonb,
    dados_app jsonb,
    ativo boolean DEFAULT true,
    created_at text,
    updated_at text,
    last_sign_in_at text,
    email_confirmed_at text,
    sync boolean DEFAULT false
);

--
-- Name: vendas_balcao; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.vendas_balcao (
    id text NOT NULL,
    empresa_id text,
    numero text,
    data_venda timestamp with time zone,
    cliente_id text,
    cliente_nome text,
    itens jsonb,
    pagamentos jsonb,
    valor_total numeric,
    valor_desconto bigint,
    tipo_pagamento text,
    operador text,
    status text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    cancelado boolean,
    cliente_cpf_cnpj text,
    delivery_info jsonb,
    cliente_telefone text,
    valor_recebido numeric,
    troco numeric,
    origem text,
    observacoes text,
    vendedor_id text,
    vendedor_nome text,
    usuario_id text,
    sync boolean DEFAULT false,
    senha character varying
);

--
-- Name: vw_historico_recente; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.vw_historico_recente (
    id text NOT NULL,
    empresa_id text,
    produto_id jsonb,
    produto_nome text,
    produto_codigo text,
    usuario_id text,
    usuario_nome text,
    usuario_email text,
    tipo_operacao text,
    campos_alterados text,
    valores_anteriores jsonb,
    valores_novos jsonb,
    resumo_mudancas text,
    data_alteracao timestamp with time zone,
    created_at timestamp with time zone,
    updated_at timestamp with time zone
);

--
-- Name: vw_vendas_detalhado; Type: VIEW; Schema: public; Owner: -
--

CREATE OR REPLACE VIEW public.vw_vendas_detalhado AS
 SELECT v.id,
    COALESCE(e."razaoSocial", e.razao_social) AS empresa_nome,
    v.numero,
    v.data_venda,
    v.valor_total,
    v.tipo_pagamento,
    v.cliente_nome,
    v.operador,
    v.cancelado,
    e.cnpj AS empresa_cnpj,
    v.created_at,
    v.empresa_id
   FROM (public.vendas_balcao v
     LEFT JOIN public.empresas e ON ((v.empresa_id = e.id)));

--
-- Name: _exodo_sync_log id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public._exodo_sync_log ALTER COLUMN id SET DEFAULT nextval('public._exodo_sync_log_id_seq'::regclass);

--
-- Name: _exodo_sync_log _exodo_sync_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = '_exodo_sync_log_pkey' AND connamespace = 'public'::regnamespace) THEN
        ALTER TABLE ONLY public._exodo_sync_log ADD CONSTRAINT _exodo_sync_log_pkey PRIMARY KEY (id);
    END IF;
END $$;

--
-- Name: _exodo_sync_log _exodo_sync_log_table_name_record_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = '_exodo_sync_log_table_name_record_id_key' AND connamespace = 'public'::regnamespace) THEN
        ALTER TABLE ONLY public._exodo_sync_log ADD CONSTRAINT _exodo_sync_log_table_name_record_id_key UNIQUE (table_name, record_id);
    END IF;
END $$;

--
-- Name: _sync_controle _sync_controle_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = '_sync_controle_pkey' AND connamespace = 'public'::regnamespace) THEN
        ALTER TABLE ONLY public._sync_controle ADD CONSTRAINT _sync_controle_pkey PRIMARY KEY (chave);
    END IF;
END $$;

--
-- Name: aberturas_caixa aberturas_caixa_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aberturas_caixa_pkey' AND connamespace = 'public'::regnamespace) THEN
        ALTER TABLE ONLY public.aberturas_caixa ADD CONSTRAINT aberturas_caixa_pkey PRIMARY KEY (id);
    END IF;
END $$;

--
-- Name: agendamentos_servico agendamentos_servico_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'agendamentos_servico_pkey' AND connamespace = 'public'::regnamespace) THEN
        ALTER TABLE ONLY public.agendamentos_servico ADD CONSTRAINT agendamentos_servico_pkey PRIMARY KEY (id);
    END IF;
END $$;

--
-- Name: bridge_commands bridge_commands_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'bridge_commands_pkey' AND connamespace = 'public'::regnamespace) THEN
        ALTER TABLE ONLY public.bridge_commands ADD CONSTRAINT bridge_commands_pkey PRIMARY KEY (id);
    END IF;
END $$;

--
-- Name: bridge_status bridge_status_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'bridge_status_pkey' AND connamespace = 'public'::regnamespace) THEN
        ALTER TABLE ONLY public.bridge_status ADD CONSTRAINT bridge_status_pkey PRIMARY KEY (id);
    END IF;
END $$;

--
-- Name: cache_dados cache_dados_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'cache_dados_pkey' AND connamespace = 'public'::regnamespace) THEN
        ALTER TABLE ONLY public.cache_dados ADD CONSTRAINT cache_dados_pkey PRIMARY KEY (chave);
    END IF;
END $$;

--
-- Name: clientes clientes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'clientes_pkey' AND connamespace = 'public'::regnamespace) THEN
        ALTER TABLE ONLY public.clientes ADD CONSTRAINT clientes_pkey PRIMARY KEY (id);
    END IF;
END $$;

--
-- Name: comissoes_vendedores comissoes_vendedores_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'comissoes_vendedores_pkey' AND connamespace = 'public'::regnamespace) THEN
        ALTER TABLE ONLY public.comissoes_vendedores ADD CONSTRAINT comissoes_vendedores_pkey PRIMARY KEY (id);
    END IF;
END $$;

--
-- Name: contas_pagar contas_pagar_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'contas_pagar_pkey' AND connamespace = 'public'::regnamespace) THEN
        ALTER TABLE ONLY public.contas_pagar ADD CONSTRAINT contas_pagar_pkey PRIMARY KEY (id);
    END IF;
END $$;

--
-- Name: empresas empresas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'empresas_pkey' AND connamespace = 'public'::regnamespace) THEN
        ALTER TABLE ONLY public.empresas ADD CONSTRAINT empresas_pkey PRIMARY KEY (id);
    END IF;
END $$;

--
-- Name: entregas entregas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'entregas_pkey' AND connamespace = 'public'::regnamespace) THEN
        ALTER TABLE ONLY public.entregas ADD CONSTRAINT entregas_pkey PRIMARY KEY (id);
    END IF;
END $$;

--
-- Name: estoque_historico estoque_historico_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'estoque_historico_pkey' AND connamespace = 'public'::regnamespace) THEN
        ALTER TABLE ONLY public.estoque_historico ADD CONSTRAINT estoque_historico_pkey PRIMARY KEY (id);
    END IF;
END $$;

--
-- Name: exodo_config exodo_config_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'exodo_config_pkey' AND connamespace = 'public'::regnamespace) THEN
        ALTER TABLE ONLY public.exodo_config ADD CONSTRAINT exodo_config_pkey PRIMARY KEY (chave);
    END IF;
END $$;

--
-- Name: exodo_sync_conflitos exodo_sync_conflitos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'exodo_sync_conflitos_pkey' AND connamespace = 'public'::regnamespace) THEN
        ALTER TABLE ONLY public.exodo_sync_conflitos ADD CONSTRAINT exodo_sync_conflitos_pkey PRIMARY KEY (id);
    END IF;
END $$;

--
-- Name: fechamentos_caixa fechamentos_caixa_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fechamentos_caixa_pkey' AND connamespace = 'public'::regnamespace) THEN
        ALTER TABLE ONLY public.fechamentos_caixa ADD CONSTRAINT fechamentos_caixa_pkey PRIMARY KEY (id);
    END IF;
END $$;

--
-- Name: funcionarios funcionarios_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'funcionarios_pkey' AND connamespace = 'public'::regnamespace) THEN
        ALTER TABLE ONLY public.funcionarios ADD CONSTRAINT funcionarios_pkey PRIMARY KEY (id);
    END IF;
END $$;

--
-- Name: imagens imagens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'imagens_pkey' AND connamespace = 'public'::regnamespace) THEN
        ALTER TABLE ONLY public.imagens ADD CONSTRAINT imagens_pkey PRIMARY KEY (id);
    END IF;
END $$;

--
-- Name: links_vendedores links_vendedores_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'links_vendedores_pkey' AND connamespace = 'public'::regnamespace) THEN
        ALTER TABLE ONLY public.links_vendedores ADD CONSTRAINT links_vendedores_pkey PRIMARY KEY (id);
    END IF;
END $$;

--
-- Name: mesas_comandas mesas_comandas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'mesas_comandas_pkey' AND connamespace = 'public'::regnamespace) THEN
        ALTER TABLE ONLY public.mesas_comandas ADD CONSTRAINT mesas_comandas_pkey PRIMARY KEY (id);
    END IF;
END $$;

--
-- Name: motoristas motoristas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'motoristas_pkey' AND connamespace = 'public'::regnamespace) THEN
        ALTER TABLE ONLY public.motoristas ADD CONSTRAINT motoristas_pkey PRIMARY KEY (id);
    END IF;
END $$;

--
-- Name: nfces nfces_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'nfces_pkey' AND connamespace = 'public'::regnamespace) THEN
        ALTER TABLE ONLY public.nfces ADD CONSTRAINT nfces_pkey PRIMARY KEY (id);
    END IF;
END $$;

--
-- Name: nfes nfes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'nfes_pkey' AND connamespace = 'public'::regnamespace) THEN
        ALTER TABLE ONLY public.nfes ADD CONSTRAINT nfes_pkey PRIMARY KEY (id);
    END IF;
END $$;

--
-- Name: notas_entrada notas_entrada_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'notas_entrada_pkey' AND connamespace = 'public'::regnamespace) THEN
        ALTER TABLE ONLY public.notas_entrada ADD CONSTRAINT notas_entrada_pkey PRIMARY KEY (id);
    END IF;
END $$;

--
-- Name: ordens_servico ordens_servico_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ordens_servico_pkey' AND connamespace = 'public'::regnamespace) THEN
        ALTER TABLE ONLY public.ordens_servico ADD CONSTRAINT ordens_servico_pkey PRIMARY KEY (id);
    END IF;
END $$;

--
-- Name: pedidos pedidos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'pedidos_pkey' AND connamespace = 'public'::regnamespace) THEN
        ALTER TABLE ONLY public.pedidos ADD CONSTRAINT pedidos_pkey PRIMARY KEY (id);
    END IF;
END $$;

--
-- Name: produto_historico produto_historico_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'produto_historico_pkey' AND connamespace = 'public'::regnamespace) THEN
        ALTER TABLE ONLY public.produto_historico ADD CONSTRAINT produto_historico_pkey PRIMARY KEY (id);
    END IF;
END $$;

--
-- Name: produtos produtos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'produtos_pkey' AND connamespace = 'public'::regnamespace) THEN
        ALTER TABLE ONLY public.produtos ADD CONSTRAINT produtos_pkey PRIMARY KEY (id);
    END IF;
END $$;

--
-- Name: romaneios romaneios_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'romaneios_pkey' AND connamespace = 'public'::regnamespace) THEN
        ALTER TABLE ONLY public.romaneios ADD CONSTRAINT romaneios_pkey PRIMARY KEY (id);
    END IF;
END $$;

--
-- Name: sangrias_caixa sangrias_caixa_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'sangrias_caixa_pkey' AND connamespace = 'public'::regnamespace) THEN
        ALTER TABLE ONLY public.sangrias_caixa ADD CONSTRAINT sangrias_caixa_pkey PRIMARY KEY (id);
    END IF;
END $$;

--
-- Name: servicos servicos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'servicos_pkey' AND connamespace = 'public'::regnamespace) THEN
        ALTER TABLE ONLY public.servicos ADD CONSTRAINT servicos_pkey PRIMARY KEY (id);
    END IF;
END $$;

--
-- Name: suprimentos_caixa suprimentos_caixa_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'suprimentos_caixa_pkey' AND connamespace = 'public'::regnamespace) THEN
        ALTER TABLE ONLY public.suprimentos_caixa ADD CONSTRAINT suprimentos_caixa_pkey PRIMARY KEY (id);
    END IF;
END $$;

--
-- Name: sync_logs sync_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'sync_logs_pkey' AND connamespace = 'public'::regnamespace) THEN
        ALTER TABLE ONLY public.sync_logs ADD CONSTRAINT sync_logs_pkey PRIMARY KEY (id);
    END IF;
END $$;

--
-- Name: sync_status sync_status_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'sync_status_pkey' AND connamespace = 'public'::regnamespace) THEN
        ALTER TABLE ONLY public.sync_status ADD CONSTRAINT sync_status_pkey PRIMARY KEY (empresa_id);
    END IF;
END $$;

--
-- Name: taxas_entrega taxas_entrega_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'taxas_entrega_pkey' AND connamespace = 'public'::regnamespace) THEN
        ALTER TABLE ONLY public.taxas_entrega ADD CONSTRAINT taxas_entrega_pkey PRIMARY KEY (id);
    END IF;
END $$;

--
-- Name: trocas_devolucoes trocas_devolucoes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'trocas_devolucoes_pkey' AND connamespace = 'public'::regnamespace) THEN
        ALTER TABLE ONLY public.trocas_devolucoes ADD CONSTRAINT trocas_devolucoes_pkey PRIMARY KEY (id);
    END IF;
END $$;

--
-- Name: usuarios usuarios_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'usuarios_pkey' AND connamespace = 'public'::regnamespace) THEN
        ALTER TABLE ONLY public.usuarios ADD CONSTRAINT usuarios_pkey PRIMARY KEY (id);
    END IF;
END $$;

--
-- Name: vendas_balcao vendas_balcao_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'vendas_balcao_pkey' AND connamespace = 'public'::regnamespace) THEN
        ALTER TABLE ONLY public.vendas_balcao ADD CONSTRAINT vendas_balcao_pkey PRIMARY KEY (id);
    END IF;
END $$;

--
-- Name: vw_historico_recente vw_historico_recente_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'vw_historico_recente_pkey' AND connamespace = 'public'::regnamespace) THEN
        ALTER TABLE ONLY public.vw_historico_recente ADD CONSTRAINT vw_historico_recente_pkey PRIMARY KEY (id);
    END IF;
END $$;

--
-- Name: idx_clientes_empresa_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_clientes_empresa_id ON public.clientes USING btree (empresa_id);

--
-- Name: idx_clientes_nome; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_clientes_nome ON public.clientes USING btree (nome);

--
-- Name: idx_estoque_historico_empresa_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_estoque_historico_empresa_id ON public.estoque_historico USING btree (empresa_id);

--
-- Name: idx_pedidos_empresa_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_pedidos_empresa_id ON public.pedidos USING btree (empresa_id);

--
-- Name: idx_produtos_codigo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_produtos_codigo ON public.produtos USING btree (codigo);

--
-- Name: idx_produtos_empresa_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_produtos_empresa_id ON public.produtos USING btree (empresa_id);

--
-- Name: idx_produtos_nome; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_produtos_nome ON public.produtos USING btree (nome);

--
-- Name: idx_sync_logs_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_sync_logs_created_at ON public.sync_logs USING btree (created_at DESC);

--
-- Name: idx_sync_logs_empresa_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_sync_logs_empresa_id ON public.sync_logs USING btree (empresa_id);

--
-- Name: idx_sync_status_online; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_sync_status_online ON public.sync_status USING btree (online);

--
-- Name: idx_sync_status_updated; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_sync_status_updated ON public.sync_status USING btree (updated_at DESC);

--
-- Name: idx_vendas_balcao_empresa_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_vendas_balcao_empresa_id ON public.vendas_balcao USING btree (empresa_id);

--
-- Name: aberturas_caixa trg_exodo_sync_log_aberturas_caixa; Type: TRIGGER; Schema: public; Owner: -
--

DROP TRIGGER IF EXISTS trg_exodo_sync_log_aberturas_caixa ON public.aberturas_caixa;
CREATE TRIGGER trg_exodo_sync_log_aberturas_caixa AFTER INSERT OR DELETE OR UPDATE ON public.aberturas_caixa FOR EACH ROW EXECUTE FUNCTION public.log_sync_event();

--
-- Name: agendamentos_servico trg_exodo_sync_log_agendamentos_servico; Type: TRIGGER; Schema: public; Owner: -
--

DROP TRIGGER IF EXISTS trg_exodo_sync_log_agendamentos_servico ON public.agendamentos_servico;
CREATE TRIGGER trg_exodo_sync_log_agendamentos_servico AFTER INSERT OR DELETE OR UPDATE ON public.agendamentos_servico FOR EACH ROW EXECUTE FUNCTION public.log_sync_event();

--
-- Name: clientes trg_exodo_sync_log_clientes; Type: TRIGGER; Schema: public; Owner: -
--

DROP TRIGGER IF EXISTS trg_exodo_sync_log_clientes ON public.clientes;
CREATE TRIGGER trg_exodo_sync_log_clientes AFTER INSERT OR DELETE OR UPDATE ON public.clientes FOR EACH ROW EXECUTE FUNCTION public.log_sync_event();

--
-- Name: comissoes_vendedores trg_exodo_sync_log_comissoes_vendedores; Type: TRIGGER; Schema: public; Owner: -
--

DROP TRIGGER IF EXISTS trg_exodo_sync_log_comissoes_vendedores ON public.comissoes_vendedores;
CREATE TRIGGER trg_exodo_sync_log_comissoes_vendedores AFTER INSERT OR DELETE OR UPDATE ON public.comissoes_vendedores FOR EACH ROW EXECUTE FUNCTION public.log_sync_event();

--
-- Name: contas_pagar trg_exodo_sync_log_contas_pagar; Type: TRIGGER; Schema: public; Owner: -
--

DROP TRIGGER IF EXISTS trg_exodo_sync_log_contas_pagar ON public.contas_pagar;
CREATE TRIGGER trg_exodo_sync_log_contas_pagar AFTER INSERT OR DELETE OR UPDATE ON public.contas_pagar FOR EACH ROW EXECUTE FUNCTION public.log_sync_event();

--
-- Name: empresas trg_exodo_sync_log_empresas; Type: TRIGGER; Schema: public; Owner: -
--

DROP TRIGGER IF EXISTS trg_exodo_sync_log_empresas ON public.empresas;
CREATE TRIGGER trg_exodo_sync_log_empresas AFTER INSERT OR DELETE OR UPDATE ON public.empresas FOR EACH ROW EXECUTE FUNCTION public.log_sync_event();

--
-- Name: entregas trg_exodo_sync_log_entregas; Type: TRIGGER; Schema: public; Owner: -
--

DROP TRIGGER IF EXISTS trg_exodo_sync_log_entregas ON public.entregas;
CREATE TRIGGER trg_exodo_sync_log_entregas AFTER INSERT OR DELETE OR UPDATE ON public.entregas FOR EACH ROW EXECUTE FUNCTION public.log_sync_event();

--
-- Name: estoque_historico trg_exodo_sync_log_estoque_historico; Type: TRIGGER; Schema: public; Owner: -
--

DROP TRIGGER IF EXISTS trg_exodo_sync_log_estoque_historico ON public.estoque_historico;
CREATE TRIGGER trg_exodo_sync_log_estoque_historico AFTER INSERT OR DELETE OR UPDATE ON public.estoque_historico FOR EACH ROW EXECUTE FUNCTION public.log_sync_event();

-- NOTA: exodo_config e sync_status NAO recebem trigger log_sync_event (tabelas sem coluna id;
--        o trigger usaria NEW.id::text e quebraria todas as escritas).

--
-- Name: fechamentos_caixa trg_exodo_sync_log_fechamentos_caixa; Type: TRIGGER; Schema: public; Owner: -
--

DROP TRIGGER IF EXISTS trg_exodo_sync_log_fechamentos_caixa ON public.fechamentos_caixa;
CREATE TRIGGER trg_exodo_sync_log_fechamentos_caixa AFTER INSERT OR DELETE OR UPDATE ON public.fechamentos_caixa FOR EACH ROW EXECUTE FUNCTION public.log_sync_event();

--
-- Name: funcionarios trg_exodo_sync_log_funcionarios; Type: TRIGGER; Schema: public; Owner: -
--

DROP TRIGGER IF EXISTS trg_exodo_sync_log_funcionarios ON public.funcionarios;
CREATE TRIGGER trg_exodo_sync_log_funcionarios AFTER INSERT OR DELETE OR UPDATE ON public.funcionarios FOR EACH ROW EXECUTE FUNCTION public.log_sync_event();

--
-- Name: imagens trg_exodo_sync_log_imagens; Type: TRIGGER; Schema: public; Owner: -
--

DROP TRIGGER IF EXISTS trg_exodo_sync_log_imagens ON public.imagens;
CREATE TRIGGER trg_exodo_sync_log_imagens AFTER INSERT OR DELETE OR UPDATE ON public.imagens FOR EACH ROW EXECUTE FUNCTION public.log_sync_event();

--
-- Name: links_vendedores trg_exodo_sync_log_links_vendedores; Type: TRIGGER; Schema: public; Owner: -
--

DROP TRIGGER IF EXISTS trg_exodo_sync_log_links_vendedores ON public.links_vendedores;
CREATE TRIGGER trg_exodo_sync_log_links_vendedores AFTER INSERT OR DELETE OR UPDATE ON public.links_vendedores FOR EACH ROW EXECUTE FUNCTION public.log_sync_event();

--
-- Name: mesas_comandas trg_exodo_sync_log_mesas_comandas; Type: TRIGGER; Schema: public; Owner: -
--

DROP TRIGGER IF EXISTS trg_exodo_sync_log_mesas_comandas ON public.mesas_comandas;
CREATE TRIGGER trg_exodo_sync_log_mesas_comandas AFTER INSERT OR DELETE OR UPDATE ON public.mesas_comandas FOR EACH ROW EXECUTE FUNCTION public.log_sync_event();

--
-- Name: motoristas trg_exodo_sync_log_motoristas; Type: TRIGGER; Schema: public; Owner: -
--

DROP TRIGGER IF EXISTS trg_exodo_sync_log_motoristas ON public.motoristas;
CREATE TRIGGER trg_exodo_sync_log_motoristas AFTER INSERT OR DELETE OR UPDATE ON public.motoristas FOR EACH ROW EXECUTE FUNCTION public.log_sync_event();

--
-- Name: nfces trg_exodo_sync_log_nfces; Type: TRIGGER; Schema: public; Owner: -
--

DROP TRIGGER IF EXISTS trg_exodo_sync_log_nfces ON public.nfces;
CREATE TRIGGER trg_exodo_sync_log_nfces AFTER INSERT OR DELETE OR UPDATE ON public.nfces FOR EACH ROW EXECUTE FUNCTION public.log_sync_event();

DROP TRIGGER IF EXISTS trg_exodo_sync_log_nfes ON public.nfes;
CREATE TRIGGER trg_exodo_sync_log_nfes AFTER INSERT OR DELETE OR UPDATE ON public.nfes FOR EACH ROW EXECUTE FUNCTION public.log_sync_event();

--
-- Name: notas_entrada trg_exodo_sync_log_notas_entrada; Type: TRIGGER; Schema: public; Owner: -
--

DROP TRIGGER IF EXISTS trg_exodo_sync_log_notas_entrada ON public.notas_entrada;
CREATE TRIGGER trg_exodo_sync_log_notas_entrada AFTER INSERT OR DELETE OR UPDATE ON public.notas_entrada FOR EACH ROW EXECUTE FUNCTION public.log_sync_event();

--
-- Name: ordens_servico trg_exodo_sync_log_ordens_servico; Type: TRIGGER; Schema: public; Owner: -
--

DROP TRIGGER IF EXISTS trg_exodo_sync_log_ordens_servico ON public.ordens_servico;
CREATE TRIGGER trg_exodo_sync_log_ordens_servico AFTER INSERT OR DELETE OR UPDATE ON public.ordens_servico FOR EACH ROW EXECUTE FUNCTION public.log_sync_event();

--
-- Name: pedidos trg_exodo_sync_log_pedidos; Type: TRIGGER; Schema: public; Owner: -
--

DROP TRIGGER IF EXISTS trg_exodo_sync_log_pedidos ON public.pedidos;
CREATE TRIGGER trg_exodo_sync_log_pedidos AFTER INSERT OR DELETE OR UPDATE ON public.pedidos FOR EACH ROW EXECUTE FUNCTION public.log_sync_event();

--
-- Name: produto_historico trg_exodo_sync_log_produto_historico; Type: TRIGGER; Schema: public; Owner: -
--

DROP TRIGGER IF EXISTS trg_exodo_sync_log_produto_historico ON public.produto_historico;
CREATE TRIGGER trg_exodo_sync_log_produto_historico AFTER INSERT OR DELETE OR UPDATE ON public.produto_historico FOR EACH ROW EXECUTE FUNCTION public.log_sync_event();

--
-- Name: produtos trg_exodo_sync_log_produtos; Type: TRIGGER; Schema: public; Owner: -
--

DROP TRIGGER IF EXISTS trg_exodo_sync_log_produtos ON public.produtos;
CREATE TRIGGER trg_exodo_sync_log_produtos AFTER INSERT OR DELETE OR UPDATE ON public.produtos FOR EACH ROW EXECUTE FUNCTION public.log_sync_event();

--
-- Name: romaneios trg_exodo_sync_log_romaneios; Type: TRIGGER; Schema: public; Owner: -
--

DROP TRIGGER IF EXISTS trg_exodo_sync_log_romaneios ON public.romaneios;
CREATE TRIGGER trg_exodo_sync_log_romaneios AFTER INSERT OR DELETE OR UPDATE ON public.romaneios FOR EACH ROW EXECUTE FUNCTION public.log_sync_event();

--
-- Name: sangrias_caixa trg_exodo_sync_log_sangrias_caixa; Type: TRIGGER; Schema: public; Owner: -
--

DROP TRIGGER IF EXISTS trg_exodo_sync_log_sangrias_caixa ON public.sangrias_caixa;
CREATE TRIGGER trg_exodo_sync_log_sangrias_caixa AFTER INSERT OR DELETE OR UPDATE ON public.sangrias_caixa FOR EACH ROW EXECUTE FUNCTION public.log_sync_event();

--
-- Name: servicos trg_exodo_sync_log_servicos; Type: TRIGGER; Schema: public; Owner: -
--

DROP TRIGGER IF EXISTS trg_exodo_sync_log_servicos ON public.servicos;
CREATE TRIGGER trg_exodo_sync_log_servicos AFTER INSERT OR DELETE OR UPDATE ON public.servicos FOR EACH ROW EXECUTE FUNCTION public.log_sync_event();

--
-- Name: suprimentos_caixa trg_exodo_sync_log_suprimentos_caixa; Type: TRIGGER; Schema: public; Owner: -
--

DROP TRIGGER IF EXISTS trg_exodo_sync_log_suprimentos_caixa ON public.suprimentos_caixa;
CREATE TRIGGER trg_exodo_sync_log_suprimentos_caixa AFTER INSERT OR DELETE OR UPDATE ON public.suprimentos_caixa FOR EACH ROW EXECUTE FUNCTION public.log_sync_event();

--
-- Name: sync_logs trg_exodo_sync_log_sync_logs; Type: TRIGGER; Schema: public; Owner: -
--

-- NOTA: sync_logs NAO recebe trigger log_sync_event (tabela de logs internos)
DROP TRIGGER IF EXISTS trg_exodo_sync_log_sync_logs ON public.sync_logs;


--
-- Name: taxas_entrega trg_exodo_sync_log_taxas_entrega; Type: TRIGGER; Schema: public; Owner: -
--

DROP TRIGGER IF EXISTS trg_exodo_sync_log_taxas_entrega ON public.taxas_entrega;
CREATE TRIGGER trg_exodo_sync_log_taxas_entrega AFTER INSERT OR DELETE OR UPDATE ON public.taxas_entrega FOR EACH ROW EXECUTE FUNCTION public.log_sync_event();

--
-- Name: trocas_devolucoes trg_exodo_sync_log_trocas_devolucoes; Type: TRIGGER; Schema: public; Owner: -
--

DROP TRIGGER IF EXISTS trg_exodo_sync_log_trocas_devolucoes ON public.trocas_devolucoes;
CREATE TRIGGER trg_exodo_sync_log_trocas_devolucoes AFTER INSERT OR DELETE OR UPDATE ON public.trocas_devolucoes FOR EACH ROW EXECUTE FUNCTION public.log_sync_event();

--
-- Name: usuarios trg_exodo_sync_log_usuarios; Type: TRIGGER; Schema: public; Owner: -
--

DROP TRIGGER IF EXISTS trg_exodo_sync_log_usuarios ON public.usuarios;
CREATE TRIGGER trg_exodo_sync_log_usuarios AFTER INSERT OR DELETE OR UPDATE ON public.usuarios FOR EACH ROW EXECUTE FUNCTION public.log_sync_event();

--
-- Name: vendas_balcao trg_exodo_sync_log_vendas_balcao; Type: TRIGGER; Schema: public; Owner: -
--

DROP TRIGGER IF EXISTS trg_exodo_sync_log_vendas_balcao ON public.vendas_balcao;
CREATE TRIGGER trg_exodo_sync_log_vendas_balcao AFTER INSERT OR DELETE OR UPDATE ON public.vendas_balcao FOR EACH ROW EXECUTE FUNCTION public.log_sync_event();

--
-- PostgreSQL database dump complete
--

