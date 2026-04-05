import os
import sys

base_dir = r'C:\Users\Harshil\source\repos\harshil-sh\sql-performance-lab1\scenarios'

dirs = [
    os.path.join(base_dir, '04_window_functions'),
    os.path.join(base_dir, '05_keyset_pagination'),
    os.path.join(base_dir, '06_index_fragmentation')
]

for dir_path in dirs:
    os.makedirs(dir_path, exist_ok=True)
    gitkeep_path = os.path.join(dir_path, '.gitkeep')
    with open(gitkeep_path, 'w') as f:
        pass
    print(f'Created: {gitkeep_path}')

print('All directories created successfully')
