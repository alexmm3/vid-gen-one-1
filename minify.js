const fs = require("fs");
const path = require("path");

function getFiles(dir, fileList = []) {
  const files = fs.readdirSync(dir);
  for (const file of files) {
    const stat = fs.statSync(path.join(dir, file));
    if (stat.isDirectory()) {
      getFiles(path.join(dir, file), fileList);
    } else if (file.endsWith(".ts") && !file.includes(".test.")) {
      fileList.push(path.join(dir, file));
    }
  }
  return fileList;
}

const functionDir = "supabase/functions/generate-video";
const sharedDir = "supabase/functions/_shared";

const allFiles = [...getFiles(functionDir), ...getFiles(sharedDir)];

const filesPayload = allFiles.map(file => {
  let relativePath;
  if (file.startsWith(functionDir)) {
    relativePath = file.substring(functionDir.length + 1);
  } else if (file.startsWith(sharedDir)) {
    relativePath = "../" + file.substring("supabase/functions/".length);
  }
  let content = fs.readFileSync(file, "utf8");
  // Basic minification: remove comments and empty lines
  content = content.replace(/\/\*[\s\S]*?\*\//g, ''); // block comments
  content = content.replace(/\/\/.*/g, ''); // line comments
  content = content.replace(/^\s*[\r\n]/gm, ''); // empty lines
  return {
    name: relativePath,
    content: content
  };
});

console.log(JSON.stringify({
  name: "generate-video",
  entrypoint_path: "index.ts",
  verify_jwt: false,
  files: filesPayload
}));
