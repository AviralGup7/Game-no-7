# GameRoot lifecycle and state-machine review

## Why this is a larger risk area

`GameRoot` coordinates the complete run lifecycle: menu, run creation, pause, wave breaks, upgrades, victory, game-over, restart, save finalization, and world construction. A small ordering error here affects every feature at once, unlike an isolated content helper.

## Research basis

- [Godot's pause/process-mode documentation](https://docs.godotengine.org/en/stable/tutorials/scripting/pausing_games.html) establishes that `SceneTree.paused` stops physics and most callbacks, while `PROCESS_MODE_ALWAYS` or `WHEN_PAUSED` selectively keeps controllers and pause UI alive.
- [Godot FSM guidance](https://godot-essentials.gitbook.io/addons-documentation/components/finite-state-machine) recommends a single state-machine commit point, explicit enter/exit behavior, and a current state that is established before dependent logic runs.
- [Godot FSM signal discussion](https://www.reddit.com/r/godot/comments/193v60o/why_use_signals_for_fsm_state_transitions/) highlights the reentrancy hazard around synchronous signals and the value of exposing one transition result to observers.
- [Godot scene communication guidance](https://dredyson.com/signaling-from-a-newly-instanced-node-in-godot-4-x-how-i-fixed-my-saas-game-apps-screen-transition-system-a-complete-beginners-step-by-step-guide-to-node-communication-signal-routing-and-scen/) supports explicit direct references for commands and a signal bus for notifications.

## Weakness found

`EventBus.game_state_changed.emit()` is synchronous. Before this hardening, a listener could call `transition_to()` while `_apply_state()` was still executing. That allowed a second transition to enter recursively, run another state-enter hook, mutate pause/player control, and return to finish the first hook afterward. The order observed by listeners and the state initialization order could therefore diverge. This is especially dangerous for `STARTING_RUN`, whose enter hook builds the world and then requests `PLAYING`.

## Implemented contract

- `_apply_state()` is the only state commit point.
- A transition in progress is serialized with `_transition_in_progress`.
- A synchronous listener may queue one follow-up state; it cannot re-enter the active state hook.
- The first queued request wins and later competing requests are diagnosed and rejected.
- Queued transitions are drained only after the current state-enter hook and synchronization have fully returned.
- Pause/resume transitions use the same queue, so tree pause state cannot be changed halfway through a state notification.
- A bounded transition history and serial number are included in `get_debug_snapshot()` for diagnosing transition loops on devices.
- Existing legal-transition validation still runs when the queued request is committed; invalid queued requests do not bypass the graph.

## QA checklist

1. Attach a listener that requests `PLAYING` when `STARTING_RUN` is announced and verify the run-start hook finishes before PLAYING is committed.
2. Attach two listeners that request different states from one notification and verify the first request wins and a diagnostic is emitted.
3. Request pause from a state notification and verify `SceneTree.paused`, `RunState.paused`, and `GameRoot` state change together.
4. Force an invalid queued target and verify the state remains unchanged after the active hook finishes.
5. Restart from pause, upgrade selection, wave transition, and game-over; verify no pending state survives into the new run.
6. Inspect the bounded transition history during a long run and verify it cannot grow without limit.
