const fs = require('fs');
const { execSync } = require('child_process');

const data = JSON.parse(fs.readFileSync('deploy_payload.json', 'utf8'));

for (const file of data.files) {
  if (file.name.endsWith('.ts')) {
    fs.writeFileSync('temp.ts', file.content);
    execSync('npx esbuild temp.ts --minify > temp.min.ts');
    file.content = fs.readFileSync('temp.min.ts', 'utf8');
  }
}

fs.writeFileSync('deploy_payload_esbuild.json', JSON.stringify(data));
console.log("Minified size:", fs.statSync('deploy_payload_esbuild.json').size);
