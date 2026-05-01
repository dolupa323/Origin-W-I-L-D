import os

def check_all_lua_files(root_dir):
    invalid_files = []
    for root, dirs, files in os.walk(root_dir):
        for file in files:
            if file.endswith('.lua'):
                file_path = os.path.join(root, file)
                try:
                    with open(file_path, 'rb') as f:
                        raw_data = f.read()
                    raw_data.decode('utf-8')
                except UnicodeDecodeError:
                    invalid_files.append(file_path)
    return invalid_files

if __name__ == "__main__":
    src_dir = r"c:\YJS\Roblox\Origin-WILD\src"
    invalids = check_all_lua_files(src_dir)
    if invalids:
        print("Invalid UTF-8 files found:")
        for f in invalids:
            print(f)
    else:
        print("All .lua files are valid UTF-8.")
