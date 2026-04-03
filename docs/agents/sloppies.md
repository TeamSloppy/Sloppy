---
layout: doc
title: Sloppies
---

# Sloppies

Every agent in Sloppy has a Sloppie — a pixel-art companion that is procedurally generated from the agent's identity and grows as the agent does work. A Sloppie is not cosmetic: its five stats reflect how the agent has actually been used over time.

## How it works

When an agent is first created, Sloppy generates a random 64-bit **genome** and uses it as a deterministic seed to assemble the Sloppie's appearance and base stats. The same genome always produces the same Sloppie, so the character is stable across restarts.

As the agent interacts — in direct chats, linked channels, heartbeats, and automated runs — each event contributes small increments to the Sloppie's stats. Stats are capped per-channel and globally per day to prevent fast accumulation from a single burst of activity.

```
Genome (64-bit seed)
        │
        ▼
  Weighted random draw
        │
        ├─ Head part + rarity
        ├─ Body part + rarity
        ├─ Legs part + rarity
        ├─ Face part + rarity
        └─ Accessory part + rarity
                │
                ▼
         Base stats (18–36 per stat)
         + rarity bonuses
         + part-specific bonuses
```

## Parts and rarity

A Sloppie is assembled from five independently drawn parts. Each part belongs to a rarity tier that influences both the Sloppie's overall rarity and its base stat floor.

| Part | What it is | Slot |
|---|---|---|
| **Head** | The character's head shape | Top of the sprite |
| **Body** | The torso design | Middle of the sprite |
| **Legs** | The locomotion type | Bottom of the sprite |
| **Face** | The facial expression overlay | Rendered over the head |
| **Accessory** | A decorative body overlay | Rendered over the body |

### Rarity tiers

| Tier | Colour in Dashboard | Stat bonus |
|---|---|---|
| Common | Gray | +0 |
| Uncommon | Green | +2 per part |
| Rare | Cyan | +5 per part |
| Legendary | Gold | +9 per part |

The Sloppie's **overall rarity** is derived from its parts:

- Any legendary part → **Legendary**
- Two or more rare parts → **Legendary**
- One rare part, or three or more uncommon parts → **Rare**
- Any uncommon part → **Uncommon**
- All common → **Common**

### Available parts

**Heads** — bubble · cube · shell · fork · visor · probe · oracle · crown

**Bodies** — core · puff · brick · terminal · satchel · relay · reactor · throne

**Legs** — stub · bouncer · track · sprinter · spider · piston · hover · singularity

**Faces** — default · mono · scan · grin · frown · x · star · halo

**Accessories** — none · scarf · badge · cape · chain · stripe · wings · bolt

## Stats

A Sloppie has five stats, each tracked independently from 0 to 100. Base values are generated from the genome (18–36 range) and shifted upward by rarity bonuses and part-specific bonuses.

| Stat | What grows it |
|---|---|
| **Wisdom** | Long user messages, successful tool calls, completed runs, oracle/crown head |
| **Debugging** | Tool calls and results, terminal/reactor body, stripe/badge accessory |
| **Patience** | Longer messages, completed runs, puff/throne body, grin/halo face |
| **Snark** | Snarky message content (`???`, `wtf`, `obviously`…), visor head, spider legs, cape/chain accessory |
| **Chaos** | Chaotic messages (`!!!`, `urgent`, `panic`…), tool failures, interrupted runs, hover/singularity legs, wings/bolt accessory |

Stats never decrease. They converge upward toward 100 as the agent gains experience.

## Stat growth

Each interaction type contributes a specific delta:

| Event | Effect |
|---|---|
| Short user message (< 16 chars) | Tiny wisdom gain (scaled ×0.35) |
| Medium message (16–48 chars) | +1 wisdom |
| Long message (48–120 chars) | +2 wisdom, +1 patience |
| Very long message (120+ chars) | +3 wisdom, +2 patience |
| Technical message content | +1–2 debugging |
| Snarky message content | +2 snark |
| Chaotic message content | +1 chaos |
| Tool call | +2 debugging |
| Tool success | +2 debugging, +1 wisdom |
| Tool failure | +1 debugging, +1–2 chaos |
| Run completed | +2 wisdom, +2 patience |
| Run failed | +1 debugging, +1–2 chaos |
| Run interrupted | +1 snark, +1–2 chaos |

Events from heartbeats and cron sources are weighted at 35% of their normal value. Direct chat and external channel events are weighted at 100%.

### Daily caps

Sloppy limits how much a Sloppie can grow in a single day to prevent gaming through bulk activity.

| Cap | Wisdom | Debugging | Patience | Snark | Chaos |
|---|---|---|---|---|---|
| Per channel | 14 | 16 | 12 | 10 | 12 |
| Global (all channels combined) | 32 | 36 | 28 | 24 | 28 |

## Viewing your Sloppie

The Sloppie lives on the **Overview** tab of each agent in the Dashboard. The card shows:

- The animated pixel-art sprite
- The genome hash and pet ID
- All five active parts (head, body, legs, face if non-default, accessory if present)
- The five stat bars with current and base values overlaid

::: tip
The base stat marker (gold vertical line) shows where the stat started. Anything to the right of it is growth from real interactions.
:::

## Related

- [Runtime](/agents/runtime) — how interactions are processed and what events look like internally
- [Channels](/channels/about) — how external channel messages count toward stat growth
