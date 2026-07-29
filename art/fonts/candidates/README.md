# Font candidates

Not in use. These are the two survivors of a legibility comparison run against
the real inventory screen — same panel, same copy, same 16px, only the font
swapped. Kept in the repo so the decision can be re-examined without
re-downloading anything.

## Why we were looking

**The shipping font renders `12` as `I2`.** `dico`'s `1` is a bare serifed stem
with no flag, so it reads as a capital I. That shows up anywhere a number starts
with 1 — carry capacity, stack counts, health above 9 — and it is a defect
rather than a taste question.

## The two left standing

| File | Licence | Notes |
|---|---|---|
| `PixelOperator.ttf` + `-Bold` | CC0 (public domain) | Jayvee Enaguas. Unambiguous digits, designed as a UI face. Ships a real Bold, which is the closest a pixel font gets to an italic. |
| `Munro.ttf` | Free, Ten by Twenty (Ed Merritt) | Larger x-height so it reads bigger at the same size, more character. Its slash sits high — `6 ⁄ 6` — which is either invisible to you or permanent. |

## Rejected, and why

- **Silkscreen** — caps only. Broke the character panel outright: "HEALTH"
  wrapped to its own line and pushed the value out of the frame.
- **Jersey 15** — its `6` and `8` are near-identical glyphs. `6 / 6` renders as
  something you read as `8 / 8`. Unusable in a UI that is mostly numbers.
- **Pixelify Sans** — clean, but its `1` is a bare stem, so it has `dico`'s
  problem in a milder form.

## If one is adopted

It is not a drop-in. `ui_font.tres` points at `dico` with `alagard` as a
*fallback*, which is a glyph-coverage mechanism rather than a design one —
alagard only appears for characters dico lacks. The intended end state is two
fonts chosen on purpose: a workhorse for prose and Alagard for headings and
names. `ui/type_scale.gd` and the tests that assert the 16-unit grid would need
retuning to whatever the new face's design size is.
