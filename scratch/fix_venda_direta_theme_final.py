import os

file_path = r"c:\Users\charles\.antigravity\sistema_exodo_15-04-2026\lib\pages\venda_direta_page.dart"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# --- 1. Substituir os gradientes do carrinho na lateral direita (duas ocorrências no modo duas colunas) ---
target_grad1 = """                            colors: [
                              const Color(0xFF0D0D15),
                              const Color(0xFF12121C),
                            ],"""

replacement_grad1 = """                            colors: isDark ? [
                              const Color(0xFF0D0D15),
                              const Color(0xFF12121C),
                            ] : [
                              Colors.white,
                              const Color(0xFFF1F5F9),
                            ],"""

content = content.replace(target_grad1, replacement_grad1)
print("GRADIENTES_DUAS_COLUNAS_ATUALIZADOS")


# --- 2. Substituir a cor sólida do carrinho no modo tabbed (linha 11070) ---
target_solid_carrinho = """                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0D0D15),
                                    borderRadius: BorderRadius.circular(20),
                                  ),"""

replacement_solid_carrinho = """                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF0D0D15) : Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                    border: isDark ? null : Border.all(color: Colors.black12),
                                  ),"""

content = content.replace(target_solid_carrinho, replacement_solid_carrinho)
print("CARRINHO_SOLID_ATUALIZADO")


# --- 3. Substituir a cor de fundo das categorias no loop e no "Todos" ---
# Categoria "Todos"
target_todos_color = """                          color: isActive ? null : (isDark ? const Color(0xFF1E1E2E) : Colors.white),"""
# (Já está correto no arquivo, mas vamos certificar a cor do border)
target_todos_border = """                          border: Border.all(
                            color: isSelected
                                ? Colors.cyanAccent
                                : (isActive
                                      ? Colors.blue
                                      : Colors.white.withOpacity(0.1)),
                            width: isSelected ? 3 : 1,
                          ),"""

replacement_todos_border = """                          border: Border.all(
                            color: isSelected
                                ? Colors.cyanAccent
                                : (isActive
                                      ? Colors.blue
                                      : (isDark ? Colors.white.withOpacity(0.1) : Colors.black12)),
                            width: isSelected ? 3 : 1,
                          ),"""

content = content.replace(target_todos_border, replacement_todos_border)
print("BORDER_TODOS_ATUALIZADO")


# Categoria genérica loop
target_loop_color = """                        color: isActive ? null : const Color(0xFF1E1E2E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? Colors.cyanAccent
                              : (isActive
                                    ? (index % 2 == 0 ? Colors.purple : Colors.orange)
                                    : Colors.white.withOpacity(0.1)),
                          width: isSelected ? 3 : 1,
                        ),"""

replacement_loop_color = """                        color: isActive ? null : (isDark ? const Color(0xFF1E1E2E) : Colors.white),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? Colors.cyanAccent
                              : (isActive
                                    ? (index % 2 == 0 ? Colors.purple : Colors.orange)
                                    : (isDark ? Colors.white.withOpacity(0.1) : Colors.black12)),
                          width: isSelected ? 3 : 1,
                        ),"""

content = content.replace(target_loop_color, replacement_loop_color)
print("CATEGORIA_LOOP_ATUALIZADA_COMPLETO")


# --- 4. Ajustar as cores dos textos e ícones não ativos no loop de categorias ---
target_loop_icons = """                          Icon(
                            index % 2 == 0 ? Icons.laptop_chromebook : Icons.widgets,
                            color: isActive ? Colors.white : Colors.white60,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            categoria,
                            style: TextStyle(
                              color: isActive ? Colors.white : Colors.white70,"""

replacement_loop_icons = """                          Icon(
                            index % 2 == 0 ? Icons.laptop_chromebook : Icons.widgets,
                            color: isActive ? Colors.white : (isDark ? Colors.white60 : Colors.black54),
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            categoria,
                            style: TextStyle(
                              color: isActive ? Colors.white : (isDark ? Colors.white70 : Colors.black87),"""

content = content.replace(target_loop_icons, replacement_loop_icons)
print("ICONS_E_TEXTOS_CATEGORIA_LOOP_ATUALIZADOS")


with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)
