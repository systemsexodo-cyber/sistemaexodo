from pathlib import Path
p=Path(r'C:\Users\charles\.antigravity\sistema_exodo_15-04-2026\lib\pages\loja_publica_page.dart')
s=p.read_text(encoding='utf-8-sig')
bs=chr(92)
for old,new in [(bs+'${item.quantidade}', '${item.quantidade}'), (bs+'${item.nome}', '${item.nome}'), (bs+'${carrinho.totalItens}', '${carrinho.totalItens}'), (bs+'$resumo', '$resumo'), (bs+'${restantes', '${restantes'), (bs+'$restantes', '$restantes')]:
    s=s.replace(old,new)
p.write_text(s,encoding='utf-8-sig',newline='')
print('Interpolacoes corrigidas.')