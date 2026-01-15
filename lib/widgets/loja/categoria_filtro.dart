import 'package:flutter/material.dart';

class CategoriaFiltro extends StatelessWidget {
  final List<String> categorias;
  final String? categoriaSelecionada;
  final bool mostrarApenasPromocoes;
  final Function(String?) onCategoriaSelected;
  final VoidCallback onPromocoesToggled;
  final Color? corPrimaria;

  const CategoriaFiltro({
    super.key,
    required this.categorias,
    this.categoriaSelecionada,
    required this.mostrarApenasPromocoes,
    required this.onCategoriaSelected,
    required this.onPromocoesToggled,
    this.corPrimaria,
  });

  @override
  Widget build(BuildContext context) {
    if (categorias.isEmpty) return const SizedBox.shrink();
    
    final corP = corPrimaria ?? Theme.of(context).colorScheme.primary;

    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: corP.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.category, size: 18, color: corP),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Categorias',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _buildChipFiltro(
                  context: context,
                  label: 'Todas',
                  isSelected: categoriaSelecionada == null && !mostrarApenasPromocoes,
                  icon: Icons.apps,
                  onTap: () => onCategoriaSelected(null),
                  corPrimaria: corP,
                ),
                const SizedBox(width: 10),
                _buildChipFiltro(
                  context: context,
                  label: 'Promoções',
                  isSelected: mostrarApenasPromocoes,
                  icon: Icons.local_offer,
                  onTap: onPromocoesToggled,
                  corPrimaria: corP,
                ),
                const SizedBox(width: 10),
                ...categorias.map((cat) => Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: _buildChipFiltro(
                        context: context,
                        label: cat,
                        isSelected: categoriaSelecionada == cat,
                        icon: Icons.category,
                        onTap: () => onCategoriaSelected(cat == categoriaSelecionada ? null : cat),
                        corPrimaria: corP,
                      ),
                    )),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildChipFiltro({
    required BuildContext context,
    required String label,
    required bool isSelected,
    required IconData icon,
    required VoidCallback onTap,
    required Color corPrimaria,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? corPrimaria : Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: isSelected ? corPrimaria : Colors.grey[300]!,
              width: isSelected ? 2 : 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: isSelected ? corPrimaria.withOpacity(0.25) : Colors.black.withOpacity(0.04),
                blurRadius: isSelected ? 10 : 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: isSelected ? Colors.white : Theme.of(context).textTheme.bodyMedium?.color),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Theme.of(context).textTheme.bodyLarge?.color,
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
