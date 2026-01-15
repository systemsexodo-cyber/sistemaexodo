<?php

namespace SistemaExodo\BackendNfce;

class Router
{
    private App $app;

    public function __construct(App $app)
    {
        $this->app = $app;
    }

    public function defineRoutes(): void
    {
        // Rotas são tratadas dinamicamente no handleRequest
    }

    public function handleRequest(): void
    {
        $method = $_SERVER['REQUEST_METHOD'];
        $uri = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
        $uri = rtrim($uri, '/');

        try {
            // Health check
            if ($uri === '/health' && $method === 'GET') {
                $this->handleHealth();
                return;
            }

            // Emitir NFC-e
            if ($uri === '/api/nfce/emitir' && $method === 'POST') {
                $this->handleEmitirNFCe();
                return;
            }

            // Rota não encontrada
            $this->sendResponse(404, [
                'success' => false,
                'error' => 'Rota não encontrada',
                'path' => $uri
            ]);
        } catch (\Exception $e) {
            $this->app->getLogger()->error('Erro no router: ' . $e->getMessage(), [
                'trace' => $e->getTraceAsString()
            ]);

            $this->sendResponse(500, [
                'success' => false,
                'error' => 'Erro interno do servidor',
                'message' => $e->getMessage()
            ]);
        }
    }

    private function handleHealth(): void
    {
        $this->sendResponse(200, [
            'status' => 'ok',
            'message' => 'Backend PHP NFC-e está funcionando',
            'backend' => 'php',
            'library' => 'sped-nfe',
            'version' => '5.0'
        ]);
    }

    private function handleEmitirNFCe(): void
    {
        // Ler dados do POST
        $input = file_get_contents('php://input');
        $data = json_decode($input, true);

        if (json_last_error() !== JSON_ERROR_NONE) {
            $this->sendResponse(400, [
                'success' => false,
                'error' => 'JSON inválido',
                'message' => json_last_error_msg()
            ]);
            return;
        }

        // Validar dados obrigatórios
        if (!isset($data['empresa']) || !isset($data['produtos']) || !isset($data['pagamentos'])) {
            $this->sendResponse(400, [
                'success' => false,
                'error' => 'Dados incompletos',
                'message' => 'São obrigatórios: empresa, produtos, pagamentos'
            ]);
            return;
        }

        try {
            // Chamar serviço de emissão
            $result = $this->app->getNFCeService()->emitir($data);

            $this->sendResponse(200, $result);
        } catch (\Exception $e) {
            $this->app->getLogger()->error('Erro ao emitir NFC-e: ' . $e->getMessage(), [
                'trace' => $e->getTraceAsString(),
                'data' => $data
            ]);

            $this->sendResponse(500, [
                'success' => false,
                'error' => 'Erro ao emitir NFC-e',
                'message' => $e->getMessage(),
                'error_type' => get_class($e)
            ]);
        }
    }

    private function sendResponse(int $statusCode, array $data): void
    {
        http_response_code($statusCode);
        echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);
        exit;
    }
}











