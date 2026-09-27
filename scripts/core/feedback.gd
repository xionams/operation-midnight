extends Object
class_name Feedback

## One channel for telling the player what just happened to an action.
##
## Commands that were silently ignored were the biggest source of "the
## game did not hear me": a dog right-clicked onto a wall, a squad sent to
## a full house, a building dropped outside territory. Every such path
## now reports here with a reason; the HUD shows the text, a CommandMarker
## marks the spot, and AudioDirector plays a cue. Nothing that reports
## needs to know about any of those.

enum Kind { INFO, OK, WARN, REJECT }

static func info(text: String, position: Vector3 = Vector3.INF) -> void:
	EventBus.feedback.emit(text, Kind.INFO, position)

static func ok(text: String, position: Vector3 = Vector3.INF) -> void:
	EventBus.feedback.emit(text, Kind.OK, position)

static func warn(text: String, position: Vector3 = Vector3.INF) -> void:
	EventBus.feedback.emit(text, Kind.WARN, position)

static func reject(text: String, position: Vector3 = Vector3.INF) -> void:
	EventBus.feedback.emit(text, Kind.REJECT, position)

static func color_for(kind: int) -> Color:
	match kind:
		Kind.OK:
			return Color(0.45, 1.0, 0.55)
		Kind.WARN:
			return Color(1.0, 0.75, 0.25)
		Kind.REJECT:
			return Color(1.0, 0.35, 0.3)
	return Color(0.6, 0.85, 1.0)
