import 'package:flutter/widgets.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:crypto/crypto.dart';
import 'dart:typed_data';
import 'dart:convert';

/// Serviço para geração de QR Code da NFC-e
class QRCodeService {
  /// Gera string do QR Code conforme layout oficial da NFC-e
  static String gerarStringQRCode({
    required String chaveAcesso,
    required String urlConsulta,
    required String csc,
    required String cscIdToken,
    required bool ambienteHomologacao,
    required DateTime dataEmissao,
    required double valorTotal,
  }) {
    // Formato: URL?chNFe=CHAVE&nVersao=100&tpAmb=AMBIENTE&cDest=CSC&dhEmi=DATA&vNF=VALOR&vICMS=0.00&digVal=DIGEST&cIdToken=TOKEN
    
    final tpAmb = ambienteHomologacao ? '2' : '1';
    final dhEmi = dataEmissao.toUtc().toIso8601String();
    final vNF = valorTotal.toStringAsFixed(2);
    
    // Calcular digest value (hash SHA-1 da chave de acesso)
    final digest = _calcularDigest(chaveAcesso);
    
    final qrCodeString = '$urlConsulta?chNFe=$chaveAcesso&nVersao=100&tpAmb=$tpAmb&cDest=$csc&dhEmi=$dhEmi&vNF=$vNF&vICMS=0.00&digVal=$digest&cIdToken=$cscIdToken';
    
    return qrCodeString;
  }

  /// Calcula digest value (hash SHA-1) da chave de acesso
  static String _calcularDigest(String chaveAcesso) {
    // TODO: Implementar cálculo correto do digest conforme especificação
    // Por enquanto, usar hash SHA-1 simples
    final bytes = utf8.encode(chaveAcesso);
    final hash = sha1.convert(bytes);
    return base64Encode(hash.bytes);
  }

  /// Gera widget QR Code para exibição
  static Widget gerarWidgetQRCode(
    String qrCodeString, {
    double size = 200,
    Color? foregroundColor,
    Color? backgroundColor,
  }) {
    return QrImageView(
      data: qrCodeString,
      version: QrVersions.auto,
      size: size,
      foregroundColor: foregroundColor ?? const Color(0xFF000000),
      backgroundColor: backgroundColor ?? const Color(0xFFFFFFFF),
      errorCorrectionLevel: QrErrorCorrectLevel.M,
    );
  }

  /// Gera imagem do QR Code como bytes
  static Future<Uint8List> gerarImagemQRCode(
    String qrCodeString, {
    double size = 200,
  }) async {
    // TODO: Implementar geração de imagem do QR Code
    // Usar QrPainter para desenhar em um canvas
    throw UnimplementedError('Geração de imagem QR Code ainda não implementada');
  }
}

