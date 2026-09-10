# Weighted selection robustness review

## Weakness found

`WeightedTable` is a shared dependency of upgrade, loot, wave, and content selection. Its `add()` path sanitized non-finite values, but `set_weight()` did not. A NaN or infinity passed through `set_weight()` could poison `_total`; a NaN sample could then fall through the cumulative scan and select the final entry regardless of its weight. Repeated incremental subtraction also allowed floating-point drift in the cached total.

## Research basis

- The standard cumulative-weight approach described by [Python's weighted choices discussion](https://stackoverflow.com/questions/3679694/a-weighted-version-of-random-choice) is correct only when weights are non-negative finite values and the cumulative total is valid; it also recommends a final fallback for floating-point boundary errors.
- [Gonum's weighted sampling documentation](https://stackoverflow.com/questions/50866502/weighted-sampling-without-replacement-using-gonum) specifically warns that high-variance or very small weight sums can create numerical stability problems.
- [Efraimidis-style weighted sampling research](https://publikationen.bibliothek.kit.edu/1000097067/72597002) describes weighted sampling without replacement and highlights exponential/logarithmic methods when larger or more numerically demanding populations require them.
- Godot's GDScript math API exposes finite-value checks such as `is_nan`/`is_inf`; this project already uses the combined `is_finite` guard consistently elsewhere.

## Implemented contract

- All weight mutation paths use one `_sanitize_weight()` policy.
- NaN and infinity become the existing tiny epsilon; negative and zero values are clamped to epsilon; very large values are capped.
- `set_weight()` now has the same safety guarantees as `add()`.
- Cached totals are rebuilt after add, remove, and set operations instead of accumulating subtraction drift.
- Invalid totals cause a safe empty result rather than undefined selection.
- NaN and infinity samples deterministically map to sample zero.
- `roll_unique()` applies the same finite checks after each removal.
- The cumulative scan retains a final-index fallback for normal floating-point rounding at the upper boundary.

This remains an O(n) roulette-wheel implementation, which is appropriate for the project's small upgrade/wave tables. If future content uses tens of thousands of entries or repeated large samples, a prefix-sum/binary-search or exponential-clock sampler should be benchmarked rather than adding complexity prematurely.

## QA checklist

1. Set a weight to NaN, positive infinity, negative infinity, zero, and a huge value; verify total weight remains finite.
2. Roll with NaN and infinity samples; verify deterministic valid results.
3. Remove entries repeatedly and verify total equals the sum of remaining sanitized weights.
4. Roll unique selections with malformed samples and verify no duplicates and no invalid values.
5. Run distribution checks over many deterministic RNG samples and compare observed frequencies to normalized weights within a documented tolerance.
