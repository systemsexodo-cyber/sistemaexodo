import pynfe.processamento.serializacao as ser
import re

def test_token(token):
    replacements = {"0": ""}
    token_corrupted = re.sub("([0])", lambda m: replacements[m.group()], token)
    return token_corrupted

print(f"Token '1' -> {test_token('1')}")
print(f"Token '01' -> {test_token('01')}")
print(f"Token '10' -> {test_token('10')}")
print(f"Token '100' -> {test_token('100')}")
print(f"Token '000001' -> {test_token('000001')}")
