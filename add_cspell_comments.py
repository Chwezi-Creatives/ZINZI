import os

def add_cspell_comment_to_file(file_path):
    with open(file_path, 'r+', encoding='utf-8') as f:
        content = f.read()
        if not content.startswith('//cspell:disable'):
            f.seek(0, 0)
            f.write('//cspell:disable\n' + content)
            print(f'Added cspell comment to {file_path}')
        else:
            print(f'{file_path} already has cspell comment')

def process_directory(directory):
    for root, _, files in os.walk(directory):
        for file in files:
            if file.endswith('.dart'):
                file_path = os.path.join(root, file)
                try:
                    add_cspell_comment_to_file(file_path)
                except Exception as e:
                    print(f'Error processing {file_path}: {str(e)}')

if __name__ == '__main__':
    lib_dir = os.path.join(os.path.dirname(__file__), 'lib')
    process_directory(lib_dir)
    print('Finished processing all .dart files')
