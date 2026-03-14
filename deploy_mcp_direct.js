const fs = require('fs');
const payload = JSON.parse(fs.readFileSync('payload.json', 'utf8'));

console.log(`
I need to deploy the function. The payload is ready in payload.json.
I will use the CallMcpTool to deploy it.
`);
