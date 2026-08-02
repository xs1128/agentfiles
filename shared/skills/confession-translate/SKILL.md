---
name: confession-translate
description: Translate anonymous posts for the National Tsing Hua University (NTHU) 匿名牆 (anonymous wall) — mainly school gossip and school-related discussions, occasionally confessions. Auto-detects input language and routes — English → Taiwanese Mandarin, Taiwanese Mandarin → English, Japanese → both Taiwanese Mandarin and English, mixed/other → auto-detect and output both. Preserves anonymous-wall register (Dcard / 匿名牆 / 靠北牆 tone). Triggers on "/confession-translate", "translate this confession", "translate this post", "匿名牆翻譯", "翻譯告白", "靠北翻譯".
---

# Confession Translate — NTHU 匿名牆 (Anonymous Wall)

Translate a post for NTHU's 匿名牆. Content is mainly school gossip and school-related discussion (courses, professors, dorms, campus events, department drama), occasionally crush confessions. Not literal translation — the output must read like something a Taiwanese university student would actually post.

## Routing (detect first, then translate)

Detect the dominant language of the input, then:

| Input language | Output |
|---|---|
| English | Taiwanese Mandarin (Traditional Chinese) |
| Mandarin (any variety) | English |
| Japanese | BOTH Taiwanese Mandarin AND English |
| Other (Korean, Taiwanese Hokkien, etc.) | BOTH Taiwanese Mandarin AND English |
| Mixed languages | Detect per-segment; translate each segment per the rules above, keep segments in original order. If ambiguous, output both Taiwanese Mandarin and English versions of the whole post |

Always state the detected language(s) in one line before the translation.

## Taiwanese Mandarin style rules (critical)

Output must be **Taiwan Mandarin, Traditional characters** — not Mainland Mandarin, not textbook Chinese:

- Register: Dcard / 匿名牆 / 靠北牆 tone. Casual, first-person. Gossip posts often 酸 (sarcastic) or 吃瓜 (spectating drama); discussion posts more neutral but still colloquial; crush posts 曖昧.
- Use Taiwan-native particles and fillers where the source tone calls for them: 啦、欸、耶、喔、好嗎、拜託、真的、有夠.
- **V+一下, never V+下**: 看一下場合 ✓, 看下場合 ✗ (that's Cantonese/Mainland-southern grammar).
- Taiwan lexicon over Mainland: 影片 not 视频, 網路 not 网络, 沒關係 not 没事儿. No 儿化.
- Slang/idiom mapping, not word-for-word. Examples:
  - "read the room" → 看一下場合 / 識相一點 / 搞清楚狀況 (NOT 讀空氣 unless the post is deliberately referencing Japanese net culture)
  - clueless person → 狀況外 / 白目 (白目 only if the post is already a rant — it's harsh)
  - 空気読め / 空気嫁 → 看一下場合好嗎 (+ note the 嫁 pun if translating to English: "read the room")
- Anonymous-post conventions: gossip/callout posts refer to targets as 那位同學 / 某系某人 / 某教授 (never real names — keep whatever anonymization the source uses); crush posts address the target as 你 directly. Preserve whichever the source implies.
- Campus vocabulary in Taiwan terms: 加簽 (add-code/override), 停修 (course withdrawal), 學餐, 宿舍/齋 (NTHU dorms are 齋, e.g. 清齋、鴻齋), 系上, 通識, 期中/期末.

## English style rules

- Natural campus/net register, not formal. Match the source's energy (thirsty, salty, wistful, meme-y).
- Keep culture-specific items with a short gloss in parentheses when needed: 加簽 (course add/drop override), 宵夜 (late-night food run), 學餐 (campus cafeteria).
- Don't flatten sarcasm or hedging — confession posts live on tone.

## Punctuation

- **No em-dashes (—) in the translation output**, unless the original input text itself contains one. Rephrase with commas, periods, or parentheses instead. (Em-dashes read as AI-generated on the wall.)

## Japanese input specifics

- Japanese net slang needs decoding before translating (空気嫁 = 空気読め = read the room; 乙 = otsukare; 草 = lol). Translate the meaning, then footnote the wordplay in one line if it's a pun.
- Output order: Taiwanese Mandarin version first, then English version, then (optional, one line) any pun/culture note.

## Output format

```
偵測語言 / Detected: <language(s)>

<translation(s), labeled 中 / EN when both are produced>

(optional) 註 / Note: <one-line pun or culture note>
```

Keep it copy-paste ready — the user submits the translation directly to the confession page. No commentary beyond the optional note. If a line is genuinely ambiguous (e.g., could be crush or callout), give both readings inline as `A / B` rather than asking.
