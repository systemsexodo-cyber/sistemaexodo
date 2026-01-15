<?php
/**
 * Backend PHP para emissão de NFC-e usando SPED-NFe
 * API REST para comunicação com Flutter
 */

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

// Tratar requisições OPTIONS (CORS preflight)
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

// Carregar autoload do Composer
require_once __DIR__ . '/vendor/autoload.php';

// Carregar variáveis de ambiente
if (file_exists(__DIR__ . '/.env')) {
    $dotenv = Dotenv\Dotenv::createImmutable(__DIR__);
    $dotenv->load();
}

use SistemaExodo\BackendNfce\App;
use SistemaExodo\BackendNfce\Router;

// Inicializar aplicação
$app = new App();
$router = new Router($app);

// Definir rotas
$router->defineRoutes();

// Processar requisição
$router->handleRequest();











