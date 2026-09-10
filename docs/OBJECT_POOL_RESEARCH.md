# Object pool robustness review

## Why this was selected

After the save-system hardening, the most fragile reusable runtime primitive was `ObjectPool`. It sits beneath projectiles, pickups, damage numbers, and effects: a bookkeeping mistake there can cause stale state, negative live counts, or an object being returned twice and later acquired by two systems.

## Research

- The Godot pooling guide at [Uhiyama Lab](https://uhiyama-lab.com/en/notes/godot/godot-object-pooling-basics/) emphasizes that `_ready()` is not rerun on reuse, and that pooling requires an explicit reset/spawn lifecycle. It also warns that hiding a node alone does not stop processing or collisions.
- [Godot forum guidance](https://forum.godotengine.org/t/adding-and-removings-hundred-of-objects-potentially-per-frame-good-or-bad/79238) recommends pooling only for high-frequency objects and maintaining explicit inactive/active ownership.
- The [pooling trade-off review](https://saltmire.github.io/godot-4-object-pooling-vs-instantiate.html) identifies stale velocity, timers, tweens, and signal state as the main failure mode and recommends a reset on every acquire.
- The general [object-pool design pattern](https://thegrumpydev.substack.com/p/design-patterns-object-pool) keeps separate available and in-use collections so release can reject objects that are not currently checked out.

## Problems fixed

The previous implementation only checked `_free` during release. A foreign object was therefore accepted and decremented `live_count`; a failed factory could also place `null` in the free list, causing a later acquire to report a live object while returning `null`.

The implementation now:

- tracks every successful acquire in `_leased`;
- rejects foreign and duplicate releases without changing accounting;
- never seeds the free list with `null` and stops prewarming safely if the factory fails;
- refuses a failed lazy factory without incrementing creation or live counters;
- resets on release and again on acquire, protecting both normal reuse and activation-context-dependent resetters;
- preserves the maximum idle size and frees overflow `Node` instances;
- keeps the primitive headless-testable and generic for Dictionary-based test doubles as well as Godot Objects.

## QA checklist for Godot/device testing

1. Acquire every prewarmed item, exhaust the pool, and confirm lazy creation is bounded by actual demand.
2. Release the same item twice and verify `live_count`, idle count, and later acquisition remain correct.
3. Release an item from another pool and verify it is ignored.
4. Make the factory return `null` during prewarm and lazy acquire; verify no null enters the pool.
5. Mutate velocity, timers, visibility, collision state, and animation state, release, then acquire and verify the reset callback clears all of them.
6. For Node pools, verify overflow and `clear_idle()` queue-free idle nodes and never free leased nodes.

Pooling should remain limited to high-churn objects confirmed by profiling; for low-frequency content, normal instantiation is simpler and safer.
