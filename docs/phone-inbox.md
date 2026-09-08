# Capturing words on your iPhone

Type words on your phone, save them to iCloud Drive, and Maldari picks them up
with full definitions the next time you look at it.

```
iPhone: type words → save file  →  iCloud Drive  →  Maldari: reads it, asks Claude, files the words
```

> **Why iCloud and not Google Drive?** An iOS limitation, not a preference.
> Since iOS 15 the Save File action can only write to a typed path in iCloud
> Drive or on the device itself. Any other service — Google Drive included —
> forces the shortcut to open a file picker on **every** capture. iCloud is
> the only destination a shortcut can write to unattended.

The phone does nothing but write a list. Everything else happens in the app.

---

## Part 1 · On this PC (once)

**1. Install [iCloud for Windows](https://apps.microsoft.com/detail/9PKTQ5699M62)**,
sign in, and switch **iCloud Drive** on in its settings.

**2. Create the folder** `Maldari` inside your iCloud Drive folder (typically
`C:\Users\<you>\iCloudDrive`) and put any file in it — a README will do.

Both parts matter. The folder must exist before the phone writes to it, and an
**empty folder does not reliably sync through iCloud**: it simply never shows
up in the Shortcut's folder picker on the phone. One file in it is enough to
make it appear.

Keep it flat, too. A nested `Maldari\inbox` is tidier but gives iCloud a second
empty folder to lose.

**3. In Maldari:** Settings → **Words from your phone**

- **Synced folder** → your `…\iCloudDrive\Maldari` path
- **API key** → paste your key from
  [console.anthropic.com](https://console.anthropic.com/settings/keys)
- **Model** → Sonnet 5
- **Words arrive as** → Learning or Reinforced, whichever you want new words
  to be
- Press **Test**. It sends one deliberately misspelled word and reports the
  correction back, which proves the key, the model and the typo-fixing at
  once. If that works, the whole chain works.
- Press **Save**.

---

## Part 2 · On the iPhone (once)

### Build the Shortcut

Open **Shortcuts** → **+** → **Add Action**. Two actions.

> **Add them in this order.** Shortcuts only offers a variable to actions
> *below* the one that produces it. Add Save File first and there is no
> "Provided Input" to choose — which looks exactly like the feature is
> missing. If you already added Save File, tap the **✕** on it and start with
> Ask for Input.

**Action 1 — search for `Ask for Input`**

- Tap **Text** next to "Ask for" and leave it as Text
- Tap the prompt field and type: `Words (numbered)`
- Tap the action's **›** to expand it → turn **Allow Multiple Lines** on

**Action 2 — search for `Save File`**

The action arrives as *Save **File*** — a pale blue **File** placeholder, and
a **›** in a blue circle. Both matter:

- **Tap the pale blue `File`** and pick the variable for the text you just
  typed. Depending on the iOS version it is listed as **Ask for Input** (the
  name of the action that produced it) or as **Provided Input** — same thing.
  The line should end up reading *Save **Ask for Input***. If the list offers
  neither, this action is above Ask for Input; see the order note.
- **Tap the `›`** to expand the rest of the action; the settings are collapsed
  behind it, not missing. Then:
  - turn **Ask Where To Save** **off**. Two fields appear: a **base folder**
    (shown in blue after "to", defaulting to `Shortcuts`) and a **Subpath**.
  - tap the blue base folder and browse to **iCloud Drive → Maldari**. The
    picker only offers folders — you cannot select the iCloud Drive root — so
    the destination folder has to be picked here rather than typed.
  - leave **Subpath** empty. It is relative to the base folder, so a path here
    would nest another copy inside it.
  - leave **Overwrite If File Exists** **off**, so capturing twice before you
    open Maldari appends a numbered file instead of replacing the first.

Tap the shortcut's name at the top — it will have auto-named itself after one
of the actions — rename it **Korean words**, and choose **Add to Home Screen**.

### Optional: a second shortcut for Reinforced

Where a file is decides which pile its words join, so a second shortcut lets
you choose at capture time instead of relying on a setting:

- `Maldari/` → the **Words arrive as** setting decides
- `Maldari/reinforced/` → always Reinforced
- `Maldari/learning/` → always Learning

Both subfolders are created for you when you press Save in Settings.

In Shortcuts, long-press **Korean words** → **Duplicate**, rename the copy
**Korean words (reinforce)**, and change one field: the base folder, from
`Maldari` to `Maldari → reinforced`. Add it to the Home Screen too.

Choosing the pile is then which icon you tap — nothing to set, nothing to
remember, and no race with the setting.

That's the whole thing. No JSON, no API key, no headers.

### Using it

Tap the shortcut and type your words as a **numbered list**, one per line:

```
1. 기다리다
2. 숟가락
3. 조용하다
```

`1.`, `2)`, `3]` and `4 가다` all count; the marker is stripped and the rest of
the line is the word.

> **Only numbered lines are imported.** A line without a number is skipped and
> reported, never guessed at. A captured file is just whatever was in a text
> field on a phone, and without a marker there is no way to tell a vocabulary
> word from a stray line, an autocorrect artefact or a note to self. Numbering
> is cheap to type and unambiguous to read.
>
> If a file has unnumbered lines, the import report names them — *ignored 2
> unnumbered lines (…) — number every line* — so nothing disappears quietly.

Tap Done. Open Maldari — the words appear with romanization, English meaning,
part of speech and (for verbs) the 해요체 form filled in.

**Typos are fixed on the way in.** The words are read as something typed
quickly on a phone, so a wrong or missing jamo is corrected to the nearest real
word, and a conjugated form is converted to its dictionary form — type 갔어요
and you get 가다. Every change is listed in the import report as
`typed → kept`, so you can see what it decided rather than having to trust it.

Correction happens *before* the duplicate check, which is the point: a typo of
a word you already have is recognised as that word instead of being added
beside it.

---

## What Maldari does with the file

At launch, and whenever the window comes back into focus:

1. Reads every file in the inbox — plain text or JSON, extension or not.
2. Takes the numbered lines and strips the numbering. Unnumbered lines are
   skipped and reported.
3. Sends the words to Claude in batches of 25, which corrects typos and fills
   in the details. Corrections are reported, never silent.
4. **Skips words you already have**, matching on hangul, so importing twice
   adds nothing.
5. Files each word by where it came from: the `reinforced` or `learning`
   subfolder if it was saved there, otherwise the status set in Settings.
6. Moves the file to a `processed\` subfolder — never deletes it.
7. Flushes to disk immediately, so new words survive a crash a second later.

A message tells you what arrived. **Import now** in Settings does the same on
demand and shows the detail.

### When something goes wrong

| What you see | What it means |
|---|---|
| *Folder not found* | The path in Settings doesn't exist, or iCloud for Windows isn't running |
| *definitions unavailable* | The API call failed. **The words are still imported**, just bare — fill them in with auto-fill in the add sheet |
| *Key rejected (401)* | Wrong or revoked key |
| *n already known* | Those words were already in your collection |
| Words in the wrong pile | A file saved straight into `Maldari` takes the Settings status *at import time*. Save to the `reinforced` subfolder to decide at capture time instead |
| *ignored n unnumbered lines* | Those lines had no number, so they were not imported. Number every line and capture again |
| Nothing arrives at all | Save File is saving the wrong thing — its input must be **Provided Input**, which only exists if Ask for Input is *above* it |

A file that can't be read at all — usually one still syncing — is left alone
and retried next time, never half-imported.

---

## Cost

About **1.3¢ per 25 words** on Sonnet 5. Definitions are only ever requested
for words that arrive without them, and never for a word you already have, so
re-importing costs nothing. Usage: [console.anthropic.com](https://console.anthropic.com/settings/usage).

---

## File format (if you ever want to write one by hand)

A numbered list is enough:

```
1. 기다리다
2. 숟가락
```

Full JSON is accepted too — it skips both the numbering rule and the API
call, since it already carries everything:

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

Only `hangul` is required. Status precedence is **folder, then file, then
setting**: a file in `reinforced/` wins over a `status` inside it, which in
turn wins over the Settings default. `partOfSpeech` must be one of `noun`, `verb`, `descriptive_verb`,
`adverb`, `particle`, `expression`, and anything else becomes `noun`.
