<?php
/**
 * Exemplo de uso do Backend PHP NFC-e
 * 
 * Este arquivo demonstra como usar a API REST para emitir NFC-e
 */

require_once __DIR__ . '/vendor/autoload.php';

$baseUrl = 'http://localhost:8000';

// Dados de exemplo para emissão de NFC-e
$dados = [
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

// Fazer requisição
$ch = curl_init($baseUrl . '/api/nfce/emitir');
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_POST, true);
curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($dados));
curl_setopt($ch, CURLOPT_HTTPHEADER, [
    'Content-Type: application/json'
]);

$response = curl_exec($ch);
$httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
curl_close($ch);

// Processar resposta
$resultado = json_decode($response, true);

if ($resultado['success'] && $resultado['autorizada']) {
    echo "✅ NFC-e autorizada!\n";
    echo "Chave: " . $resultado['chave'] . "\n";
    echo "Protocolo: " . $resultado['protocolo'] . "\n";
    echo "QR Code: " . $resultado['qr_code'] . "\n";
} else {
    echo "❌ Erro na emissão:\n";
    echo "Erro: " . ($resultado['error'] ?? 'Desconhecido') . "\n";
    if (isset($resultado['codigo_erro'])) {
        echo "Código: " . $resultado['codigo_erro'] . "\n";
    }
}

print_r($resultado);











