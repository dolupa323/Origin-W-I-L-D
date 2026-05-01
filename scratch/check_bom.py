def check_bom(file_path):
    with open(file_path, 'rb') as f:
        raw = f.read(4)
    
    if raw.startswith(b'\xef\xbb\xbf'):
        print("UTF-8 BOM detected")
    elif raw.startswith(b'\xff\xfe') or raw.startswith(b'\xfe\xff'):
        print("UTF-16 BOM detected")
    else:
        print("No BOM detected")

if __name__ == "__main__":
    target_file = r"c:\YJS\Roblox\Origin-WILD\src\ServerScriptService\Server\Services\BaseClaimService.lua"
    check_bom(target_file)
