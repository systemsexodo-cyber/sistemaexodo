
import os

files = [
    r'c:\Users\USER\.gemini\antigravity\sistema_exodo_01-12\lib\services\venda_pdf_service.dart',
    r'c:\Users\USER\.gemini\antigravity\sistema_exodo_01-12\lib\services\pedido_pdf_service.dart'
]

def fix_pdf_service(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    new_lines = []
    in_obs_block = False
    
    for line in lines:
        if '/// Constrói observações térmico' in line:
            in_obs_block = True
            # Determine if it's VendaBalcao or Pedido based on filepath
            type_obj = 'VendaBalcao venda' if 'venda_pdf' in filepath else 'Pedido pedido'
            var_obj = 'venda' if 'venda_pdf' in filepath else 'pedido'
            
            new_lines.append(f'  /// Constrói observações térmico\n')
            new_lines.append(f'  static pw.Widget _buildObservacoesTermico({type_obj}, double fontSizeCorpo) {{\n')
            new_lines.append(f'    if ({var_obj}.observacoes == null || {var_obj}.observacoes!.trim().isEmpty) return pw.SizedBox.shrink();\n')
            new_lines.append(f'    \n')
            new_lines.append(f'    return pw.Column(\n')
            new_lines.append(f'      crossAxisAlignment: pw.CrossAxisAlignment.start,\n')
            new_lines.append(f'      children: [\n')
            new_lines.append(f'        pw.Divider(thickness: 0.5),\n')
            new_lines.append(f'        pw.SizedBox(height: 1),\n')
            new_lines.append(f'        pw.Text(\n')
            new_lines.append(f"          'OBSERVAÇÕES:',\n")
            new_lines.append(f'          style: pw.TextStyle(\n')
            new_lines.append(f'            fontSize: fontSizeCorpo,\n')
            new_lines.append(f'            fontWeight: pw.FontWeight.bold,\n')
            new_lines.append(f'          ),\n')
            new_lines.append(f'        ),\n')
            new_lines.append(f'        pw.SizedBox(height: 1),\n')
            new_lines.append(f'        pw.Text(\n')
            new_lines.append(f'          {var_obj}.observacoes!,\n')
            new_lines.append(f'          style: pw.TextStyle(fontSize: fontSizeCorpo),\n')
            new_lines.append(f'        ),\n')
            new_lines.append(f'        pw.SizedBox(height: 2),\n')
            new_lines.append(f'      ],\n')
            new_lines.append(f'    );\n')
            new_lines.append(f'  }}\n')
            continue
        
        if in_obs_block:
            if line.strip() == '}':
                in_obs_block = False
            continue
            
        new_lines.append(line)

    with open(filepath, 'w', encoding='utf-8') as f:
        f.writelines(new_lines)

for f in files:
    fix_pdf_service(f)
print("Observation prints fixed successfully")
