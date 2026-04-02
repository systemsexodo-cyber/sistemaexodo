import pynfe
import os

with open(r'c:\Users\USER\.gemini\antigravity\sistema_exodo_01-12\tmp\path.txt', 'w') as f:
    f.write(os.path.dirname(pynfe.__file__))
