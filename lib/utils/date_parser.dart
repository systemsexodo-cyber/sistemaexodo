/// Helper para lidar com datas vindas do Firebase ou LocalStorage
class DateParser {
  /// Converte dinamicamente um valor para DateTime
  /// Suporta: String (ISO 8601), Timestamp (Firestore), DateTime, int (ms)
  static DateTime parse(dynamic value, {DateTime? defaultValue}) {
    if (value == null) return (defaultValue ?? DateTime.now()).toLocal();
    if (value is DateTime) return value.toLocal();
    
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed.toLocal();
      return (defaultValue ?? DateTime.now()).toLocal();
    }
    
    // Suporte para Timestamps do Firestore sem depender do pacote
    try {
      if (value.runtimeType.toString() == 'Timestamp' || value.runtimeType.toString() == '_JsonTimestamp') {
        return (value as dynamic).toDate().toLocal();
      }
    } catch (_) {}

    // Fallback para objetos que tenham toDate() ou similar
    try {
      return (value as dynamic).toDate().toLocal();
    } catch (_) {}

    // Suporte para milissegundos
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value).toLocal();
    }
    if (value is double) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt()).toLocal();
    }

    return (defaultValue ?? DateTime.now()).toLocal();
  }
}
