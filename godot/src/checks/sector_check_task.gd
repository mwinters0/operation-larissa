@tool
class_name SectorCheckTask
extends RefCounted
## "Check sector" running in the background: the what-changed report and the instant checks are made at once, the reachability search
## (the part that takes seconds) runs on a `WorkerThreadPool` thread, and `finished` is emitted on the main thread when the report is complete.
##
## Teaches: moving one slow step off the main thread without making the rest thread-safe. The parts that touch resources and autoloads
## (`SectorChanges.report`, the instant checks, preparing the search: `SectorReport.begin`) stay on the thread that asked; only the search
## itself, which works on a private copy of the data (`ReachSweep.prepare_for`, the same split `SectorChecks.check_many` relies on to
## search 32 sectors side by side), runs on the worker. A thread cannot emit a signal into the UI, so it ends by `call_deferred`-ing a
## method of this object, which then runs in the main loop; a window just waits for `finished` (or asks `running`) and keeps drawing meanwhile.
##
## Use:  var task := SectorCheckTask.start(sector, true, true, true, false)
##       task.finished.connect(func(report: SectorReport) -> void: print(report.text()))

## The report is complete (`findings` are in it); emitted on the main thread, never in `start` itself.
signal finished(report: SectorReport)

var report: SectorReport
var running := true

var _task_id := -1
var _done := false
## A `Callable` does not keep an object alive; this does, until the task is over, so that nobody has to hold on to it.
var _keep_alive: SectorCheckTask


## Starts the work. Arguments as `SectorReport.make`.
static func start(sector: SectorData, with_changes: bool = true, with_checks: bool = true, reach: bool = true, with_shared: bool = false) -> SectorCheckTask:
	var task := SectorCheckTask.new()
	task._keep_alive = task
	task.report = SectorReport.begin(sector, with_changes, with_checks, reach, with_shared)
	if task.report.has_search():
		task._task_id = WorkerThreadPool.add_task(task._search_on_worker, false, "sector checks: reachability search")
	else:
		task._finish.call_deferred()
	return task


## Waits for the search and returns the finished report (for a caller that cannot wait for the signal, such as a script).
func wait() -> SectorReport:
	_finish()
	return report


func _search_on_worker() -> void:
	report.search()
	_finish.call_deferred()


func _finish() -> void:
	if _done:
		return
	_done = true
	if _task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1
	report.complete()
	running = false
	var keep := _keep_alive                 # let go of ourselves only when this method is over
	_keep_alive = null
	finished.emit(report)
	keep = null
