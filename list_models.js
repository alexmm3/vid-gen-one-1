const apiKey = process.env.GEMINI_API_KEY;
fetch(`https://generativelanguage.googleapis.com/v1beta/models?key=${apiKey}`)
  .then(r => r.json())
  .then(d => {
    const models = d.models.map(m => m.name);
    console.log(models.join('\n'));
  });
