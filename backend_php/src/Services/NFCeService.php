<?php

namespace SistemaExodo\BackendNfce\Services;

use NFePHP\NFe\Make;
use NFePHP\NFe\Tools;
use NFePHP\Common\Certificate;
use NFePHP\NFe\Common\Standardize;
use Monolog\Logger;

class NFCeService
{
    private Logger $logger;
    private string $certPath;
    private string $storagePath;

    public function __construct(Logger $logger)
    {
        $this->logger = $logger;
        $this->certPath = __DIR__ . '/../../storage/certs';
        $this->storagePath = __DIR__ . '/../../storage/xml';

        // Criar diretórios se não existirem
        foreach ([$this->certPath, $this->storagePath] as $dir) {
            if (!is_dir($dir)) {
                mkdir($dir, 0755, true);
            }
        }
    }

    /**
     * Emite uma NFC-e
     * 
     * @param array $data Dados da NFC-e
     * @return array Resultado da emissão
     */
    public function emitir(array $data): array
    {
        try {
            $this->logger->info('Iniciando emissão de NFC-e');

            $empresa = $data['empresa'];
            $produtos = $data['produtos'];
            $pagamentos = $data['pagamentos'];
            $consumidor = $data['consumidor'] ?? null;
            $observacoes = $data['observacoes'] ?? '';
            $numeroNFCe = $data['numero_nfce'] ?? 1;

            // Validar dados
            $this->validarDados($empresa, $produtos, $pagamentos);

            // Preparar certificado
            $certificate = $this->prepararCertificado($empresa);

            // Configurar ambiente
            $ambiente = ($empresa['ambienteHomologacao'] ?? true) ? 2 : 1; // 2 = Homologação, 1 = Produção
            $uf = strtoupper($empresa['uf'] ?? 'SP');
            $serie = $empresa['serie_nfce'] ?? $empresa['serieNFCe'] ?? '1';
            $cMunFG = $empresa['codigo_municipio_ibge'] ?? $empresa['codigoIBGE'] ?? '3550308';

            // Criar objeto Make para NFC-e
            $make = new Make();
            
            // Configurar informações básicas da NFC-e
            // A API do SPED-NFe usa métodos específicos para cada tag
            $make->taginfNFe(
                '4.00', // versao
                'NFe' . str_pad($numeroNFCe, 9, '0', STR_PAD_LEFT), // Id
                '65', // mod (Modelo 65 = NFC-e)
                $serie, // serie
                $numeroNFCe, // nNF
                date('c'), // dhEmi (ISO 8601)
                date('c'), // dhSaiEnt
                '1', // tpNF (1 = Saída)
                '1', // idDest (1 = Operação interna)
                $cMunFG, // cMunFG (Código IBGE do município)
                '4', // tpImp (4 = NFC-e)
                '1', // tpEmis (1 = Normal)
                (string)$ambiente, // tpAmb (1 = Produção, 2 = Homologação)
                '1', // finNFe (1 = Normal)
                '1', // indFinal (1 = Sim, operação com consumidor final)
                '1', // indPres (1 = Operação presencial)
                '0', // procEmi (0 = Emissão com aplicativo do contribuinte)
                'Sistema Exodo 1.0' // verProc
            );

            // Adicionar emitente
            $this->adicionarEmitente($make, $empresa);

            // Adicionar destinatário (consumidor ou não identificado)
            $this->adicionarDestinatario($make, $consumidor);

            // Adicionar produtos
            $valorTotal = $this->adicionarProdutos($make, $produtos);

            // Adicionar totalizadores
            $this->adicionarTotalizadores($make, $valorTotal);

            // Adicionar pagamentos
            $this->adicionarPagamentos($make, $pagamentos, $valorTotal);

            // Adicionar observações
            if (!empty($observacoes)) {
                $make->taginfAdic($observacoes, '');
            }

            // Montar XML
            $xml = $make->getXML();
            $this->logger->debug('XML gerado com sucesso');

            // Assinar XML
            $tools = new Tools($xml, $certificate);
            $tools->model('65'); // Modelo 65 = NFC-e
            $xmlAssinado = $tools->signNFe($certificate);

            // Enviar para SEFAZ
            $this->logger->info('Enviando NFC-e para SEFAZ');
            $response = $tools->sefazEnviaLote([$xmlAssinado], $tools::NFCe);

            // Processar retorno
            $std = new Standardize($response);
            $stdArr = $std->toArray();

            $this->logger->info('Resposta da SEFAZ recebida', ['response' => $stdArr]);

            // Verificar se foi autorizada
            if (isset($stdArr['protNFe']['infProt']['cStat']) && $stdArr['protNFe']['infProt']['cStat'] == '100') {
                // NFC-e autorizada
                $protocolo = $stdArr['protNFe']['infProt']['nProt'] ?? '';
                $chave = $stdArr['protNFe']['infProt']['chNFe'] ?? '';

                // Salvar XMLs
                $this->salvarXMLs($chave, $xmlAssinado, $response, $empresa['id'] ?? 'default');

                // Gerar QR Code
                $qrCode = $this->gerarQRCode($chave, $ambiente, $uf);

                return [
                    'success' => true,
                    'autorizada' => true,
                    'chave' => $chave,
                    'protocolo' => $protocolo,
                    'numero' => $numeroNFCe,
                    'qr_code' => $qrCode,
                    'xml' => $xmlAssinado,
                    'xml_retorno' => $response,
                    'status' => 'autorizada'
                ];
            } else {
                // NFC-e rejeitada
                $motivo = $stdArr['protNFe']['infProt']['xMotivo'] ?? 'Erro desconhecido';
                $codigoErro = $stdArr['protNFe']['infProt']['cStat'] ?? '000';

                return [
                    'success' => false,
                    'autorizada' => false,
                    'error' => $motivo,
                    'codigo_erro' => $codigoErro,
                    'status' => 'rejeitada',
                    'xml_retorno' => $response
                ];
            }
        } catch (\Exception $e) {
            $this->logger->error('Erro ao emitir NFC-e: ' . $e->getMessage(), [
                'trace' => $e->getTraceAsString()
            ]);

            return [
                'success' => false,
                'autorizada' => false,
                'error' => $e->getMessage(),
                'error_type' => get_class($e)
            ];
        }
    }

