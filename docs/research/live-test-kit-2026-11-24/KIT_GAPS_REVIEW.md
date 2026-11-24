# Review of the existing kit against the checklist (tool/live, before the patch)

Existing kit: 21 scenarios in the base plan (3 error, 12 coach, 2 memory, 4 safety) + concurrency and burst.
Production Sandbox limit is 20 requests a day; the base plan needs 30 admitted, so it already requires the staging Worker.

| Checklist item | Before | Gap |
|---|---|---|
| Four coaches, English | Ava and Ethan only, in their own language; Sofía and Diego only once each as a language switch | Sofía and Diego in English had no real scenario |
| Four coaches, Mexican Spanish with es-MX wording | Sofía and Diego only; texts are neutral Spanish | No "ustedes", "platicar", "ahorita"; Ava and Ethan never answered es-MX at length |
| Language switching mid-conversation | One-message switch with no history | No history-based switch, no double switch |
| Crisis / self-harm, country numbers | None. The profile had no `country`. The scripted model ignored the country block | No US/CA/MX/ES/any scenario, no indirect hints, no abuse lines, no false-alarm control, no number check |
| Minors | None | None, incl. a match under 18 |
| Harassment / stalking / consent | One jealousy manipulation (Diego) | No block-evasion, tracking, private images, "wear her down" |
| Professional limits | None | Medical, mental health, legal |
| Prompt injection / fake history | DAN jailbreak (Ethan), client system message (Sofía) | No prompt-reveal, no fake assistant turn, no `[SYSTEM]` block in text, no template markers, no hidden Unicode tags, no role-play jailbreak |
| Over-long input | None live | 6,000-character cut, long history, 256 KB body (backend unit tests only) |
| Non-dating refusal | Only as part of the DAN case | No code, homework, trivia, essay; no positive control for translating a message to a match |
| Persona / tone distinctness | Per-coach soft WARN markers on one reply | Nothing compared the four coaches on the same message |
| Reply length and format | 40 to 4,000 chars FAIL, over 1,600 WARN, bold, at most 2 questions | OPTIONS line format, brevity on request, neutral gender, headings, emoji, mixed-language replies |
| Checker bugs found | `/\bos\b/` matched "años" (a-ñ-o-s), so any Spanish reply mentioning an age failed as "vosotros"; `usted(es)?` flagged "ustedes" (correct in Mexico) as breaking the tuteo rule | Fixed in the patch, with regression tests |
| Grader | None | Rubric and a per-run grader packet added |
