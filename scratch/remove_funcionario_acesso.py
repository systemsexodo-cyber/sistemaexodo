import os

file_path = r"c:\Users\charles\.antigravity\sistema_exodo_15-04-2026\lib\pages\funcionarios_page.dart"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# --- 1. Ocultar checkbox de permissão no Adicionar Funcionário ---
target_add = """                  const SizedBox(height: 16),
                  CheckboxListTile(
                    title: const Text(
                      'Permitir acesso ao sistema',
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: const Text(
                      'O funcionário poderá fazer login e ver seus pedidos/comissões',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    value: temAcesso,
                    onChanged: (value) {
                      setState(() {
                        temAcesso = value ?? false;
                      });
                    },
                  ),
                  if (temAcesso) ...[
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: senhaController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Senha para login *',
                        labelStyle: TextStyle(color: Colors.white70),
                        border: OutlineInputBorder(),
                        helperText: 'Senha que o funcionário usará para fazer login',
                        helperMaxLines: 2,
                      ),
                      obscureText: obscureSenha,
                      keyboardType: TextInputType.visiblePassword,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Checkbox(
                          value: obscureSenha,
                          onChanged: (value) {
                            setState(() {
                              obscureSenha = value ?? true;
                            });
                          },
                        ),
                        const Text(
                          'Mostrar senha',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ],"""

# Como queremos apenas remover a interface visual mantendo a compilabilidade, podemos substituir por nada
if target_add in content:
    content = content.replace(target_add, "")
    print("ACESS_ADD_REMOVIDO")
else:
    normalized_content = content.replace("\r\n", "\n")
    normalized_target = target_add.replace("\r\n", "\n")
    if normalized_target in normalized_content:
        normalized_content = normalized_content.replace(normalized_target, "")
        content = normalized_content
        print("ACESS_ADD_NORMALIZADO_REMOVIDO")
    else:
        print("FALHA_AO_REMOVER_ACESS_ADD")


# --- 2. Ocultar checkbox de permissão no Editar Funcionário ---
target_edit = """                  const SizedBox(height: 16),
                  CheckboxListTile(
                    title: const Text(
                      'Permitir acesso ao sistema',
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: const Text(
                      'O funcionário poderá fazer login e ver seus pedidos/comissões',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    value: temAcesso,
                    onChanged: (value) {
                      setState(() {
                        temAcesso = value ?? false;
                      });
                    },
                  ),
                  if (temAcesso) ...[
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: senhaController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: funcionario.temAcesso ? 'Nova senha (deixe em branco para manter)' : 'Senha para login *',
                        labelStyle: const TextStyle(color: Colors.white70),
                        border: const OutlineInputBorder(),
                        helperText: funcionario.temAcesso 
                            ? 'Deixe em branco para manter a senha atual'
                            : 'Senha que o funcionário usará para fazer login',
                        helperMaxLines: 2,
                      ),
                      obscureText: obscureSenha,
                      keyboardType: TextInputType.visiblePassword,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Checkbox(
                          value: obscureSenha,
                          onChanged: (value) {
                            setState(() {
                              obscureSenha = value ?? true;
                            });
                          },
                        ),
                        const Text(
                          'Mostrar senha',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ],"""

if target_edit in content:
    content = content.replace(target_edit, "")
    print("ACESS_EDIT_REMOVIDO")
else:
    normalized_content = content.replace("\r\n", "\n")
    normalized_target = target_edit.replace("\r\n", "\n")
    if normalized_target in normalized_content:
        normalized_content = normalized_content.replace(normalized_target, "")
        content = normalized_content
        print("ACESS_EDIT_NORMALIZADO_REMOVIDO")
    else:
        print("FALHA_AO_REMOVER_ACESS_EDIT")

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)
