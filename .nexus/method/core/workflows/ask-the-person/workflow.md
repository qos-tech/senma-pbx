---
name: ask-the-person
description: 'How a step offers its choices: as a real question the person clicks in Nexus Studio, falling back to the written menu when the engine cannot ask. Read fully whenever a step is about to present a menu.'
---

# Asking the person

**Goal:** turn a step's written menu into a question the person answers by
clicking, without changing which choices the step offers or how they are worded.

---

## The defect this exists to stop

A step printed `Escolha: [A] Elicitação Avançada [P] Party Mode [C] Continuar
para Usuários-alvo (Step 3) [R] Reescrever esta seção`, the person typed `c`,
and the agent then had to admit it had never shown the section the menu was
about. A typed letter carries no context: `c` cannot distinguish "I read it and
I am happy" from "I know what comes next". A clicked choice is bound to the
question it answered, and the question is bound to what was on screen.

So there are two rules here, and the second matters more than the first:

1. Offer the choices through the asking channel the run provides, so they
   arrive as buttons rather than as a letter to type.
2. **Show what you are asking about BEFORE you ask.** Never ask about a section
   you have not just presented.

---

## Rule 1: present, then ask

Before the question, put the thing being decided on screen: the section you just
wrote, the decision you are proposing, the findings you want a verdict on. The
person must be able to answer from what is in front of them, without opening a
file. A question about content that was never shown is the defect above, and
using the tool does not fix it.

## Rule 2: the question goes through the asking tool

Ask with whatever tool this run offers for it, carrying the step's own menu,
transformed like this. Do not name a particular tool here: which one exists is
the app's business and it changes, and a step that hardcodes one asks nothing
the day it is renamed.

- **one option per bracketed choice** in the step's menu, in the step's order;
- **`label` is that choice's text with the bracket letter removed.** `[C]
  Continue to Target Users (Step 3)` becomes the label `Continue to Target Users
  (Step 3)`. Keep the step's wording, translated to the person's language if the
  step's own menu is in it;
- **`description` is what that choice does**, taken from the step's own
  explanation of the menu. One or two sentences, saying what happens and what it
  costs;
- **`question`** names what is being decided, about the thing you just showed;
- **`header`** is two or three words, a label for the question, not a sentence;
- **`multiSelect`** is `false` unless the step really accepts several answers.

**Never use a bare letter as a label.** The app sends the label text back
verbatim as the answer, so a label of `C` reproduces exactly the defect this
file exists to stop: an answer with no context in it.

### The shape, exactly as the app reads it

```json
{
  "questions": [
    {
      "question": "The Executive Summary above is written. What next?",
      "header": "Next step",
      "multiSelect": false,
      "options": [
        {
          "label": "Continue to Target Users (Step 3)",
          "description": "Saves this section as written and moves on. Nothing here is revisited."
        },
        {
          "label": "Advanced Elicitation",
          "description": "Runs the elicitation protocol over this section, then comes back to this same question."
        },
        {
          "label": "Rewrite this section",
          "description": "Throws away the text above and writes it again from your feedback."
        }
      ]
    }
  ]
}
```

## Rule 3: the written menu stays, and is the fallback

The written menu remains necessary when a run's asking channel is unavailable,
or when no window is watching it. A step that only called the channel would
otherwise leave no answerable question behind.

The app tells you at the start of the run what it offers for asking, and how to
call it. Read what it said and use that; do not go looking for a tool by name,
and do not assume the one you used last time still exists.

So the step keeps its written menu, and behaves like this:

- **When the run offers a way to ask:** show the section, print the menu, then
  ask. The person clicks, and their answer comes back to you.
- **When no such tool is available:** show the section, print the menu, and say
  in one line that this RUN is non-interactive, so the answer comes as a typed
  letter. Never say the engine cannot ask: the engine can, and it is the mode
  this turn runs in that cannot. Then wait for the letter.

Never delete the written menu to "clean up". It is what the fallback reads.

## Rule 4: accept the answer in either form

The click sends back the **label text**, not the letter. The letter arrives only
from the fallback. So a step's menu handling must match **either**: treat
`Continue to Target Users (Step 3)` and `C` as the same answer. Match the label
first, then the letter, then the person's own words, which the app also allows.
