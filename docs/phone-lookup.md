# Looking up your words on the phone

Maldari writes your whole collection to `iCloudDrive\Maldari\export\` and keeps
it current. This is a Shortcut that searches it.

It reads **`vocab.md`**, not the JSON. The JSON is the tidier data, but every
line of the Markdown already contains the Hangul, the reading, the English and
the 해요체 form — so a plain substring search over it finds a word whether you
remember the Korean or the English, with no list-filtering gymnastics.

```
가다 → matches 가다
go  → matches 가다 too
```

---

## The Shortcut — six actions

**1. `Ask for Input`**

- Ask for: **Text**
- Prompt: `Look up`

**2. `Get File`**

Same shape as the Save File action in the capture shortcut: a base folder and
a path.

- Turn **Show Document Picker** **off** (the path fields only appear once it
  is off)
- Base folder: **iCloud Drive → Maldari → export**
- File path: `vocab.md`

> If the action instead offers only a typed path with no folder chip, put
> `Maldari/export/vocab.md` in it — that path is relative to iCloud Drive.

**3. `Get Text from Input`**

Turns the file into text the next action can search.

**4. `Match Text`**

- Text: the output of step 3
- Pattern: `(?i).*` then insert the **Provided Input** variable from step 1,
  then `.*`

So the pattern reads `(?i).*⟨Provided Input⟩.*`. Each matching *line* comes
back as one result.

> **The `(?i)` is not decoration.** Regex matching is case-sensitive by
> default, so without it `wait` finds nothing while `to wait` does — and you
> would conclude the word is missing when it is sitting right there. Korean is
> caseless, so this only ever bites on English searches, which makes it easy
> to miss until it matters.
>
> If your version of the Match Text action shows a **Case Sensitive** toggle
> under its **›**, turning that off does the same thing and you can drop the
> `(?i)`.

**5. `Combine Text`**

- Combine: the matches from step 4
- Separator: **New Lines**

**6. `Show Result`**

Shows the combined text.

Name it **Look up**, add it to the Home Screen.

---

## Using it

Tap **Look up**, type any fragment — `가` , `wait`, `하다` — and you get every
line that contains it:

```
- **기다리다** *(gidarida)* — to wait · 기다려요
- **서성이다** *(seoseongida)* — to pace about · 서성여요
```

Nothing matches? You get an empty result, which means that word is not in your
collection — itself useful before you capture it again.

---

## Notes

- **It works offline.** iCloud keeps a local copy, so the lookup does not need
  a connection — only a recent sync.
- **It is a snapshot.** The file is rewritten a few seconds after the app's
  collection changes, so it is current as of the last time the PC ran Maldari
  and iCloud synced. Words captured on the phone appear here only after the PC
  has imported them.
- **Editing it does nothing.** The file is overwritten on the next export;
  Maldari never reads it back. Change words in the app.
- **Prefer no Shortcut at all?** Open `vocab.md` in the Files app and use its
  search. The Shortcut is faster to reach, nothing more.
