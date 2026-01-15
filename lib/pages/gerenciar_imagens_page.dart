import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'dart:typed_data';
import '../services/auth_service.dart';
import '../services/image_storage_service.dart';
import '../theme.dart';
import 'package:intl/intl.dart';

/// Página para gerenciar imagens armazenadas gratuitamente no Firestore
class GerenciarImagensPage extends StatefulWidget {
  const GerenciarImagensPage({super.key});

  @override
  State<GerenciarImagensPage> createState() => _GerenciarImagensPageState();
}

class _GerenciarImagensPageState extends State<GerenciarImagensPage> {
  List<Map<String, dynamic>> _imagens = [];
  Map<String, dynamic> _estatisticas = {};
  String? _categoriaFiltro;
  bool _isLoading = false;
  bool _carregandoEstatisticas = false;

  final List<String> _categorias = [
    'produtos',
    'clientes',
    'pets',
    'loja',
    'banners',
    'logos',
    'outros',
  ];

  @override
  void initState() {
    super.initState();
    _carregarImagens();
    _carregarEstatisticas();
  }

  Future<void> _carregarImagens() async {
    setState(() => _isLoading = true);

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final empresa = authService.empresaAtual;
      if (empresa == null) return;

      final imagens = await ImageStorageService.listarImagens(
        empresaId: empresa.id,
        categoria: _categoriaFiltro,
      );

      setState(() {
        _imagens = imagens;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('>>> Erro ao carregar imagens: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar imagens: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _carregarEstatisticas() async {
    setState(() => _carregandoEstatisticas = true);

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final empresa = authService.empresaAtual;
      if (empresa == null) return;

      final stats = await ImageStorageService.obterEstatisticas(empresa.id);

      setState(() {
        _estatisticas = stats;
        _carregandoEstatisticas = false;
      });
    } catch (e) {
      debugPrint('>>> Erro ao carregar estatísticas: $e');
      setState(() => _carregandoEstatisticas = false);
    }
  }

  Future<void> _uploadImagem() async {
    try {
      FilePickerResult? result;
      if (kIsWeb) {
        result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: false,
          withData: true,
        );
      } else {
        result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: false,
        );
      }

      if (result == null || result.files.isEmpty) return;

      final authService = Provider.of<AuthService>(context, listen: false);
      final empresa = authService.empresaAtual;
      if (empresa == null) return;

      final file = result.files.first;
      Uint8List? imageBytes;

      if (kIsWeb) {
        imageBytes = file.bytes;
      } else if (file.path != null) {
        // Para mobile, precisaríamos ler o arquivo
        // Por enquanto, vamos focar no web
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Upload de imagens no mobile será implementado em breve'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      if (imageBytes == null || imageBytes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro ao ler arquivo'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Mostrar diálogo para selecionar categoria e nome
      final resultado = await showDialog<Map<String, String>>(
        context: context,
        builder: (context) => _DialogUploadImagem(categorias: _categorias),
      );

      if (resultado == null) return;

      // Mostrar loading
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Comprimindo e salvando imagem...'),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      // Salvar imagem
      await ImageStorageService.salvarImagem(
        imageBytes: imageBytes,
        empresaId: empresa.id,
        categoria: resultado['categoria']!,
        nome: resultado['nome'],
      );

      if (mounted) {
        Navigator.pop(context); // Fechar loading
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Imagem salva com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        _carregarImagens();
        _carregarEstatisticas();
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Fechar loading se ainda estiver aberto
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao fazer upload: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deletarImagem(String imagemId, String nome) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Confirmar Exclusão', style: TextStyle(color: Colors.white)),
        content: Text('Deseja realmente deletar "$nome"?', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Deletar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    final sucesso = await ImageStorageService.deletarImagem(imagemId);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(sucesso ? 'Imagem deletada!' : 'Erro ao deletar imagem'),
          backgroundColor: sucesso ? Colors.green : Colors.red,
        ),
      );
      if (sucesso) {
        _carregarImagens();
        _carregarEstatisticas();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Gerenciar Imagens'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.upload),
              tooltip: 'Upload de Imagem',
              onPressed: _uploadImagem,
            ),
          ],
        ),
        body: Column(
          children: [
            // Estatísticas
            if (_estatisticas.isNotEmpty)
              Card(
                margin: const EdgeInsets.all(16),
                color: Colors.white.withOpacity(0.1),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.storage, color: Colors.white),
                          const SizedBox(width: 8),
                          const Text(
                            'Estatísticas de Armazenamento',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _buildEstatisticaCard(
                              'Total de Imagens',
                              '${_estatisticas['totalImagens'] ?? 0}',
                              Icons.image,
                              Colors.blue,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildEstatisticaCard(
                              'Tamanho Total',
                              '${_estatisticas['tamanhoTotalMB'] ?? '0.00'} MB',
                              Icons.data_usage,
                              Colors.green,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '💡 Armazenamento GRATUITO no Firestore (plano Spark)',
                        style: TextStyle(
                          color: Colors.green[300],
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Filtros
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _categoriaFiltro,
                      decoration: InputDecoration(
                        labelText: 'Filtrar por Categoria',
                        labelStyle: TextStyle(color: Colors.white70),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.white30),
                        ),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.1),
                      ),
                      dropdownColor: Colors.grey[900],
                      style: const TextStyle(color: Colors.white),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('Todas as Categorias'),
                        ),
                        ..._categorias.map((cat) => DropdownMenuItem(
                              value: cat,
                              child: Text(cat.toUpperCase()),
                            )),
                      ],
                      onChanged: (value) {
                        setState(() => _categoriaFiltro = value);
                        _carregarImagens();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Atualizar',
                    onPressed: () {
                      _carregarImagens();
                      _carregarEstatisticas();
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Lista de imagens
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _imagens.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.image_not_supported, size: 64, color: Colors.white38),
                              const SizedBox(height: 16),
                              Text(
                                'Nenhuma imagem encontrada',
                                style: TextStyle(color: Colors.white70),
                              ),
                              const SizedBox(height: 8),
                              ElevatedButton.icon(
                                onPressed: _uploadImagem,
                                icon: const Icon(Icons.upload),
                                label: const Text('Fazer Upload'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _imagens.length,
                          itemBuilder: (context, index) {
                            final imagem = _imagens[index];
                            return _buildCardImagem(imagem);
                          },
                        ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _uploadImagem,
          backgroundColor: Colors.green,
          icon: const Icon(Icons.upload),
          label: const Text('Upload'),
        ),
      ),
    );
  }

  Widget _buildEstatisticaCard(String titulo, String valor, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  titulo,
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            valor,
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardImagem(Map<String, dynamic> imagem) {
    final tamanhoKB = (imagem['tamanhoBytes'] as int? ?? 0) / 1024;
    final tamanhoOriginalKB = (imagem['tamanhoOriginalBytes'] as int? ?? 0) / 1024;
    final dataUpload = imagem['dataUpload'] as DateTime?;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.white.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Preview da imagem
            FutureBuilder<String?>(
              future: ImageStorageService.obterImagem(imagem['id'] as String),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.grey[800],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }

                if (snapshot.hasData && snapshot.data != null) {
                  return Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white30),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        snapshot.data!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: Colors.grey[800],
                            child: const Icon(Icons.error, color: Colors.red),
                          );
                        },
                      ),
                    ),
                  );
                }

                return Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.grey[800],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.image, color: Colors.grey),
                );
              },
            ),

            const SizedBox(width: 12),

            // Informações
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    imagem['nome'] as String? ?? 'Sem nome',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          (imagem['categoria'] as String? ?? 'outros').toUpperCase(),
                          style: TextStyle(
                            color: Colors.blue[300],
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Comprimido: ${tamanhoKB.toStringAsFixed(2)} KB (Original: ${tamanhoOriginalKB.toStringAsFixed(2)} KB)',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  if (dataUpload != null)
                    Text(
                      'Upload: ${DateFormat('dd/MM/yyyy HH:mm').format(dataUpload)}',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                ],
              ),
            ),

            // Botão deletar
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              tooltip: 'Deletar',
              onPressed: () => _deletarImagem(
                imagem['id'] as String,
                imagem['nome'] as String? ?? 'Imagem',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogUploadImagem extends StatefulWidget {
  final List<String> categorias;

  const _DialogUploadImagem({required this.categorias});

  @override
  State<_DialogUploadImagem> createState() => _DialogUploadImagemState();
}

class _DialogUploadImagemState extends State<_DialogUploadImagem> {
  final _nomeController = TextEditingController();
  String _categoriaSelecionada = 'outros';

  @override
  void dispose() {
    _nomeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.grey[900],
      title: const Text('Upload de Imagem', style: TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nomeController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Nome da Imagem',
              labelStyle: TextStyle(color: Colors.white70),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.white30),
              ),
              filled: true,
              fillColor: Colors.white.withOpacity(0.1),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _categoriaSelecionada,
            decoration: InputDecoration(
              labelText: 'Categoria',
              labelStyle: TextStyle(color: Colors.white70),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.white30),
              ),
              filled: true,
              fillColor: Colors.white.withOpacity(0.1),
            ),
            dropdownColor: Colors.grey[800],
            style: const TextStyle(color: Colors.white),
            items: widget.categorias.map((cat) {
              return DropdownMenuItem(
                value: cat,
                child: Text(cat.toUpperCase()),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => _categoriaSelecionada = value);
              }
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context, {
              'nome': _nomeController.text.trim(),
              'categoria': _categoriaSelecionada,
            });
          },
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}













