import os

file_path = r"c:\Users\charles\.antigravity\sistema_exodo_15-04-2026\lib\pages\venda_direta_page.dart"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# --- 1. Injetar getters globais no topo do _VendaDiretaPageState ---
target_class_top = """class _VendaDiretaPageState extends State<VendaDiretaPage> {
  ViewMode _viewMode = ViewMode.grid;"""

replacement_class_top = """class _VendaDiretaPageState extends State<VendaDiretaPage> {
  bool get isDark => Theme.of(context).brightness == Brightness.dark;
  Color get textColor => isDark ? Colors.white : Colors.black87;
  Color get subTextColor => isDark ? Colors.white70 : Colors.black54;

  ViewMode _viewMode = _somenteMesaComanda ? ViewMode.mesaComanda : ViewMode.grid;"""

# Nota: vamos verificar se a linha 171 do arquivo original bate com ViewMode _viewMode = ViewMode.grid; ou similar.
# No view_file anterior vimos:
# 170: class _VendaDiretaPageState extends State<VendaDiretaPage> {
# 171:   ViewMode _viewMode = ViewMode.grid;

target_class_top_real = """class _VendaDiretaPageState extends State<VendaDiretaPage> {
  ViewMode _viewMode = ViewMode.grid;"""

replacement_class_top_real = """class _VendaDiretaPageState extends State<VendaDiretaPage> {
  bool get isDark => Theme.of(context).brightness == Brightness.dark;
  Color get textColor => isDark ? Colors.white : Colors.black87;
  Color get subTextColor => isDark ? Colors.white70 : Colors.black54;

  ViewMode _viewMode = ViewMode.grid;"""

if target_class_top_real in content:
    content = content.replace(target_class_top_real, replacement_class_top_real)
    print("GETTERS_GLOBAIS_INJETADOS")
else:
    print("FALHA_AO_INJETAR_GETTERS_GLOBAIS")


# --- 2. Alterar o fundo do painel do carrinho lateral direito (linhas 11040-11043 e 11067-11070) ---
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

if target_carrinho_bg1 in content:
    content = content.replace(target_carrinho_bg1, replacement_carrinho_bg1)
    print("CARRINHO_BG_ATUALIZADO")
else:
    normalized_content = content.replace("\r\n", "\n")
    normalized_target = target_carrinho_bg1.replace("\r\n", "\n")
    normalized_replacement = replacement_carrinho_bg1.replace("\r\n", "\n")
    if normalized_target in normalized_content:
        normalized_content = normalized_content.replace(normalized_target, normalized_replacement)
        content = normalized_content
        print("CARRINHO_BG_NORMALIZADO")
    else:
        print("FALHA_AO_ATUALIZAR_CARRINHO_BG")


# --- 3. Corrigir o fundo e borda do container da barra superior de busca ---
target_barra_superior = """  Widget _buildBarraSuperior(DataService dataService) {
    final isSmallHeight = MediaQuery.of(context).size.height < 750;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 800;

    // Elementos da barra
    final searchField = Expanded(
      flex: 3,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue.withOpacity(0.3)),
        ),"""

replacement_barra_superior = """  Widget _buildBarraSuperior(DataService dataService) {
    final isSmallHeight = MediaQuery.of(context).size.height < 750;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 800;

    // Elementos da barra
    final searchField = Expanded(
      flex: 3,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isDark ? Colors.blue.withOpacity(0.3) : Colors.black12),
        ),"""

if target_barra_superior in content:
    content = content.replace(target_barra_superior, replacement_barra_superior)
    print("BARRA_SUPERIOR_CORRIGIDA")
else:
    normalized_content = content.replace("\r\n", "\n")
    normalized_target = target_barra_superior.replace("\r\n", "\n")
    normalized_replacement = replacement_barra_superior.replace("\r\n", "\n")
    if normalized_target in normalized_content:
        normalized_content = normalized_content.replace(normalized_target, normalized_replacement)
        content = normalized_content
        print("BARRA_SUPERIOR_NORMALIZADA")
    else:
        print("FALHA_AO_CORRIGIR_BARRA_SUPERIOR")


# --- 4. Corrigir o TextField da busca (texto e placeholder dinâmicos) ---
target_textfield = """            style: TextStyle(color: Colors.white, fontSize: isSmallHeight ? 14 : 15),
            decoration: InputDecoration(
              hintText: _categoriaAtiva != null ? '🔍 $_categoriaAtiva...' : '🔍 Buscar...',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: isSmallHeight ? 12 : 13),"""

