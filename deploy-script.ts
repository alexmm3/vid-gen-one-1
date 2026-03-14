import * as fs from "node:fs";

async function deploy() {
  const filesArray = JSON.parse(fs.readFileSync("files_array.json", "utf-8"));
  
  const payload = {
    function_name: "generate-video",
    files: filesArray,
    verify_jwt: true
  };
  
  fs.writeFileSync("payload.json", JSON.stringify(payload, null, 2));
  console.log("Wrote payload.json");
}

deploy();
