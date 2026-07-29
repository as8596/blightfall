# Fonts

Two, on purpose.

| Resource | Face | Used for |
|---|---|---|
| `ui_font.tres` | Pixel Operator | Body. Anything you read a sentence of. |
| `ui_font_bold.tres` | Pixel Operator Bold | `[b]`, and emphasis in RichTextLabels. |
| `ui_display.tres` | Alagard | Headings, speaker names, item names, the title. |

**Character where it is free, legibility where it is load-bearing.** Alagard has
period feel and middling legibility, which is the right trade for two words at
the top of a panel and the wrong one for a paragraph of item description. Giving
each job its own face lets both be good at it.

## Why the body font changed

`dico` draws `1` as a bare serifed stem with no flag, so `12` reads as `I2` —
everywhere a number starts with one: carry capacity, stack counts, health above
nine.

Found by rendering the real inventory screen in each candidate, same panel, same
copy, same 16px, only the face swapped. Not by looking at specimen sheets, which
is how a font that fails at 16px passes a review.

| Candidate | Verdict |
|---|---|
| **Pixel Operator** (CC0) | Adopted. Unambiguous digits, designed as a UI face, ships a real Bold. |
| Munro (free, Ten by Twenty) | Runner-up. Larger x-height, more character; its slash sits high — `6 ⁄ 6`. |
| Silkscreen | Rejected. Caps only; broke the character panel outright, wrapping "HEALTH" onto its own line and pushing the value out of the frame. |
| Jersey 15 | Rejected. `6` and `8` are near-identical glyphs. Unusable in a UI that is mostly numbers. |
| Pixelify Sans | Rejected. Bare-stem `1` — dico's defect in a milder form. |

## The rules that still apply

**Sizes must be whole multiples of 16.** Both faces have a design grid that
divides evenly at that step (Pixel Operator is 1600 units/em over a 16px design,
Alagard 1024 over the same), so anything off the step lands strokes on half
pixels and the text goes soft. `ui/type_scale.gd` enforces it.

**There is no italic.** No pixel font in the shortlist ships one, and Godot's
synthetic italic shears glyphs off the grid. `[i]` renders as plain text. Weight
and colour are the two axes available; an aside is marked with dimmer colour and
an asterisk (see `ui/game_menu.gd`).

**Import with antialiasing, hinting and subpixel positioning off.** All three
put a font's strokes between pixels, which is the one thing these faces cannot
survive.
