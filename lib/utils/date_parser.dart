/// Helper para lidar com datas vindas do Firebase ou LocalStorage
class DateParser {
  /// Converte dinamicamente um valor para DateTime
  /// Suporta: String (ISO 8601), Timestamp (Firestore), DateTime, int (ms)
  static DateTime parse(dynamic value, {DateTime? defaultValue}) {
    if (value == null) return defaultValue ?? DateTime.now();
    if (value is DateTime) return value;
    
    if (value is String) {
      return DateTime.tryParse(value) ?? defaultValue ?? DateTime.now();
    }
    
    // Suporte para Timestamps do Firestore sem depender do pacote
    try {
      if (value.runtimeType.toString() == 'Timestamp' || value.runtimeType.toString() == '_JsonTimestamp') {
        return (value as dynamic).toDate();
      }
    } catch (_) {}

    // Fallback para objetos que tenham toDate() ou similar
    try {
      return (value as dynamic).toDate();
    } catch (_) {}

    // Suporte para milissegundos
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value is double) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }

    return defaultValue ?? DateTime.now();
  }
}
