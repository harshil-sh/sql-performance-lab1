const fs = require('fs');
const path = require('path');

const baseDir = 'C:\\Users\\Harshil\\source\\repos\\harshil-sh\\sql-performance-lab1\\scenarios';

const dirs = [
  path.join(baseDir, '04_window_functions'),
  path.join(baseDir, '05_keyset_pagination'),
  path.join(baseDir, '06_index_fragmentation')
];

dirs.forEach(dir => {
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, '.gitkeep'), '');
  console.log(`Created: ${dir}/.gitkeep`);
});

console.log('All directories created successfully');
