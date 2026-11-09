import requests
import json
import os

invoke_url = "https://integrate.api.nvidia.com/v1/chat/completions"
stream = False  # Alterado para False para simplificar a captura e execução das ferramentas no loop

headers = {
    "Authorization": "Bearer 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",
    "Accept": "application/json",
    "Content-Type": "application/json"
}

# --- DEFINIÇÃO DAS FERRAMENTAS QUE O PYTHON VAI EXECUTAR PARA A IA ---
def listar_diretorio():
    """Lista todos os arquivos da pasta atual do projeto"""
    try:
        arquivos = os.listdir('.')
        return f"Arquivos no projeto: {arquivos}"
    except Exception as e:
        return f"Erro ao ler diretório: {str(e)}"

def ler_arquivo(nome_arquivo):
    """Lê o conteúdo de um arquivo específico"""
    try:
        with open(nome_arquivo, 'r', encoding='utf-8') as f:
            return f.read()
    except Exception as e:
        return f"Erro ao ler arquivo: {str(e)}"

def criar_ou_editar_arquivo(nome_arquivo, conteudo):
    """Cria ou sobrescreve um arquivo com um novo código/texto"""
    try:
        with open(nome_arquivo, 'w', encoding='utf-8') as f:
            f.write(conteudo)
        return f"Arquivo '{nome_arquivo}' salvo com sucesso!"
    except Exception as e:
        return f"Erro ao salvar arquivo: {str(e)}"

# Mapeamento para execução dinâmica
tools_map = {
    "listar_diretorio": listar_diretorio,
    "ler_arquivo": ler_arquivo,
    "criar_ou_editar_arquivo": criar_ou_editar_arquivo
}

# Definição das ferramentas no formato que a API da NVIDIA entende
tools_definition = [
    {
        "type": "function",
        "function": {
            "name": "listar_diretorio",
            "description": "Lista todos os arquivos e pastas do diretório atual do projeto.",
            "parameters": {"type": "object", "properties": {}}
        }
    },
    {
        "type": "function",
        "function": {
            "name": "ler_arquivo",
            "description": "Lê o conteúdo de um arquivo específico do projeto para analisar o código.",
            "parameters": {
                "type": "object",
                "properties": {
                    "nome_arquivo": {"type": "string", "description": "O nome do arquivo a ser lido (ex: main.py)"}
                },
                "required": ["nome_arquivo"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "criar_ou_editar_arquivo",
            "description": "Cria um novo arquivo ou atualiza um arquivo existente com o código fornecido.",
            "parameters": {
                "type": "object",
                "properties": {
                    "nome_arquivo": {"type": "string", "description": "Nome do arquivo a ser criado/salvo"},
                    "conteudo": {"type": "string", "description": "O código completo ou texto a ser gravado"}
                },
                "required": ["nome_arquivo", "conteudo"]
            }
        }
    }
]

chat_history = [
    {
        "role": "system", 
        "content": "Você é o Nemotron, um agente autônomo de programação. Você tem acesso ao sistema de arquivos do usuário através de ferramentas. Use as ferramentas sempre que precisar inspecionar a pasta, ler códigos ou salvar modificações pedidas pelo usuário."
    }
]

print("=" * 60)
print("🤖 AGENTE NVIDIA NEMOTRON 3.5 - ACESSO AO PROJETO ATIVADO")
print("=" * 60)

while True:
    user_input = input("\nVocê: ")
    
    if user_input.lower().strip() == 'sair':
        print("\nEncerrando o agente. Até logo!")
        break
        
    if not user_input.strip():
        continue

    chat_history.append({"role": "user", "content": user_input})

    # Loop para processar interações em cadeia (IA pede ferramenta -> Python executa -> IA responde)
    while True:
        payload = {
          "model": "nvidia/nemotron-3.5-bolt-e4b",
          "messages": chat_history,
          "temperature": 0.3, # Menor temperatura garante maior precisão no uso de ferramentas
          "top_p": 0.95,
          "max_tokens": 2048,
          "stream": False,
          "tools": tools_definition,
          "tool_choice": "auto"
        }

        try:
            response = requests.post(invoke_url, headers=headers, json=payload)
            
            if response.status_code != 200:
                print(f"\n[Erro NVIDIA]: {response.text}")
                break

            response_json = response.json()
            message = response_json["choices"][0]["message"]
            
            # 1. Se a IA decidiu chamar uma ferramenta (ler/escrever arquivo)
            if "tool_calls" in message and message["tool_calls"]:
                chat_history.append(message) # Adiciona a intenção da IA ao histórico
                
                for tool_call in message["tool_calls"]:
                    function_name = tool_call["function"]["name"]
                    arguments = json.loads(tool_call["function"]["arguments"])
                    tool_call_id = tool_call["id"]
                    
                    print(f"\n⚙️ [Executando Ação]: {function_name}({arguments})")
                    
                    # Executa a função nativa do Python
                    func_para_executar = tools_map[function_name]
                    resultado_execucao = func_para_executar(**arguments)
                    
                    # Devolve o resultado do arquivo/pasta para a IA
                    chat_history.append({
                        "role": "tool",
                        "tool_call_id": tool_call_id,
                        "name": function_name,
                        "content": resultado_execucao
                    })
                
                # Continua o loop para a IA ler o resultado que o Python coletou
                continue 
            
            # 2. Se a IA apenas respondeu em texto final para o usuário
            else:
                texto_resposta = message.get("content", "")
                print(f"\nResposta da IA:\n{texto_resposta}")
                print("\n" + "-"*30)
                chat_history.append({"role": "assistant", "content": texto_resposta})
                break # Sai do loop interno e espera o próximo comando do usuário

        except Exception as e:
            print(f"\nErro no script: {e}")
            break
