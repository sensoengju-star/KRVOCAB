# Capturing words on your iPhone

Note a word on the phone, let Claude write the definition, and have Maldari
pick it up the next time you open it.

```
iPhone Shortcut  →  Claude (definitions)  →  JSON file in Google Drive  →  Maldari imports it
```

Maldari never talks to a cloud service. Google Drive for desktop puts the file
on this PC, and the app just reads a folder. No account, no OAuth, no API key
on the desktop — the key lives only in the Shortcut on your phone.

---

## 1 · One-time setup

**On this PC** — install [Google Drive for desktop](https://www.google.com/drive/download/).
It mounts as `G:` by default. Create the folder:

```
G:\My Drive\Maldari\inbox
```

**On the iPhone** — install the Google Drive app (it registers Drive with the
Files app, which is what lets a Shortcut save there).

**An API key** — from [console.anthropic.com](https://console.anthropic.com/settings/keys).
A batch of 25 words on Sonnet 5 costs about **1.3¢** (~500 input tokens at
$2/Mtok, ~1,200 output at $10/Mtok), so existing credit goes a long way.

**In Maldari** — Settings → *Words from your phone* → set the folder to
`G:\My Drive\Maldari\inbox` and press **Save path**.

---

## 2 · The Shortcut

Five actions. Build it in the Shortcuts app, then add it to your Home Screen
or the Action Button.

### 1. Ask for Input

- Input Type: **Text**
- Prompt: `Words (one per line)`
- Allow Multiple Lines: **on**

### 2. Choose from Menu

Two items: **Learning** and **Reinforced**. In each branch put a *Text* action
containing `learning` or `reinforcement`, then *Set Variable* → `status`.

### 3. Text

The request body. Paste it exactly, inserting the two variables as variable
tokens where marked — don't type them literally.

```json
{
  "model": "claude-sonnet-5",
  "max_tokens": 16000,
  "thinking": { "type": "disabled" },
  "system": "You are a Korean dictionary for a TOPIK I-II learner. For each word given, return the dictionary form in Hangul, its revised-romanization reading, a short English meaning, and the part of speech. For verbs and descriptive verbs only, also give the present polite 해요체 form; leave politeForm as an empty string for everything else. Set status on every word to the STATUS value the user gives.",
  "messages": [
    { "role": "user", "content": "STATUS: [status]\n\nWORDS:\n[Provided Input]" }
  ],
  "output_config": {
    "format": {
      "type": "json_schema",
      "schema": {
        "type": "object",
        "properties": {
          "words": {
            "type": "array",
            "items": {
              "type": "object",
              "properties": {
                "hangul":         { "type": "string" },
                "romanization":   { "type": "string" },
                "englishMeaning": { "type": "string" },
                "partOfSpeech":   { "type": "string",
                                    "enum": ["noun","verb","descriptive_verb",
                                             "adverb","particle","expression"] },
                "politeForm":     { "type": "string" },
                "status":         { "type": "string",
                                    "enum": ["learning","reinforcement"] }
              },
              "required": ["hangul","romanization","englishMeaning",
                           "partOfSpeech","politeForm","status"],
              "additionalProperties": false
            }
          }
        },
        "required": ["words"],
        "additionalProperties": false
      }
    }
  }
}
```

`[status]` is the variable from step 2; `[Provided Input]` is the text from
step 1.

Three things are doing real work here:

- **`output_config.format`** constrains Claude to exactly these fields with a
  valid `partOfSpeech`. There is no prose to strip and no parsing to get wrong.
- **`status` is in the schema**, so Claude stamps your menu choice onto every
  word. That removes the repeat-loop the Shortcut would otherwise need.
- **`thinking: disabled`** means the response is a single text block, which
  keeps step 5 trivial. This is a dictionary lookup; there is nothing to reason
  about, and thinking tokens bill as output.

### 4. Get Contents of URL

- URL: `https://api.anthropic.com/v1/messages`
- Method: **POST**
- Headers:
  - `x-api-key` → your key
  - `anthropic-version` → `2023-06-01`
  - `Content-Type` → `application/json`
- Request Body: **File** → the Text from step 3

### 5. Save File

Between the request and the save, pull the JSON out of the response:

- *Get Dictionary Value* → **Value** for key `content.text`
- *Get Item from List* → **First Item**

The response body is `{"content": [{"type": "text", "text": "…"}], …}`. With
thinking disabled there is exactly one block, and structured outputs guarantee
its text is the JSON.

Then:

- *Save File* → Destination **Google Drive → Maldari → inbox**
- Filename: a *Current Date* action formatted `yyyy-MM-dd-HHmmss`, plus `.json`
- Ask Where to Save: **off**

---

## 3 · What Maldari does with it

At launch — and whenever the window comes back into focus — the app reads
every `*.json` in the inbox folder and:

- **skips words you already have**, matching on hangul the same way the merge
  tool does, so importing twice adds nothing;
- **files each word** with the status from the phone;
- **moves the file** to `inbox\processed\`, never deleting it;
- **flushes to disk immediately**, so new words survive a crash a second later;
- **leaves a file alone** if it doesn't parse — usually one still syncing — and
  tries again next time.

A snackbar reports what arrived. Settings → *Words from your phone* →
**Import now** does the same on demand and shows the detail, including why any
file was skipped.

---

## 4 · If the API is unreachable

Give the Shortcut an *Otherwise* branch on step 4 that saves just the words:

```json
{ "words": [{ "hangul": "기다리다", "status": "learning" }] }
```

Maldari accepts that — `romanization`, `englishMeaning` and `politeForm` are
all optional. Fill them in later with the local model from the add sheet's
auto-fill. Capture never depends on the network.

---

## File format

The app accepts either `{"words": [...]}` (what the schema above produces) or a
bare array:

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

Only `hangul` is required. `status` is `learning` or `reinforcement`
(`reinforced` is accepted too); anything else, including a missing field,
becomes `learning`. An unrecognised `partOfSpeech` becomes `noun`.

---

## Notes

- **Model:** `claude-sonnet-5`. Use that exact string — no date suffix.
- **Cost:** roughly 1.3¢ per 25 words. Check spend at
  [console.anthropic.com](https://console.anthropic.com/settings/usage).
- **The key never leaves your phone.** Maldari has no network code for this
  feature and nothing to store, so none of it can leak through this repo.
