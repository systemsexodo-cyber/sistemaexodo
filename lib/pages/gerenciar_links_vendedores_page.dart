import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sistema_exodo_novo/models/link_vendedor.dart';
import 'package:sistema_exodo_novo/models/funcionario.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/services/auth_service.dart';
import 'package:sistema_exodo_novo/theme.dart';
import 'package:sistema_exodo_novo/widgets/sync_status_widget.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:html' as html;

class GerenciarLinksVendedoresPage extends StatefulWidget {
  const GerenciarLinksVendedoresPage({super.key});

  @override
  State<GerenciarLinksVendedoresPage> createState() => _GerenciarLinksVendedoresPageState();
}

class _GerenciarLinksVendedoresPageState extends State<GerenciarLinksVendedoresPage> {
  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataService>(context);
    final links = dataService.linksVendedores;
    final funcionarios = dataService.funcionarios;
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Gerenciar Links de Vendedores'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: Navigator.canPop(context)
              ? IconButton(
                  icon: Icon(
                    Icons.arrow_back,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                )
              : null,
          actions: [
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Criar novo link',
              onPressed: () => _mostrarDialogoCriarLink(funcionarios),
            ),
            const SyncStatusWidget(),
          ],
        ),
        body: Column(
          children: [
            // Card do Link Fixo da Loja
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.withOpacity(0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.store, color: Colors.blue[300]),
                      const SizedBox(width: 8),
                      const Text(
                        'Link Fixo da Loja',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Este é o link principal da sua loja (sem vendedor específico):',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _obterLinkFixoLoja(),
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 14,
                              color: Colors.white,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy, color: Colors.blue),
                          tooltip: 'Copiar link fixo',
                          onPressed: () => _copiarLinkFixo(),
                        ),
                        IconButton(
                          icon: const Icon(Icons.share, color: Colors.blue),
                          tooltip: 'Compartilhar link fixo',
                          onPressed: () => _compartilharLinkFixo(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Lista de Links dos Vendedores
            Expanded(
              child: links.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.link_off, size: 64, color: Colors.white.withOpacity(0.5)),
                        const SizedBox(height: 16),
                        Text(
                          'Nenhum link de vendedor criado',
                          style: TextStyle(fontSize: 18, color: Colors.white.withOpacity(0.7)),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: () => _mostrarDialogoCriarLink(funcionarios),
                          icon: const Icon(Icons.add),
                          label: const Text('Criar Primeiro Link'),
                        ),
                      ],
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Text(
                          'Links dos Vendedores',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white.withOpacity(0.9),
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: links.length,
                          itemBuilder: (context, index) {
                            final link = links[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 16),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: link.ativo ? Colors.green : Colors.grey,
                                  child: Icon(
                                    link.ativo ? Icons.link : Icons.link_off,
                                    color: Colors.white,
                                  ),
                                ),
                                title: Text(link.funcionarioNome),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Icon(Icons.code, size: 14, color: Colors.white.withOpacity(0.7)),
                                        const SizedBox(width: 4),
                                        Text(
                                          link.codigoLink,
                                          style: const TextStyle(
                                            fontFamily: 'monospace',
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.copy, size: 18),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: () => _copiarLink(link),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      link.urlCompleta,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.blue[700],
                                        fontFamily: 'monospace',
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${link.totalVendas} vendas • ${formatoMoeda.format(link.totalComissao)} em comissões',
                                      style: const TextStyle(fontSize: 12, color: Colors.white70),
                                    ),
                                    Text(
                                      '${link.percentualComissao}% de comissão',
                                      style: const TextStyle(fontSize: 12, color: Colors.white70),
                                    ),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.share),
                                      tooltip: 'Compartilhar link',
                                      onPressed: () => _compartilharLink(link),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.edit),
                                      tooltip: 'Editar',
                                      onPressed: () => _mostrarDialogoEditarLink(link, funcionarios),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete),
                                      tooltip: 'Excluir',
                                      onPressed: () => _confirmarExcluirLink(link),
                                    ),
                                  ],
                                ),
                                onTap: () => _mostrarDetalhesLink(link, formatoMoeda),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
            ),
          ],
        ),
      ),
    );
  }

  void _mostrarDialogoCriarLink(List<Funcionario> funcionarios) {
    if (funcionarios.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cadastre funcionários antes de criar links'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    Funcionario? funcionarioSelecionado;
    final percentualController = TextEditingController(text: '10.0');
    final codigoController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: const Color(0xFF10151B),
          title: const Text(
            'Criar Link de Vendedor',
            style: TextStyle(color: Colors.white),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<Funcionario>(
                  decoration: const InputDecoration(
                    labelText: 'Vendedor *',
                    border: OutlineInputBorder(),
                  ),
                  items: funcionarios.map((f) {
                    return DropdownMenuItem(
                      value: f,
                      child: Text(f.nome),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      funcionarioSelecionado = value;
                      if (codigoController.text.isEmpty) {
                        codigoController.text = _gerarCodigoLink();
                      }
                    });
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: codigoController,
                  decoration: const InputDecoration(
                    labelText: 'Código do Link *',
                    border: OutlineInputBorder(),
                    helperText: 'Código único para o link (ex: ABC123)',
                  ),
                  readOnly: true,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: percentualController,
                  decoration: const InputDecoration(
                    labelText: 'Percentual de Comissão (%) *',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: funcionarioSelecionado == null
                  ? null
                  : () {
                      _criarLink(
                        funcionarioSelecionado!,
                        codigoController.text,
                        double.tryParse(percentualController.text) ?? 10.0,
                      );
                      Navigator.pop(context);
                    },
              child: const Text('Criar'),
            ),
          ],
        ),
      ),
    );
  }

  void _mostrarDialogoEditarLink(LinkVendedor link, List<Funcionario> funcionarios) {
    final percentualController = TextEditingController(text: link.percentualComissao.toString());
    bool ativo = link.ativo;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: const Color(0xFF10151B),
          title: const Text(
            'Editar Link',
            style: TextStyle(color: Colors.white),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(link.funcionarioNome),
                  subtitle: Text('Código: ${link.codigoLink}'),
                ),
                const Divider(),
                TextFormField(
                  controller: percentualController,
                  decoration: const InputDecoration(
                    labelText: 'Percentual de Comissão (%) *',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  title: const Text('Link Ativo'),
                  value: ativo,
                  onChanged: (value) {
                    setState(() {
                      ativo = value ?? true;
                    });
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                _atualizarLink(
                  link,
                  double.tryParse(percentualController.text) ?? link.percentualComissao,
                  ativo,
                );
                Navigator.pop(context);
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  /// Obtém o link fixo da loja (sem vendedor específico)
  String _obterLinkFixoLoja() {
    final urlBase = kIsWeb ? html.window.location.origin : 'https://seusite.com';
    // Link fixo: /loja
    return '$urlBase/loja';
  }

  /// Copia o link fixo da loja para a área de transferência
  void _copiarLinkFixo() {
    final linkFixo = _obterLinkFixoLoja();
    Clipboard.setData(ClipboardData(text: linkFixo));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Link fixo copiado: $linkFixo'),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.green,
      ),
    );
  }

  /// Compartilha o link fixo da loja
  void _compartilharLinkFixo() {
    final linkFixo = _obterLinkFixoLoja();
    if (kIsWeb) {
      // No web, usar Web Share API se disponível
      try {
        html.window.navigator.share({
          'title': 'Loja Online',
          'text': 'Confira nossa loja online!',
          'url': linkFixo,
        });
      } catch (e) {
        // Se não suportar, copiar para clipboard
        _copiarLinkFixo();
      }
    } else {
      _copiarLinkFixo();
    }
  }

  String _gerarCodigoLink() {
    // Gera um código único de 6 caracteres (letras e números)
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = DateTime.now().millisecondsSinceEpoch;
    String codigo = '';
    for (int i = 0; i < 6; i++) {
      codigo += chars[(random + i) % chars.length];
    }
    return codigo;
  }

  /// Gera um slug (URL amigável) a partir do nome da empresa
  String _gerarSlugNomeLoja(String nome) {
    // Converter para minúsculas
    String slug = nome.toLowerCase();
    
    // Remover acentos e caracteres especiais
    slug = slug
        .replaceAll(RegExp(r'[áàâãä]'), 'a')
        .replaceAll(RegExp(r'[éèêë]'), 'e')
        .replaceAll(RegExp(r'[íìîï]'), 'i')
        .replaceAll(RegExp(r'[óòôõö]'), 'o')
        .replaceAll(RegExp(r'[úùûü]'), 'u')
        .replaceAll(RegExp(r'[ç]'), 'c')
        .replaceAll(RegExp(r'[ñ]'), 'n');
    
    // Remover caracteres especiais, manter apenas letras, números e espaços
    slug = slug.replaceAll(RegExp(r'[^a-z0-9\s-]'), '');
    
    // Substituir espaços e múltiplos hífens por um único hífen
    slug = slug.replaceAll(RegExp(r'[\s-]+'), '-');
    
    // Remover hífens no início e fim
    slug = slug.replaceAll(RegExp(r'^-+|-+$'), '');
    
    // Limitar tamanho (máximo 50 caracteres)
    if (slug.length > 50) {
      slug = slug.substring(0, 50);
      // Remover hífen no final se cortou no meio
      slug = slug.replaceAll(RegExp(r'-+$'), '');
    }
    
    // Se ficou vazio, usar "loja"
    if (slug.isEmpty) {
      slug = 'loja';
    }
    
    return slug;
  }

  /// Gera URL completa personalizada com o nome da loja
  String _gerarUrlCompleta(String codigoLink, String? nomeLoja) {
    final urlBase = kIsWeb ? html.window.location.origin : 'https://seusite.com';
    
    if (nomeLoja != null && nomeLoja.isNotEmpty) {
      final slug = _gerarSlugNomeLoja(nomeLoja);
      // Formato: https://seusite.com/loja/nome-da-loja/ABC123
      return '$urlBase/loja/$slug/$codigoLink';
    } else {
      // Fallback: formato antigo
      return '$urlBase/loja?link=$codigoLink';
    }
  }

  Future<void> _criarLink(
    Funcionario funcionario,
    String codigoLink,
    double percentualComissao,
  ) async {
    final dataService = Provider.of<DataService>(context, listen: false);
    final authService = Provider.of<AuthService>(context, listen: false);

    // Verificar se o código já existe
    final codigoExiste = dataService.linksVendedores
        .any((l) => l.codigoLink == codigoLink);
    if (codigoExiste) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Este código já está em uso'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Obter nome da loja (empresa atual)
    final nomeLoja = authService.empresaAtual?.nomeExibicao;
    
    // Gerar URL completa personalizada com o nome da loja
    final urlCompleta = _gerarUrlCompleta(codigoLink, nomeLoja);

    final link = LinkVendedor(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      funcionarioId: funcionario.id,
      funcionarioNome: funcionario.nome,
      codigoLink: codigoLink,
      urlCompleta: urlCompleta,
      percentualComissao: percentualComissao,
      ativo: true,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await dataService.addLinkVendedor(link);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Link criado com sucesso!'),
              const SizedBox(height: 4),
              Text(
                urlCompleta,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
            ],
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _atualizarLink(
    LinkVendedor link,
    double percentualComissao,
    bool ativo,
  ) async {
    final dataService = Provider.of<DataService>(context, listen: false);
    final authService = Provider.of<AuthService>(context, listen: false);
    
    // Atualizar URL se o nome da loja mudou
    final nomeLoja = authService.empresaAtual?.nomeExibicao;
    final urlCompleta = _gerarUrlCompleta(link.codigoLink, nomeLoja);
    
    final linkAtualizado = link.copyWith(
      percentualComissao: percentualComissao,
      ativo: ativo,
      urlCompleta: urlCompleta,
      updatedAt: DateTime.now(),
    );

    await dataService.updateLinkVendedor(linkAtualizado);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Link atualizado'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _confirmarExcluirLink(LinkVendedor link) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF10151B),
        title: const Text(
          'Excluir Link',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Deseja realmente excluir o link ${link.codigoLink}?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              final dataService = Provider.of<DataService>(context, listen: false);
              dataService.deleteLinkVendedor(link.id);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Link excluído'),
                  backgroundColor: Colors.orange,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
  }

  void _copiarLink(LinkVendedor link) {
    Clipboard.setData(ClipboardData(text: link.urlCompleta));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Link copiado: ${link.urlCompleta}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _compartilharLink(LinkVendedor link) {
    if (kIsWeb) {
      // No web, usar Web Share API se disponível
      try {
        html.window.navigator.share({
          'title': 'Link de Vendedor - ${link.funcionarioNome}',
          'text': 'Compre através do meu link e eu ganho comissão!',
          'url': link.urlCompleta,
        });
      } catch (e) {
        // Se não suportar, copiar para clipboard
        _copiarLink(link);
      }
    } else {
      _copiarLink(link);
    }
  }

  void _mostrarDetalhesLink(LinkVendedor link, NumberFormat formatoMoeda) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF10151B),
        title: Text(
          'Detalhes do Link - ${link.funcionarioNome}',
          style: const TextStyle(color: Colors.white),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoRow('Código', link.codigoLink),
              _buildInfoRow('URL', link.urlCompleta),
              _buildInfoRow('Percentual', '${link.percentualComissao}%'),
              _buildInfoRow('Status', link.ativo ? 'Ativo' : 'Inativo'),
              _buildInfoRow('Total de Vendas', link.totalVendas.toString()),
              _buildInfoRow('Total de Comissões', formatoMoeda.format(link.totalComissao)),
              _buildInfoRow('Criado em', DateFormat('dd/MM/yyyy HH:mm').format(link.createdAt)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _copiarLink(link);
              Navigator.pop(context);
            },
            child: const Text('Copiar Link'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white70,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontFamily: 'monospace',
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
