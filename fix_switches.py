#!/usr/bin/env python3
with open('lib/pages/pdv_page.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Fix 1: _getIconeTipoRecebimento - add mercado_pago before closing }
old1 = """      case TipoPagamento.cashBack:
        return Icons.local_atm;
    }
  };"""

new1 = """      case TipoPagamento.cashBack:
        return Icons.local_atm;
      case TipoPagamento.mercado_pago:
        return Icons.qr_code;
    }
  };"""

content = content.replace(old1, new1)

# Fix 2: _getCorTipoRecebimento - add mercado_pago before closing }
old2 = """      case TipoPagamento.cashBack:
        return Colors.amber;
    }
  }"""

new2 = """      case TipoPagamento.cashBack:
        return Colors.amber;
      case TipoPagamento.mercado_pago:
        return Colors.deepPurple;
    }
  }"""

content = content.replace(old2, new2)

# Fix 3: _nomeTipoPagamento - add mercado_pago before default
old3 = """      case TipoPagamento.transferencia: return 'Transferência';
      default: return tipo.name;
    }"""

new3 = """      case TipoPagamento.transferencia: return 'Transferência';
      case TipoPagamento.mercado_pago: return 'Mercado Pago';
      default: return tipo.name;
    }"""

content = content.replace(old3, new3)

# Fix 4: _getIconeTipo - add mercado_pago before closing }
old4 = """      case TipoPagamento.cashBack:
        return Icons.local_atm;
    }
  }"""

new4 = """      case TipoPagamento.cashBack:
        return Icons.local_atm;
      case TipoPagamento.mercado_pago:
        return Icons.qr_code;
    }
  }"""

content = content.replace(old4, new4)

# Fix 5: _getCorTipo - add mercado_pago before closing }
old5 = """      case TipoPagamento.cashBack:
        return Colors.amber;
    }
  }"""

new5 = """      case TipoPagamento.cashBack:
        return Colors.amber;
      case TipoPagamento.mercado_pago:
        return Colors.deepPurple;
    }
  }"""

content = content.replace(old5, new5)

with open('lib/pages/pdv_page.dart', 'w', encoding='utf-8') as f:
    f.write(content)

print("All 5 switches fixed")