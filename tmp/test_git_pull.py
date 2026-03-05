import subprocess
import os

def test_pull():
    orig_dir = os.getcwd()
    try:
        os.chdir(r"c:\Users\USER\.gemini\antigravity\sistema_exodo_01-12")
        if not os.path.exists(".git"):
            # Tentar o diretório que o status mostrou
            os.chdir(r"c:\Users\USER\.gemini\antigravity\sistema_exodo_01-12")
            
        print(f"Diretório atual: {os.getcwd()}")
        res = subprocess.run(["git", "pull"], capture_output=True, text=True, timeout=30)
        print(f"Status Code: {res.returncode}")
        print(f"STDOUT: {res.stdout}")
        print(f"STDERR: {res.stderr}")
    except Exception as e:
        print(f"Erro: {e}")
    finally:
        os.chdir(orig_dir)

if __name__ == "__main__":
    test_pull()
