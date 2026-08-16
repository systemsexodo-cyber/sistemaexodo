import os

file_path = r"c:\Users\charles\.antigravity\sistema_exodo_15-04-2026\lib\pages\venda_direta_page.dart"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# --- 1. Injetar isDark no topo do _buildScaffoldContexto ---
target_scaffold_top = """  Widget _buildScaffoldContexto(
    BuildContext context, 
    DataService dataService, 
    List<dynamic> itensEncontrados,
    List<String> categorias,
    List<Produto> produtosCategoria
  ) {
    final screenWidth = MediaQuery.of(context).size.width;"""

replacement_scaffold_top = """  Widget _buildScaffoldContexto(
    BuildContext context, 
    DataService dataService, 
    List<dynamic> itensEncontrados,
    List<String> categorias,
    List<Produto> produtosCategoria
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;"""

if target_scaffold_top in content:
    content = content.replace(target_scaffold_top, replacement_scaffold_top)
    print("SCAFFOLD_TOP_ATUALIZADO")
else:
    print("FALHA_AO_ATUALIZAR_SCAFFOLD_TOP")


# --- 2. Atualizar as cores de fundo do painel do carrinho lateral direito (duas ocorrências de gradientes escuros) ---
target_carrinho_bg1 = """                            colors: [
                              const Color(0xFF0D0D15),
                              const Color(0xFF12121C),
                            ],
                            borderRadius: BorderRadius.circular(20),"""

replacement_carrinho_bg1 = """                            colors: isDark ? [
                              const Color(0xFF0D0D15),
                              const Color(0xFF12121C),
                            ] : [
                              Colors.white,
                              const Color(0xFFF1F5F9),
                            ],
                            borderRadius: BorderRadius.circular(20),"""

content = content.replace(target_carrinho_bg1, replacement_carrinho_bg1)
print("CARRINHO_BG1_ATUALIZADO")


# --- 3. Atualizar a cor de fundo da barra superior de busca ---
target_barra_superior_top = """  Widget _buildBarraSuperior(DataService dataService) {
    final isSmallHeight = MediaQuery.of(context).size.height < 750;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 800;

    // Elementos da barra
    final searchField = Expanded(
      flex: 3,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2E),"""

replacement_barra_superior_top = """  Widget _buildBarraSuperior(DataService dataService) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSmallHeight = MediaQuery.of(context).size.height < 750;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 800;

    // Elementos da barra
    final searchField = Expanded(
      flex: 3,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
          border: Border.all(color: isDark ? Colors.transparent : Colors.black12),"""

if target_barra_superior_top in content:
    content = content.replace(target_barra_superior_top, replacement_barra_superior_top)
    print("BARRA_SUPERIOR_BG_ATUALIZADO")
else:
    print("FALHA_AO_ATUALIZAR_BARRA_SUPERIOR_BG")


# --- 4. Corrigir o TextField da barra superior (cor do texto e placeholder dinâmicas) ---
target_textfield_style = """            style: TextStyle(color: Colors.white, fontSize: isSmallHeight ? 14 : 15),
            decoration: InputDecoration(
              hintText: _categoriaAtiva != null ? '🔍 $_categoriaAtiva...' : '🔍 Buscar...',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: isSmallHeight ? 12 : 13),"""

replacement_textfield_style = """            style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: isSmallHeight ? 14 : 15),
            decoration: InputDecoration(
              hintText: _categoriaAtiva != null ? '🔍 $_categoriaAtiva...' : '🔍 Buscar...',
              hintStyle: TextStyle(color: isDark ? Colors.white.withOpacity(0.4) : Colors.black38, fontSize: isSmallHeight ? 12 : 13),"""

if target_textfield_style in content:
    content = content.replace(target_textfield_style, replacement_textfield_style)
    print("TEXTFIELD_STYLE_ATUALIZADO")
else:
    print("FALHA_AO_ATUALIZAR_TEXTFIELD_STYLE")


# --- 5. Atualizar as cores de categorias para serem dinâmicas baseadas em isDark ---
# Categoria "Todos"
target_categoria_todos = """                          color: isActive ? null : const Color(0xFF1E1E2E),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? Colors.cyanAccent
                                : (isActive
                                      ? Colors.blue
                                      : Colors.white.withOpacity(0.1)),
                            width: isSelected ? 3 : 1,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.apps_rounded,
                              color: isActive ? Colors.white : Colors.white60,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Todos',
                              style: TextStyle(
                                color: isActive ? Colors.white : Colors.white70,
                                fontWeight: isActive"""

