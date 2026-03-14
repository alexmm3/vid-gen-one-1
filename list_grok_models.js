const apiKey = process.env.GROK_API_KEY;
fetch('https://api.x.ai/v1/models', {
  headers: { Authorization: `Bearer ${apiKey}` }
})
.then(r => r.json())
.then(d => {
  if (d.data) {
    console.log(d.data.map(m => m.id).join('\n'));
  } else {
    console.log("Response:", JSON.stringify(d, null, 2));
  }
})
.catch(e => console.error(e));
