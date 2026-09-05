const { readFileSync } = require('fs');
const { Client } = require('pg');
const path = require('path');

const SQL_FILE = path.join(__dirname, 'supabase', 'migracao_completa_supabase.sql');

async function runMigration() {
  console.log('📖 Lendo arquivo SQL...');
  const sql = readFileSync(SQL_FILE, 'utf8');
  console.log(`📄 SQL lido: ${sql.length} caracteres`);

  // Tentar diferentes configs de conexao
  const configs = [
    { ssl: { rejectUnauthorized: false }, connectionTimeoutMillis: 30000 },
    { ssl: false, connectionTimeoutMillis: 10000 },
  ];

  const baseConfig = {
    host: '2600:1f13:838:6e53:1d1c:16:c80e:ba67',
    port: 5432,
    database: 'postgres',
    user: 'postgres',
    password: 'hmrzbdKJB6Bc4Vcr',
  };

  for (let i = 0; i < configs.length; i++) {
    const config = { ...baseConfig, ...configs[i] };
    console.log(`\n🔌 Tentativa ${i + 1}: conectar com SSL=${!!config.ssl}...`);
    
    const client = new Client(config);
    
    try {
      await client.connect();
      console.log('✅ Conectado!\n');
      
      console.log('🚀 Executando migracao...');
      console.log('='.repeat(50));
      
      await client.query(sql);
      
      console.log('='.repeat(50));
      console.log('\n✅ Migracao concluida com sucesso!');
      
      // Verificar tabelas criadas
      console.log('\n📊 Verificando tabelas...');
      const result = await client.query(`
        SELECT table_name, 
          (SELECT COUNT(*) FROM information_schema.columns c 
           WHERE c.table_schema = 'public' AND c.table_name = t.table_name) as colunas
        FROM information_schema.tables t
        WHERE table_schema = 'public' AND table_type = 'BASE TABLE' AND table_name NOT LIKE 'pg_%'
        ORDER BY table_name
      `);
      
      console.log(`\n📋 Total de tabelas: ${result.rows.length}`);
      result.rows.forEach(row => {
        console.log(`   ${row.table_name} (${row.colunas} colunas)`);
      });
      
      await client.end();
      console.log('\n🔌 Conexao fechada.');
      return; // Sucesso, sair
      
    } catch (err) {
      console.error(`❌ Tentativa ${i + 1} falhou:`, err.message || '(erro vazio)');
      if (err.code) console.error('   Codigo:', err.code);
      if (err.errno) console.error('   Errno:', err.errno);
      if (err.syscall) console.error('   Syscall:', err.syscall);
      if (err.stack) {
        const lines = err.stack.split('\n');
        console.error('   Stack:', lines.slice(0, 3).join('\n          '));
      }
      try { await client.end(); } catch(_) {}
    }
  }
  
  console.log('\n❌ Todas as tentativas de conexao falharam.');
  console.log('\n💡 Dica: A senha pode estar incorreta ou o banco pode estar com acesso restrito.');
  console.log('   Tente acessar o Supabase Dashboard > Project Settings > Database');
  console.log('   e verifique a Connection string la.');
}

runMigration();
