class_name ValidatedConfig
extends Resource

## Protocol base for authored content configs (Godot has no interfaces, so the
## "implements validate()" relationship is expressed through this base class).
## ContentLoader registers any ValidatedConfig and runs its self-checks; each
## concrete config overrides validate() to report its own authoring problems.

func validate() -> Array[String]:
	return []
