<?php
/**
 * Script de teste para emissão de NFC-e
 * 
 * Execute: php testar_emissao.php
 */

require_once __DIR__ . '/vendor/autoload.php';

use SistemaExodo\BackendNfce\App;
use SistemaExodo\BackendNfce\Router;

// Dados de teste
$dadosTeste = [
    'empresa' => [
        'id' => '1',
        'cnpj' => '12345678000190',
        'razao_social' => 'Empresa Teste LTDA',
        'nome_fantasia' => 'Empresa Teste',
        'inscricao_estadual' => '123456789',
        'uf' => 'SP',
        'codigo_municipio_ibge' => '3550308',
        'serie_nfce' => '1',
        'ambienteHomologacao' => true,
        'certificado_base64' => 'BASE64_DO_CERTIFICADO_AQUI',
        'senhaCertificado' => 'senha_do_certificado',
        'endereco' => [
            'logradouro' => 'Rua Teste',
            'numero' => '123',
            'bairro' => 'Centro',
            'cidade' => 'São Paulo',
            'cep' => '01234567'
        ]
    ],
    'produtos' => [
        [
            'id' => '1',
            'codigo' => '001',
            'nome' => 'Produto Teste',
            'ncm' => '12345678',
            'cfop' => '5102',
            'unidade' => 'UN',
            'quantidade' => 1,
            'preco' => 10.00
        ]
    ],
    'pagamentos' => [
        [
            'tipo' => 'dinheiro',
            'valor' => 10.00
        ]
    ],
    'consumidor' => [
        'cpf' => '12345678900',
        'nome' => 'Consumidor Teste'
    ],
    'observacoes' => 'Nota de teste',
    'numero_nfce' => 1
];

echo "========================================\n";
echo "Teste de Emissão NFC-e - Backend PHP\n";
echo "========================================\n\n";

// Verificar se o certificado foi preenchido
if ($dadosTeste['empresa']['certificado_base64'] === 'BASE64_DO_CERTIFICADO_AQUI') {
    echo "⚠️  ATENÇÃO: Preencha o certificado_base64 com um certificado válido!\n";
    echo "   Edite este arquivo e substitua 'BASE64_DO_CERTIFICADO_AQUI'\n\n";
    exit(1);
}

try {
    // Inicializar aplicação
    $app = new App();
    $nfceService = $app->getNFCeService();
    
    echo "✅ Serviço inicializado\n";
    echo "📤 Enviando requisição de emissão...\n\n";
    
    // Emitir NFC-e
    $resultado = $nfceService->emitir($dadosTeste);
    
    // Exibir resultado
    echo "========================================\n";
    echo "RESULTADO DA EMISSÃO\n";
    echo "========================================\n";
    
    if ($resultado['success'] && $resultado['autorizada']) {
        echo "✅ NFC-e AUTORIZADA!\n\n";
        echo "Chave: " . $resultado['chave'] . "\n";
        echo "Protocolo: " . $resultado['protocolo'] . "\n";
        echo "Número: " . $resultado['numero'] . "\n";
        echo "QR Code: " . $resultado['qr_code'] . "\n";
        echo "\n✅ Emissão concluída com sucesso!\n";
    } else {
        echo "❌ NFC-e REJEITADA\n\n";
        echo "Erro: " . ($resultado['error'] ?? 'Desconhecido') . "\n";
        if (isset($resultado['codigo_erro'])) {
            echo "Código: " . $resultado['codigo_erro'] . "\n";
        }
    }
    
} catch (\Exception $e) {
    echo "❌ ERRO: " . $e->getMessage() . "\n";
    echo "Trace: " . $e->getTraceAsString() . "\n";
    exit(1);
}

echo "\n========================================\n";











