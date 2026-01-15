<?php

namespace SistemaExodo\BackendNfce;

use SistemaExodo\BackendNfce\Services\NFCeService;
use Monolog\Logger;
use Monolog\Handler\StreamHandler;

class App
{
    private NFCeService $nfceService;
    private Logger $logger;

    public function __construct()
    {
        // Configurar logger
        $this->logger = new Logger('backend_nfce');
        $logFile = __DIR__ . '/../logs/app.log';
        $logDir = dirname($logFile);
        if (!is_dir($logDir)) {
            mkdir($logDir, 0755, true);
        }
        $this->logger->pushHandler(new StreamHandler($logFile, Logger::DEBUG));

        // Inicializar serviço de NFC-e
        $this->nfceService = new NFCeService($this->logger);
    }

    public function getNFCeService(): NFCeService
    {
        return $this->nfceService;
    }

    public function getLogger(): Logger
    {
        return $this->logger;
    }
}