replacement_textfield = """            style: TextStyle(color: textColor, fontSize: isSmallHeight ? 14 : 15),
            decoration: InputDecoration(
              hintText: _categoriaAtiva != null ? '🔍 $_categoriaAtiva...' : '🔍 Buscar...',
              hintStyle: TextStyle(color: textColor.withOpacity(0.4), fontSize: isSmallHeight ? 12 : 13),"""

if target_textfield in content:
    content = content.replace(target_textfield, replacement_textfield)
    print("TEXTFIELD_STYLE_CORRIGIDO")
else:
    normalized_content = content.replace("\r\n", "\n")
    normalized_target = target_textfield.replace("\r\n", "\n")
    normalized_replacement = replacement_textfield.replace("\r\n", "\n")
    if normalized_target in normalized_content:
        normalized_content = normalized_content.replace(normalized_target, normalized_replacement)
        content = normalized_content
        print("TEXTFIELD_STYLE_NORMALIZADO")
    else:
        print("FALHA_AO_CORRIGIR_TEXTFIELD_STYLE")


# --- 5. Corrigir a cor de fundo e textos dos botões de categorias ---
# Categoria "Todos"
target_todos = """                          color: isActive ? null : const Color(0xFF1E1E2E),
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
                                color: isActive ? Colors.white : Colors.white70,"""

replacement_todos = """                          color: isActive ? null : (isDark ? const Color(0xFF1E1E2E) : Colors.white),
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
                                color: isActive ? Colors.white : (isDark ? Colors.white70 : Colors.black87),"""

if target_todos in content:
    content = content.replace(target_todos, replacement_todos)
    print("CATEGORIA_TODOS_CORRIGIDA")
else:
    normalized_content = content.replace("\r\n", "\n")
    normalized_target = target_todos.replace("\r\n", "\n")
    normalized_replacement = replacement_todos.replace("\r\n", "\n")
    if normalized_target in normalized_content:
        normalized_content = normalized_content.replace(normalized_target, normalized_replacement)
        content = normalized_content
        print("CATEGORIA_TODOS_NORMALIZADA")
    else:
        print("FALHA_AO_CORRIGIR_CATEGORIA_TODOS")


# Categoria genérica loop
target_loop = """                        color: isActive ? null : const Color(0xFF1E1E2E),
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
                              color: isActive ? Colors.white : Colors.white70,"""

replacement_loop = """                        color: isActive ? null : (isDark ? const Color(0xFF1E1E2E) : Colors.white),
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
                              color: isActive ? Colors.white : (isDark ? Colors.white70 : Colors.black87),"""

if target_loop in content:
    content = content.replace(target_loop, replacement_loop)
    print("CATEGORIA_LOOP_CORRIGIDA")
else:
    normalized_content = content.replace("\r\n", "\n")
    normalized_target = target_loop.replace("\r\n", "\n")
    normalized_replacement = replacement_loop.replace("\r\n", "\n")
    if normalized_target in normalized_content:
        normalized_content = normalized_content.replace(normalized_target, normalized_replacement)
        content = normalized_content
        print("CATEGORIA_LOOP_NORMALIZADA")
    else:
        print("FALHA_AO_CORRIGIR_CATEGORIA_LOOP")


# --- 6. Otimizar as fontes do carrinho melhorado para usar textColor e subTextColor da classe principal ---
# Apenas trocar o cabeçalho e subtextos dentro de _buildCarrinhoMelhorado
target_carrinho_melhorado_header = """              Text(
                'CARRINHO',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  letterSpacing: 1.5,
                ),
              ),"""

replacement_carrinho_melhorado_header = """              Text(
                'CARRINHO',
                style: TextStyle(
                  color: textColor.withOpacity(0.9),
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  letterSpacing: 1.5,
                ),
              ),"""

if target_carrinho_melhorado_header in content:
    content = content.replace(target_carrinho_melhorado_header, replacement_carrinho_melhorado_header)
    print("CARRINHO_HEADER_ATUALIZADO")
else:
    normalized_content = content.replace("\r\n", "\n")
    normalized_target = target_carrinho_melhorado_header.replace("\r\n", "\n")
    normalized_replacement = replacement_carrinho_melhorado_header.replace("\r\n", "\n")
    if normalized_target in normalized_content:
        normalized_content = normalized_content.replace(normalized_target, normalized_replacement)
        content = normalized_content
        print("CARRINHO_HEADER_NORMALIZADO")
    else:
        print("FALHA_AO_ATUALIZAR_CARRINHO_HEADER")

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)
