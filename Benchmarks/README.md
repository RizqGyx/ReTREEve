# Retrieval benchmark

Run before any UI existed, to answer the only question that decides whether
ReTREEve is a real product: *can a reader find a saved passage from incomplete
memory?* This is not part of the app target — it is a standalone Swift script.

```
cd Benchmarks && swift RetrievalBenchmark.swift
```

`docexp.json` caches the model-generated document expansions so the document
side of the index is deterministic between runs. Delete it to regenerate.

## Results — 5 seeded insights, 10 half-remembered queries

| Engine | Top-1 |
|---|---|
| BM25 over the raw passage | 3/10 |
| BM25 + document expansion | 5/10 |
| BM25 + document *and* query expansion | 8/10 |
| `NLEmbedding` sentence cosine | 2/10 |
| `NLContextualEmbedding` mean-pooled cosine | 1/10 |
| **Hybrid (shipped design)** | **9–10/10 top-1, 10/10 recall@3** |

## Three things this established

1. **Apple's off-the-shelf embeddings do not solve this.** The intuitive
   architecture — embed everything, rank by cosine — was measurably *worse*
   than keyword matching. Building on it would have sunk the POC.
2. **The disease is vocabulary mismatch, and the cure is expansion on both
   sides.** Neither half is sufficient alone.
3. **Top-1 is the wrong metric.** The product shows *possible matches* and lets
   the reader recognise one, so recall@3 is what counts.

## Measured again, inside the app (Phase 2)

`swift run` proves the algorithm; the app proves the integration. Launch with
`-runRetrievalCheck` and the report lands in the app container's
`Documents/retrieval-check.txt`.

| Run | Top-1 | Recall@3 |
|---|---|---|
| Hand-written seed expansions | 9/9 | 9/9 |
| **Model-generated, single pass** | **4/9** | **5/9** |
| **Model-generated, 3-angle union** | **8/9** | **9/9** |

The first row is worthless and was thrown away: those expansions were written
while looking at the test queries, so the seed data was flattering itself.
The gap between the second and third rows is the real finding — see below.

## Document expansion is unreliable in one pass

A single generation gave *Outliers* only four phrases, which made "luck and
being in the right place" unfindable and dropped top-1 to 4/9. Generating from
three different angles (everyday rephrasings / situations where the idea
applies / keywords and misrememberings) and unioning the results restored 8/9.

Two failure modes showed up while generating, and both argue for the union:

- **Context window.** Two of three angles for *Deep Work* failed with
  `exceededContextWindowSize` (4091 of 4096 tokens) when the model produced a
  long list. The surviving angle still yielded a usable index.
- **Content refusal.** One angle for *The Psychology of Money* returned
  `refusal — may contain sensitive content`, presumably a financial-advice
  guardrail. The other two covered it.

Because the angles are independent, a failure costs vocabulary rather than the
whole insight.

## Honest caveats

- Five documents is a tiny corpus. Chance alone puts the answer in the top
  three 60% of the time, so recall@3 is encouraging, not conclusive; the 9/10
  top-1 against a 20% baseline is the stronger signal.
- Discrimination between *similar* insights is barely tested. "something about
  improving little by little" already ranks *Mindset* above *Atomic Habits* —
  recoverable only because the reader sees both. Re-run at 50 and 200 insights.
- Precision on off-corpus queries is imperfect. "improving my sleep" returns
  *Mindset* on the strength of the single word *improve*. It is shown at reduced
  strength with its matched term named, so the reader can reject it, but a
  larger library will need a stricter rule than "some lexical evidence exists".
- Model output is non-deterministic, and the hybrid row is a range for that
  reason: observed runs scored 9/10 and 10/10 top-1 on identical inputs, because
  query expansion is regenerated per search. Quote the range, not the best run.
  On the document side two single-pass runs over identical seeds scored 6/10 and 5/10 — hence the cached expansions, and
  hence `semanticDescription` being persisted at save time in the app.
- **Zero-signal trap:** when no query term matches any document every BM25 score
  is 0.0 and the sort order is arbitrary. An early version of this harness
  reported 6/10 for keyword search on exactly that artefact. Any scoring code
  must treat `maxScore == 0` as *no signal*, never as a ranking.
