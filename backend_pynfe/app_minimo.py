"""
Backend MÍNIMO - Versão que SEMPRE funciona
"""

from flask import Flask, jsonify
from flask_cors import CORS

app = Flask(__name__)
CORS(app)

@app.route('/health', methods=['GET'])
def health():
    return jsonify({
        'status': 'ok',
        'message': 'Backend funcionando!',
        'pynfe_disponivel': False
    })

@app.route('/api/nfce/emitir', methods=['POST'])
def emitir_nfce():
    return jsonify({
        'success': False,
        'error': 'PyNFe não está instalado. Esta é uma versão mínima de teste.'
    }), 503

@app.route('/api/certificado/validar', methods=['POST'])
def validar_certificado():
    return jsonify({
        'success': False,
        'error': 'Serviço de certificado não disponível nesta versão mínima'
    }), 503

if __name__ == '__main__':
    print('=' * 50)
    print('🚀 Backend MÍNIMO - Teste')
    print('=' * 50)
    print('🌐 URL: http://localhost:5000')
    print('📡 Health: http://localhost:5000/health')
    print('=' * 50)
    print('')
    print('Pressione Ctrl+C para parar')
    print('')
    
    app.run(host='0.0.0.0', port=5000, debug=False)