    private function validarDados(array $empresa, array $produtos, array $pagamentos): void
    {
        // Validar empresa
        if (empty($empresa['cnpj'])) {
            throw new \Exception('CNPJ da empresa é obrigatório');
        }
        if (empty($empresa['certificado_base64']) && empty($empresa['certificadoDigitalUrl'])) {
            throw new \Exception('Certificado digital é obrigatório');
        }

        // Validar produtos
        if (empty($produtos)) {
            throw new \Exception('É necessário pelo menos um produto');
        }

        // Validar pagamentos
        if (empty($pagamentos)) {
            throw new \Exception('É necessário pelo menos uma forma de pagamento');
        }
    }

    private function prepararCertificado(array $empresa): Certificate
    {
        try {
            $certificadoBase64 = $empresa['certificado_base64'] ?? $empresa['certificadoDigitalUrl'] ?? '';
            $senha = $empresa['senhaCertificado'] ?? $empresa['senha_certificado'] ?? '';

            if (empty($certificadoBase64)) {
                throw new \Exception('Certificado digital não fornecido');
            }

            // Converter base64 para binário
            $certificadoBinario = base64_decode($certificadoBase64);
            if ($certificadoBinario === false) {
                throw new \Exception('Erro ao decodificar certificado (base64 inválido)');
            }

            // Salvar temporariamente em arquivo PFX
            $certFile = $this->certPath . '/' . uniqid('cert_') . '.pfx';
            file_put_contents($certFile, $certificadoBinario);

            // Carregar certificado
            $certificate = Certificate::readPfx($certFile, $senha);

            // Remover arquivo temporário
            @unlink($certFile);

            $this->logger->info('Certificado preparado com sucesso');
            return $certificate;
        } catch (\Exception $e) {
            $this->logger->error('Erro ao preparar certificado: ' . $e->getMessage());
            throw new \Exception('Erro ao preparar certificado: ' . $e->getMessage());
        }
    }

