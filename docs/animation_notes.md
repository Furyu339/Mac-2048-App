# Animation Notes (current app replication)

- Three-phase animation per move:
  1) Slide (moveDuration ~0.22s, easeInEaseOut)
  2) Merge absorb (mergeDuration ~0.14s)
  3) Merge pop (starts at moveDuration + 0.3*mergeDuration)
- New tile spawn animation: fade-in + scale (0.16s + 0.08s)
- Render layers: grid / static tiles / overlay moving tiles
- At end of (moveDuration + mergeDuration), swap to static board
