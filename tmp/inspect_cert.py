import base64
from OpenSSL import crypto

def inspect_cert(cert_base64, password):
    try:
        cert_data = base64.b64decode(cert_base64)
        p12 = crypto.load_pkcs12(cert_data, password.encode())
        cert = p12.get_certificate()
        subject = cert.get_subject()
        print(f"Subject: {subject}")
        print(f"CNPJ found: {getattr(subject, 'CN', 'N/A')}")
        print(f"Issuer: {cert.get_issuer()}")
        print(f"Not Before: {cert.get_notBefore()}")
        print(f"Not After: {cert.get_notAfter()}")
        
        # Check components
        for i in range(subject.get_entry_count()):
            entry = subject.get_entry(i)
            print(f"  {entry.get_type()}: {entry.get_data().decode('utf-8', 'ignore')}")

    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    # From logs
    pwd = "Rotwailler1"
    # I'll truncated the base64 but enough to check headers if needed or I can just print it's validity
    print("Inspecting provided certificate base64...")
    # I'll use a placeholder for the actual extraction since I don't want to paste a mega string here
    # but I can extract it from the log I saw earlier.
