def clean_utf8(file_path):
    with open(file_path, 'rb') as f:
        raw_data = f.read()
    
    # If the file was corrupted by my latin-1 conversion, 
    # we need to revert it if possible. 
    # But since I wrote it as utf-8, the latin-1 chars are now multi-byte utf-8.
    
    # Let's try to decode what we have now (the latin-1 version) 
    # and see if we can recover the original bytes.
    try:
        current_content = raw_data.decode('utf-8')
        # Re-encode to latin-1 to get original bytes (this works because latin-1 maps 1-to-1)
        original_bytes = current_content.encode('latin-1')
        
        # Now try to decode original bytes as utf-8 properly
        try:
            proper_content = original_bytes.decode('utf-8')
            print("Successfully recovered original UTF-8 content!")
            with open(file_path, 'w', encoding='utf-8') as f:
                f.write(proper_content)
        except UnicodeDecodeError:
            # If it still fails, it probably had some bad bytes.
            # Let's try decoding with 'replace'
            proper_content = original_bytes.decode('utf-8', errors='replace')
            print("Recovered with replacements for invalid bytes.")
            with open(file_path, 'w', encoding='utf-8') as f:
                f.write(proper_content)
                
    except Exception as e:
        print(f"Error during cleaning: {e}")

if __name__ == "__main__":
    target_file = r"c:\YJS\Roblox\Origin-WILD\src\ServerScriptService\Server\Services\BaseClaimService.lua"
    clean_utf8(target_file)
