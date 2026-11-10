class_name ProblemRunner
extends RefCounted
## Shows a ProblemScreen on top of a host node and waits until the problem is over.
##
## Teaches: `await` on a signal. One `await ProblemRunner.run(...)` line replaces the
## "connect, remember state, disconnect" boilerplate every caller (the sector viewer today,
## the real game, the debug menu) would otherwise repeat.
##
##     var session := await ProblemRunner.run(self, instance)
##     if session.solved: ...

const SCREEN_SCENE := preload("res://src/problems/problem_screen.tscn")


## Adds a ProblemScreen as the last child of `host` (so it covers it), starts `problem` and
## returns the finished `ProblemSession`. The screen is freed afterwards.
## `sfx_sink` (optional) receives the screen's `sfx_requested` signal; `configure` (optional) is called with the
## screen before the problem starts, to set its options and connect to its signals (Math Practice does).
static func run(host: Node, problem: ProblemInstance, sfx_sink: Callable = Callable(), configure: Callable = Callable()) -> ProblemSession:
	var screen: ProblemScreen = SCREEN_SCENE.instantiate()
	host.add_child(screen)
	if sfx_sink.is_valid():
		screen.sfx_requested.connect(sfx_sink)
	if configure.is_valid():
		configure.call(screen)
	screen.start(problem)
	var session: ProblemSession = await screen.finished
	screen.queue_free()
	return session
