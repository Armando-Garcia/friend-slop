# Groq VCR cassettes

Replay offline with:

```bash
make discord-groq-vcr
```

Record or refresh (uses your local `GROQ_API_KEY`, never committed).
The cassette captures **two** HTTP calls: titles, then article.

```powershell
$env:GROQ_API_KEY = "gsk_..."
$env:DISCORD_VCR_RECORD = "1"
python tools/test_discord_groq_vcr.py
```

The cassette redacts the `Authorization` header. Commit the `.yaml` so CI and other
devs can replay without a Groq key.
