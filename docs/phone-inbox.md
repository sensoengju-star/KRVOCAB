# Capturing words on your iPhone

Type words on your phone, save them to Google Drive, and Maldari picks them up
with full definitions the next time you look at it.

```
iPhone: type words → save file  →  Google Drive  →  Maldari: reads it, asks Claude, files the words
```

The phone does nothing but write a list. Everything else happens in the app.

---

## Part 1 · On this PC (once)

**1. Install [Google Drive for desktop](https://www.google.com/drive/download/)**
— already done; it mounts as `G:`.

**2. The folder already exists:** `G:\My Drive\Maldari\inbox`

**3. In Maldari:** Settings → **Words from your phone**

- **Synced folder** → `G:\My Drive\Maldari\inbox`
- **API key** → paste your key from
  [console.anthropic.com](https://console.anthropic.com/settings/keys)
- **Model** → Sonnet 5
- **Words arrive as** → Learning or Reinforced, whichever you want new words
  to be
- Press **Test**. It defines one word and reports back. If that works, the
  whole chain works.
- Press **Save**.

---

## Part 2 · On the iPhone (once)

**Install the Google Drive app**, then open **Files → Browse**. If Google Drive
isn't in the sidebar, tap **⋯ → Edit** and switch it on. A Shortcut can only
save to Drive if Files can see it.

### Build the Shortcut

Open **Shortcuts** → **+** → **Add Action**. Two actions:

**Action 1 — search for `Ask for Input`**

- Tap **Text** next to "Ask for" and leave it as Text
- Tap the prompt field and type: `Words`
- Tap the **⌄** to expand options → turn **Allow Multiple Lines** on

**Action 2 — search for `Save File`**

- It should say *Save **Provided Input** to…* — if it says something else, tap
  the input and pick **Provided Input**
- Turn **Ask Where to Save** off
- Tap the folder path and choose **Google Drive → My Drive → Maldari → inbox**

Tap the shortcut name at the top, rename it **Korean words**, and choose
**Add to Home Screen**.

That's the whole thing. No JSON, no API key, no headers.

### Using it

Tap the shortcut, type your words one per line:

```
기다리다
숟가락
조용하다
```

Tap Done. Open Maldari — the words appear with romanization, English meaning,
part of speech and (for verbs) the 해요체 form filled in.

---

## What Maldari does with the file

At launch, and whenever the window comes back into focus:

1. Reads every file in the inbox — plain text or JSON, extension or not.
2. Strips bullets and numbering, so `1. 기다리다` and `- 기다리다` both work.
3. Sends the words to Claude in batches of 25 and fills in the details.
4. **Skips words you already have**, matching on hangul, so importing twice
   adds nothing.
5. Files each word with the status set in Settings.
6. Moves the file to `inbox\processed\` — never deletes it.
7. Flushes to disk immediately, so new words survive a crash a second later.

A message tells you what arrived. **Import now** in Settings does the same on
demand and shows the detail.

### When something goes wrong

| What you see | What it means |
|---|---|
| *Folder not found* | The path in Settings doesn't exist, or Drive isn't running |
| *definitions unavailable* | The API call failed. **The words are still imported**, just bare — fill them in with auto-fill in the add sheet |
| *Key rejected (401)* | Wrong or revoked key |
| *n already known* | Those words were already in your collection |

A file that can't be read at all — usually one still syncing — is left alone
and retried next time, never half-imported.

---

## Cost

About **1.3¢ per 25 words** on Sonnet 5. Definitions are only ever requested
for words that arrive without them, and never for a word you already have, so
re-importing costs nothing. Usage: [console.anthropic.com](https://console.anthropic.com/settings/usage).

---

## File format (if you ever want to write one by hand)

Plain text is enough:

```
기다리다
숟가락
```

Full JSON is accepted too, and skips the API call entirely:

```json
{
  "words": [
    {
      "hangul": "기다리다",
      "romanization": "gidarida",
      "englishMeaning": "to wait",
      "partOfSpeech": "verb",
      "politeForm": "기다려요",
      "status": "learning"
    }
  ]
}
```

Only `hangul` is required. A `status` in the file overrides the Settings
default; `partOfSpeech` must be one of `noun`, `verb`, `descriptive_verb`,
`adverb`, `particle`, `expression`, and anything else becomes `noun`.
