const fs = require('fs');

const data = JSON.parse(fs.readFileSync('deploy_payload.json', 'utf8'));

for (const file of data.files) {
  // Remove multi-line comments
  file.content = file.content.replace(/\/\*[\s\S]*?\*\//g, '');
  // Remove single line comments that are not part of a URL
  file.content = file.content.replace(/(?<!:)\/\/.*$/gm, '');
  // Remove extra whitespace
  file.content = file.content.replace(/\s+/g, ' ');
}

fs.writeFileSync('deploy_payload_min.json', JSON.stringify(data));
console.log("Minified size:", fs.statSync('deploy_payload_min.json').size);