    private function adicionarEmitente(Make $make, array $empresa): void
    {
        $cnpj = preg_replace('/[^0-9]/', '', $empresa['cnpj']);
        $razaoSocial = $empresa['razao_social'] ?? $empresa['razaoSocial'] ?? '';
        $nomeFantasia = $empresa['nome_fantasia'] ?? $empresa['nomeFantasia'] ?? $razaoSocial;
        $inscricaoEstadual = $empresa['inscricao_estadual'] ?? $empresa['inscricaoEstadual'] ?? '';
        $inscricaoMunicipal = $empresa['inscricao_municipal'] ?? $empresa['inscricaoMunicipal'] ?? '';
        $crt = $empresa['crt'] ?? '3'; // 3 = Regime Normal
        $uf = $this->getUFCodigo($empresa['uf'] ?? 'SP');

        $make->tagemit(
            $cnpj,
            $razaoSocial,
            $nomeFantasia,
            $inscricaoEstadual,
            $inscricaoMunicipal,
            $crt,
            $uf
        );

        // Endereço do emitente
        $logradouro = $empresa['endereco']['logradouro'] ?? $empresa['endereco'] ?? '';
        $numero = $empresa['endereco']['numero'] ?? $empresa['numero'] ?? '';
        $complemento = $empresa['endereco']['complemento'] ?? $empresa['complemento'] ?? '';
        $bairro = $empresa['endereco']['bairro'] ?? $empresa['bairro'] ?? '';
        $cMun = $empresa['codigo_municipio_ibge'] ?? $empresa['codigoIBGE'] ?? '3550308';
        $municipio = $empresa['endereco']['municipio'] ?? $empresa['cidade'] ?? '';
        $cep = preg_replace('/[^0-9]/', '', $empresa['endereco']['cep'] ?? $empresa['cep'] ?? '');
        $telefone = preg_replace('/[^0-9]/', '', $empresa['endereco']['telefone'] ?? $empresa['telefone'] ?? '');

        $make->tagenderEmit(
            $logradouro,
            $numero,
            $complemento,
            $bairro,
            $cMun,
            $municipio,
            $uf,
            $cep,
            '1058', // Código do Brasil
            $telefone
        );
    }

    private function adicionarDestinatario(Make $make, ?array $consumidor): void
    {
        if ($consumidor && !empty($consumidor['cpf']) && !empty($consumidor['nome'])) {
            $cpf = preg_replace('/[^0-9]/', '', $consumidor['cpf']);
            $nome = $consumidor['nome'];
            
            $make->tagdest(
                $cpf,
                $nome,
                '', // IE
                '', // ISUF
                '', // IM
                '', // email
                '', // logradouro
                '', // numero
                '', // complemento
                '', // bairro
                '', // cMun
                ''  // municipio
            );
        } else {
            // Consumidor não identificado
            $make->tagdest(
                '',
                'CONSUMIDOR NÃO IDENTIFICADO',
                '',
                '',
                '',
                '',
                '',
                '',
                '',
                '',
                '',
                ''
            );
        }
    }

    private function adicionarProdutos(Make $make, array $produtos): float
    {
        $valorTotal = 0;
        $nItem = 1;

        foreach ($produtos as $produto) {
            $codigo = $produto['codigo'] ?? $produto['id'] ?? strval($nItem);
            $descricao = $produto['nome'] ?? $produto['descricao'] ?? 'Produto';
            $ncm = $produto['ncm'] ?? '00000000';
            $cfop = $produto['cfop'] ?? '5102';
            $un = $produto['unidade'] ?? 'UN';
            $quantidade = floatval($produto['quantidade'] ?? 1);
            $valorUnitario = floatval($produto['preco'] ?? $produto['preco_atual'] ?? 0);
            $valorProduto = $quantidade * $valorUnitario;
            $valorTotal += $valorProduto;

            // Adicionar produto
            $make->tagprod(
                $codigo,
                $descricao,
                $ncm,
                $cfop,
                $un,
                $quantidade,
                $valorUnitario,
                $valorProduto,
                '', // Código EAN
                '', // Código EAN tributário
                '0', // Ex tipi
                '', // Genero
                '', // CFOP
                ''  // Código de beneficiamento
            );

            // ICMS - Simples Nacional sem crédito (102)
            $make->tagICMS('102', '41');

            // IPI - Isento
            $make->tagIPI('99', '53');

            // PIS - Sem incidência
            $make->tagPIS('99', '08');

            // COFINS - Sem incidência
            $make->tagCOFINS('99', '08');

            // Informações adicionais do produto
            $make->taginfAdicProd('');

            $nItem++;
        }

        return $valorTotal;
    }

