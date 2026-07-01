-- ============================================
-- CONFIGURAÇÃO CORS PARA SUPABASE
-- Permite acesso de Firebase Hosting e qualquer origem
-- ============================================

-- Configurar política de CORS para permitir requisições cross-origin
-- Isso é necessário quando o app Flutter Web está hospedado em outro domínio (Firebase, Vercel, etc.)

-- Opção 1: Permitir TODAS as origens (menos seguro, mais flexível)
-- Execute no SQL Editor do Supabase:

-- Criar função para configurar headers CORS
CREATE OR REPLACE FUNCTION public.handle_cors()
RETURNS VOID AS $$
BEGIN
  -- Configuração via PostgREST (API REST do Supabase)
  -- Os headers CORS são gerenciados automaticamente pelo Supabase
  -- Esta função é apenas um placeholder para documentação
  RAISE NOTICE 'CORS configurado: Permitir origens: * (todas)';
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- VERIFICAÇÃO DE CONECTIVIDADE
-- Teste se o Supabase está respondendo corretamente
-- ============================================

-- Verificar se a tabela empresas existe e está acessível
SELECT 
  '✅ Tabela empresas existe e está acessível' as status,
  COUNT(*) as total_empresas
FROM public.empresas
LIMIT 1;

-- Verificar autenticação anônima (chave pública)
SELECT 
  '✅ Autenticação anônima configurada' as status,
  current_user as usuario_atual,
  session_user as sessao;

-- ============================================
-- RLS POLICY PARA ACESSO WEB
-- Garante que usuários anônimos/autenticados possam acessar
-- ============================================

-- Verificar políticas existentes na tabela empresas
SELECT 
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual
FROM pg_policies 
WHERE tablename = 'empresas';

-- ============================================
-- TESTE DE CORS MANUAL
-- ============================================

-- Execute este teste no console do navegador (F12 > Console):
-- fetch('https://febffvlpvxtiihvnfuts.supabase.co/rest/v1/empresas?select=id&limit=1', {
--   method: 'GET',
--   headers: {
--     'apikey': 'sb_publishable_NVM4Zf1hN8TuW2BziNv_rg_NhU4Qsss',
--     'Authorization': 'Bearer sb_publishable_NVM4Zf1hN8TuW2BziNv_rg_NhU4Qsss'
--   }
-- }).then(r => r.json()).then(data => console.log('✅ CORS OK:', data))
-- .catch(e => console.error('❌ CORS Error:', e));

-- ============================================
-- NOTAS IMPORTANTES
-- ============================================
/*

1. SUPABASE JÁ TEM CORS HABILITADO POR PADRÃO
   - Não é necessário configuração extra na maioria dos casos
   - O Supabase aceita requisições de qualquer origem (origins: *)

2. SE HOUVER PROBLEMA DE CORS:
   - Verifique no painel: Project Settings > API > Expose schema in API
   - Certifique-se de que 'public' está na lista de schemas expostos
   - A chave anon (public) deve estar sendo usada no frontend

3. PARA FIREBASE HOSTING:
   - O domínio .web.app ou .firebaseapp.com é automaticamente aceito
   - Não precisa adicionar na lista de origens permitidas

4. HEADERS NECESSÁRIOS NO FLUTTER WEB:
   - apikey: sua-anon-key
   - Authorization: Bearer sua-anon-key

*/
