# OpenSOP C2 comparison video

A reproducible ~55-second terminal recording showing "skill-only vs openSOP" on the same
task — extracting action items from meeting notes — ending on verified metrics.

## What the video shows

Three arms of a controlled benchmark, all using Claude Haiku, all on the same meeting-notes
fixture (`../fixtures/meeting-notes.txt`), the same extraction task:

| Act | Arm | What happens |
|---|---|---|
| 1 | skill | Naive prompt. 3 replayed runs show 6, 8, 7 items — different each time. Phantom items highlighted in red. |
| 2 | openSOP | `opensop run extract-action-items.sop.json`. 3 replayed runs return byte-identical JSON — exactly the 3 real items. |
| 3 | Scoreboard | Verified metrics table from the 60-run benchmark. |

## Honesty label

The outputs replayed in the video are **recorded from real measured runs**, not invented.
Full methodology and aggregated per-run data: `../NUMBERS.md`.

The numbers shown (skill 0/10 vs openSOP 10/10, recall 3/3 all arms, ~69 vs ~174-386
output tokens, 1.56 s vs 2.69 s median) come from the shipped `opensop bench` command
(see `cli/bench/`). The raw per-run JSONL (`results/bulletproof-3arm.jsonl`, 60 runs:
3 arms × 2 models × 10) lives on the `spike/c0-bench` branch and is the original
measurement source; NUMBERS.md contains the complete aggregated writeup.

The phantom items shown (Alice staging P1, Bob data-grid ticket, Alice/Carol batch-import
follow-ups) are the actual scope-creep items the model promoted from informal commitments
in the notes to "action items" — a different selection each run, as recorded.

The openSOP JSON shown is the exact output produced by every one of the 10 haiku+opensop
runs — byte-identical, as verified by the benchmark scorer.

## Re-rendering

Requires: `asciinema` (python), `agg` (from github.com/asciinema/agg), `ffmpeg`.

```sh
# From this directory:
make demo

# Or step by step:
asciinema rec --overwrite --cols 100 --rows 32 \
  -c "bash demo.sh" comparison.cast

~/.cargo/bin/agg \
  --cols 100 --rows 32 \
  --font-size 16 \
  --speed 0.5 \
  comparison.cast comparison.gif

ffmpeg -y -i comparison.gif \
  -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" \
  -c:v libx264 -pix_fmt yuv420p -movflags +faststart \
  comparison.mp4
```

## Live re-run (future)

`opensop bench` is now a shipped command (`opensop bench --stub` runs offline; add
`ANTHROPIC_API_KEY` for live API calls). This demo replays the recorded outputs from
the original measurement run for reproducibility and offline use. A future update can
run `opensop bench` live and capture a fresh cast directly.

## Files

| File | What it is |
|---|---|
| `demo.sh` | The driver script — deterministic, no API calls, replays recorded data |
| `comparison.cast` | Asciinema v2 cast file (source of truth for the recording) |
| `comparison.gif` | Rendered GIF (~406 KB; re-generate with `make demo`) |
| `Makefile` | `make demo` re-renders cast → GIF → MP4 → frames |
