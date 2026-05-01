def fix_encoding(file_path):
    encodings = ['utf-8', 'cp949', 'euc-kr', 'utf-16', 'latin-1']
    
    with open(file_path, 'rb') as f:
        raw_data = f.read()
    
    for enc in encodings:
        try:
            content = raw_data.decode(enc)
            print(f"Successfully decoded with {enc}")
            
            # Write back as utf-8
            with open(file_path, 'w', encoding='utf-8') as f:
                f.write(content)
            print(f"Successfully converted {file_path} to UTF-8 using {enc}")
            return
        except Exception:
            continue
    
    print("Failed to decode with all attempted encodings.")

if __name__ == "__main__":
    target_file = r"c:\YJS\Roblox\Origin-WILD\src\ServerScriptService\Server\Services\BaseClaimService.lua"
    fix_encoding(target_file)
