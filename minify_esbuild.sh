#!/bin/bash
mkdir -p temp_files
jq -c '.files[]' deploy_payload.json | while read i; do
  name=$(echo $i | jq -r '.name')
  content=$(echo $i | jq -r '.content')
  
  mkdir -p "temp_files/$(dirname "$name")"
  echo "$content" > "temp_files/$name"
  
  if [[ "$name" == *.ts ]]; then
    npx esbuild "temp_files/$name" --minify --loader=ts > "temp_files/$name.min"
    mv "temp_files/$name.min" "temp_files/$name"
  fi
done

node -e "
const fs = require('fs');
const data = JSON.parse(fs.readFileSync('deploy_payload.json', 'utf8'));
for (const file of data.files) {
  file.content = fs.readFileSync('temp_files/' + file.name, 'utf8');
}
fs.writeFileSync('deploy_payload_esbuild.json', JSON.stringify(data));
console.log('Minified size:', fs.statSync('deploy_payload_esbuild.json').size);
"
