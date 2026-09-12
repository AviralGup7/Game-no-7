class_name ExpectedErrors
extends RefCounted
## Exact, bounded negative-test diagnostics. Errors remain in the log; the
## strict log checker requires each declared line exactly once inside this block
## and rejects missing, extra, nested or unterminated expectations. Production
## import/export/UI logs do not enable this protocol.

static func begin(messages: Array[String]) -> void:
	print("TEST EXPECTED ERRORS: " + JSON.stringify(messages))


static func end() -> void:
	print("TEST EXPECTED ERRORS END")
