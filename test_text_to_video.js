const apiKey = process.env.GROK_API_KEY;
fetch('https://api.x.ai/v1/videos/generations', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${apiKey}`
  },
  body: JSON.stringify({
    model: 'grok-imagine-video',
    prompt: 'A magical cinematic scene with glowing particles floating in the air. Slow motion.',
    duration: 5,
    aspect_ratio: '9:16',
    resolution: '720p'
  })
})
.then(r => r.json())
.then(async d => {
  console.log("Start response:", d);
  if (!d.request_id) return;
  
  while (true) {
    await new Promise(resolve => setTimeout(resolve, 5000));
    const poll = await fetch(`https://api.x.ai/v1/videos/${d.request_id}`, {
      headers: { 'Authorization': `Bearer ${apiKey}` }
    }).then(r => r.json());
    console.log("Poll status:", poll.status);
    if (poll.status === 'done' || poll.status === 'failed' || poll.status === 'error') {
      console.log("Final result:", poll);
      break;
    }
  }
})
.catch(e => console.error(e));
