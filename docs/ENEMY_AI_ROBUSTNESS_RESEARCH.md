# Enemy AI and navigation robustness review

## Why this was selected

Enemy AI is a larger cross-cutting subsystem than a single utility: perception feeds state transitions, navigation feeds locomotion, and both run at high frequency for every enemy in a wave. A bad value or re-entrant transition can affect dozens of actors simultaneously.

## Research basis

- [Godot finite-state-machine guidance](https://godot-essentials.gitbook.io/addons-documentation/components/finite-state-machine) recommends one state-machine commit point and explicit enter/exit lifecycle handling.
- [Godot FSM signal discussion](https://www.reddit.com/r/godot/comments/193v60o/why_use_signals_for_fsm_state_transitions/) highlights that synchronous callbacks can trigger transitions while a state is still active; the machine should remain the single transition authority.
- [Godot pause/process-mode documentation](https://docs.godotengine.org/en/stable/tutorials/scripting/pausing_games.html) documents why simulation updates must be deterministic and why lifecycle controllers need deliberate processing modes.
- [Godot navigation documentation](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_using_navigationagents.html) explains that navigation agents require valid maps and that callers must handle incomplete paths rather than assume a next point always exists.
- [Weighted sampling research](https://publikationen.bibliothek.kit.edu/1000097067/72597002) and the project's own navigation notes support deterministic, bounded calculations for repeatable AI behavior.

## Weaknesses found

1. `EnemyStateMachine` changed state immediately even when `enter()`, `exit()`, or `state_changed` listeners requested another transition. That could leave state A's enter hook running after state B had already become current.
2. `EnemyPerception` accepted NaN/infinite configuration values, frame deltas, positions, intensities, and memory durations. A NaN reaction timer can keep an enemy permanently reacting; a NaN investigation point can poison navigation.
3. `EnemyNavigator` accepted invalid body/target/fallback vectors and invalid refresh intervals. A NaN refresh timer can disable retargeting while a malformed vector can spread into CharacterBody velocity.

## Implemented contract

- Enemy state transitions now serialize re-entrant requests. One state is active at a time, and queued follow-ups drain only after exit, enter, and emitted signals complete.
- Forced transitions (hurt/dead) supersede a normal queued transition, while competing normal requests are diagnosed and rejected.
- Perception configuration uses finite, non-negative bounds and safe defaults.
- Perception resets safely when target or spatial inputs are invalid.
- Reaction, memory, noise, and frame delta values are finite-checked.
- Navigation validates all vectors and substitutes a safe refresh interval when needed.
- Invalid navigation inputs return zero/fallback direction rather than propagating NaN.
- Existing LOS, FOV, flow-field, A*, and legacy navigation fallback behavior remains unchanged for valid inputs.

## QA checklist

1. Have a state `enter()` callback request another state and verify the first state's enter/exit lifecycle completes before the queued transition.
2. Emit a state signal with listeners requesting normal and forced transitions; verify forced requests win safely.
3. Feed perception NaN, infinity, negative deltas, invalid target positions, and invalid noise; verify the enemy resets or ignores the stimulus.
4. Feed navigator invalid vectors and refresh intervals; verify no NaN direction reaches locomotion.
5. Test an unreachable flow-field cell and an invalid NavigationAgent map; verify the documented fallback path is used.
6. Stress a full wave with deterministic seeds and inspect state transition history for loops or simultaneous active states.