replacement_categoria_todos = """                          color: isActive ? null : (isDark ? const Color(0xFF1E1E2E) : Colors.white),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? Colors.cyanAccent
                                : (isActive
                                      ? Colors.blue
                                      : (isDark ? Colors.white.withOpacity(0.1) : Colors.black12)),
                            width: isSelected ? 3 : 1,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.apps_rounded,
                              color: isActive ? Colors.white : (isDark ? Colors.white60 : Colors.black54),
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Todos',
                              style: TextStyle(
                                color: isActive ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                                fontWeight: isActive"""

if target_categoria_todos in content:
    content = content.replace(target_categoria_todos, replacement_categoria_todos)
    print("CATEGORIA_TODOS_ATUALIZADA")
else:
    print("FALHA_AO_ATUALIZAR_CATEGORIA_TODOS")


# Categoria genérica loop
target_categoria_loop = """                        color: isActive ? null : const Color(0xFF1E1E2E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? Colors.cyanAccent
                              : (isActive
                                    ? (index % 2 == 0 ? Colors.purple : Colors.orange)
                                    : Colors.white.withOpacity(0.1)),
                          width: isSelected ? 3 : 1,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            index % 2 == 0 ? Icons.laptop_chromebook : Icons.widgets,
                            color: isActive ? Colors.white : Colors.white60,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            categoria,
                            style: TextStyle(
                              color: isActive ? Colors.white : Colors.white70,
                              fontWeight: isActive"""

replacement_categoria_loop = """                        color: isActive ? null : (isDark ? const Color(0xFF1E1E2E) : Colors.white),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? Colors.cyanAccent
                              : (isActive
                                    ? (index % 2 == 0 ? Colors.purple : Colors.orange)
                                    : (isDark ? Colors.white.withOpacity(0.1) : Colors.black12)),
                          width: isSelected ? 3 : 1,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            index % 2 == 0 ? Icons.laptop_chromebook : Icons.widgets,
                            color: isActive ? Colors.white : (isDark ? Colors.white60 : Colors.black54),
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            categoria,
                            style: TextStyle(
                              color: isActive ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                              fontWeight: isActive"""

# Vamos tentar buscar na forma alternativa (pois a linha 12151 tem 'color: isActive ? null : const Color(0xFF1E1E2E),')
if target_categoria_loop in content:
    content = content.replace(target_categoria_loop, replacement_categoria_loop)
    print("CATEGORIA_LOOP_ATUALIZADA")
else:
    # Forma alternativa manual via string replace simplificado
    content = content.replace("color: isActive ? null : const Color(0xFF1E1E2E),", "color: isActive ? null : (isDark ? const Color(0xFF1E1E2E) : Colors.white),")
    content = content.replace("color: isActive ? Colors.white : Colors.white60,", "color: isActive ? Colors.white : (isDark ? Colors.white60 : Colors.black54),")
    content = content.replace("color: isActive ? Colors.white : Colors.white70,", "color: isActive ? Colors.white : (isDark ? Colors.white70 : Colors.black87),")
    print("CATEGORIA_LOOP_ATUALIZADA_ALT")

# --- 6. Otimizar as fontes do carrinho melhorado para tema claro ---
# Adicionar final isDark e textColor no início do _buildCarrinhoMelhorado
target_carrinho_melhorado = """  Widget _buildCarrinhoMelhorado(DataService dataService) {
    return Column(
      children: ["""

replacement_carrinho_melhorado = """  Widget _buildCarrinhoMelhorado(DataService dataService) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white70 : Colors.black54;

    return Column(
      children: ["""

if target_carrinho_melhorado in content:
    content = content.replace(target_carrinho_melhorado, replacement_carrinho_melhorado)
    print("CARRINHO_MELHORADO_VARS_INJETADAS")
else:
    print("FALHA_AO_INJETAR_CARRINHO_MELHORADO_VARS")

# Ajustar o título "CARRINHO" e totalizador
content = content.replace("color: Colors.white.withOpacity(0.9),", "color: textColor.withOpacity(0.9),")
content = content.replace("color: Colors.white.withOpacity(0.5),", "color: subTextColor,")
content = content.replace("color: Colors.white.withOpacity(0.6),", "color: subTextColor,")
content = content.replace("color: Colors.white60,", "color: subTextColor,")
print("TEXTOS_CARRINHO_ATUALIZADOS")

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)
