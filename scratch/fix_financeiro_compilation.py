import os

file_nfe = r"c:\Users\charles\.antigravity\sistema_exodo_15-04-2026\lib\pages\nfe_page.dart"
file_form = r"c:\Users\charles\.antigravity\sistema_exodo_15-04-2026\lib\pages\conta_pagar_form_page.dart"

# 1. Injetar import de conta_pagar.dart no nfe_page.dart
with open(file_nfe, "r", encoding="utf-8") as f:
    content_nfe = f.read()

import_nfe_target = "import '../models/nfce.dart';"
import_nfe_replacement = "import '../models/nfce.dart';\nimport '../models/conta_pagar.dart';"

if import_nfe_target in content_nfe:
    content_nfe = content_nfe.replace(import_nfe_target, import_nfe_replacement)
    print("IMPORT_CONTA_PAGAR_INJETADO")
else:
    print("FALHA_AO_INJETAR_IMPORT_CONTA_PAGAR")

with open(file_nfe, "w", encoding="utf-8") as f:
    f.write(content_nfe)


# 2. Adicionar categoriaPredefinida no construtor de ContaPagarFormPage
with open(file_form, "r", encoding="utf-8") as f:
    content_form = f.read()

target_form_class = """class ContaPagarFormPage extends StatefulWidget {
  final ContaPagar? contaPagar;

  const ContaPagarFormPage({super.key, this.contaPagar});"""

replacement_form_class = """class ContaPagarFormPage extends StatefulWidget {
  final ContaPagar? contaPagar;
  final String? categoriaPredefinida;

  const ContaPagarFormPage({super.key, this.contaPagar, this.categoriaPredefinida});"""

if target_form_class in content_form:
    content_form = content_form.replace(target_form_class, replacement_form_class)
    print("CONSTRUTOR_FORM_ATUALIZADO")
else:
    normalized_content = content_form.replace("\r\n", "\n")
    normalized_target = target_form_class.replace("\r\n", "\n")
    normalized_replacement = replacement_form_class.replace("\r\n", "\n")
    if normalized_target in normalized_content:
        normalized_content = normalized_content.replace(normalized_target, normalized_replacement)
        content_form = normalized_content
        print("CONSTRUTOR_FORM_NORMALIZADO")
    else:
        print("FALHA_AO_ATUALIZAR_CONSTRUTOR_FORM")


# 3. Adicionar lógica no initState de ContaPagarFormPage
target_initstate = """  @override
  void initState() {
    super.initState();
    _carregarCategoriasExistentes();
    if (widget.contaPagar != null) {"""

replacement_initstate = """  @override
  void initState() {
    super.initState();
    _carregarCategoriasExistentes();
    if (widget.categoriaPredefinida != null) {
      _categoriaController.text = widget.categoriaPredefinida!;
    }
    if (widget.contaPagar != null) {"""

if target_initstate in content_form:
    content_form = content_form.replace(target_initstate, replacement_initstate)
    print("INITSTATE_FORM_ATUALIZADO")
else:
    normalized_content = content_form.replace("\r\n", "\n")
    normalized_target = target_initstate.replace("\r\n", "\n")
    normalized_replacement = replacement_initstate.replace("\r\n", "\n")
    if normalized_target in normalized_content:
        normalized_content = normalized_content.replace(normalized_target, normalized_replacement)
        content_form = normalized_content
        print("INITSTATE_FORM_NORMALIZADO")
    else:
        print("FALHA_AO_ATUALIZAR_INITSTATE_FORM")

with open(file_form, "w", encoding="utf-8") as f:
    f.write(content_form)