    private function adicionarTotalizadores(Make $make, float $valorTotal): void
    {
        // Totalizadores da NFC-e
        $make->tagICMSTot(
            number_format($valorTotal, 2, '.', ''), // vBC
            '0.00', // vICMS
            '0.00', // vICMSDeson
            '0.00', // vFCP
            '0.00', // vBCST
            '0.00', // vST
            '0.00', // vFCPST
            '0.00', // vFCPSTRet
            '0.00', // vProd
            '0.00', // vFrete
            '0.00', // vSeg
            '0.00', // vDesc
            '0.00', // vII
            '0.00', // vIPI
            '0.00', // vIPIDevol
            number_format($valorTotal, 2, '.', ''), // vPIS
            '0.00', // vCOFINS
            '0.00', // vOutro
            number_format($valorTotal, 2, '.', ''), // vNF
            '0.00', // vTotTrib
            '0.00', // vFCPUFDest
            '0.00'  // vICMSUFDest
        );
    }

    private function adicionarPagamentos(Make $make, array $pagamentos, float $valorTotal): void
    {
        $valorPagamentos = 0;

        foreach ($pagamentos as $pagamento) {
            $tipo = $this->getTipoPagamento($pagamento['tipo'] ?? 'dinheiro');
            $valor = floatval($pagamento['valor'] ?? 0);
            $valorPagamentos += $valor;

            $make->tagdetPag(
                $tipo,
                number_format($valor, 2, '.', ''),
                '' // Troco
            );
        }

        // Garantir que o total de pagamentos seja igual ao valor total
        if (abs($valorPagamentos - $valorTotal) > 0.01) {
            // Ajustar último pagamento
            $diferenca = $valorTotal - $valorPagamentos;
            $make->tagdetPag('01', number_format($diferenca, 2, '.', ''), '');
        }

        $make->tagvTroco('0.00'); // Sem troco
    }

    private function getTipoPagamento(string $tipo): string
    {
        $tipos = [
            'dinheiro' => '01',
            'cheque' => '02',
            'credito' => '03',
            'debito' => '04',
            'credito_loja' => '05',
            'vale_alimentacao' => '10',
            'vale_refeicao' => '11',
            'vale_presente' => '12',
            'vale_combustivel' => '13',
            'pix' => '99',
            'outro' => '99'
        ];

        return $tipos[strtolower($tipo)] ?? '01';
    }

    private function getUFCodigo(string $uf): string
    {
        $ufs = [
            'AC' => '12', 'AL' => '27', 'AP' => '16', 'AM' => '13',
            'BA' => '29', 'CE' => '23', 'DF' => '53', 'ES' => '32',
            'GO' => '52', 'MA' => '21', 'MT' => '51', 'MS' => '50',
            'MG' => '31', 'PA' => '15', 'PB' => '25', 'PR' => '41',
            'PE' => '26', 'PI' => '22', 'RJ' => '33', 'RN' => '24',
            'RS' => '43', 'RO' => '11', 'RR' => '14', 'SC' => '42',
            'SP' => '35', 'SE' => '28', 'TO' => '17'
        ];

        return $ufs[strtoupper($uf)] ?? '35'; // SP como padrão
    }

    private function gerarQRCode(string $chave, int $ambiente, string $uf): string
    {
        $baseUrl = ($ambiente == 2) 
            ? 'https://homologacao.nfce.sefaz.' . strtolower($uf) . '.gov.br'
            : 'https://nfce.sefaz.' . strtolower($uf) . '.gov.br';

        return $baseUrl . '/qrCode?p=' . $chave;
    }

    private function salvarXMLs(string $chave, string $xmlAssinado, string $xmlRetorno, string $empresaId): void
    {
        $empresaDir = $this->storagePath . '/' . $empresaId;
        if (!is_dir($empresaDir)) {
            mkdir($empresaDir, 0755, true);
        }

        // Salvar XML assinado
        file_put_contents($empresaDir . '/' . $chave . '-nfe.xml', $xmlAssinado);

        // Salvar XML de retorno
        file_put_contents($empresaDir . '/' . $chave . '-retorno.xml', $xmlRetorno);

        $this->logger->info('XMLs salvos', ['empresa' => $empresaId, 'chave' => $chave]);
    }
}
