class_name AppFlow
extends RefCounted
## Wave 1, wayfinder ticket #5: pure-logic application-navigation state
## machine (docs/prototypes/CONTRACTS-app-flow.md). NO Node2D / scene-tree /
## physics dependencies and NO node/scene instantiation anywhere in this file
## (ADR-0001: application flow owns navigation; it only ever *requests* that
## the host create or tear down a Game Session — it never creates one
## itself). Construct with no arguments and drive it entirely through the
## methods below; `screen` is read-only for consumers — only this file ever
## assigns it.
##
## Screen graph (see CONTRACTS-app-flow.md for the pinned invariants):
##   BOOT -> HOME                              (boot_complete)
##   HOME -> MODE / PENS / SETTINGS            (open_mode_select/open_pens/open_settings)
##   MODE -> HOME                              (Back)
##   PENS -> HOME                              (Back)
##   SETTINGS -> HOME                          (Back)
##   MODE -> PLAYING                           (start_match, emits gameplay_start_requested)
##   PLAYING -> HOME                           (end_match, emits gameplay_stop_requested)
##   PLAYING -> CONFIRM_LEAVE                  (Back — never straight out of PLAYING)
##   CONFIRM_LEAVE -> PLAYING                  (cancel_leave, or Back — resumes, no signal)
##   CONFIRM_LEAVE -> HOME                     (confirm_leave, emits gameplay_stop_requested)
##
## boot_complete() is one small addition beyond the ticket's pinned 8-method
## API surface (open_mode_select/open_pens/open_settings/confirm_leave/
## cancel_leave/start_match/end_match/handle_back). BOOT is a real, pinned
## Screen value with no other way to leave it, so an explicit kickoff is
## needed to make it a reachable, test-covered state at all — mirroring
## TurnState.begin_turn() (game/scripts/turn_state.gd), which the same repo
## convention uses to leave its own resting initial state. This does not
## change any pinned signature. Flagged for orchestrator awareness per the
## contract's "any interface change requires orchestrator approval" rule.
##
## The loading-view question the ticket asks ("real work feedback or a fake
## delay?"): this module answers it for the pure-logic layer by NOT modeling
## one. boot_complete() transitions synchronously — no timer, no counter, no
## simulated wait. If a host wants BOOT to be visible for longer than one
## frame, that must be justified by real async work upstream of calling
## boot_complete() (asset loads, save-file reads), never by this state
## machine manufacturing a delay. See Wave 2/3 docs/prototypes/app-flow/ for
## the product-level decision this evidence feeds.

enum Screen { BOOT, HOME, MODE, PENS, SETTINGS, CONFIRM_LEAVE, PLAYING }

signal screen_changed(from: Screen, to: Screen)
## Emitted ONLY on a transition into PLAYING (i.e. only inside start_match()).
signal gameplay_start_requested(mode: String)
## Emitted ONLY when a live match is actually ending for good — end_match()
## (the match concluded) or confirm_leave() (the player chose to leave and
## confirmed). Entering CONFIRM_LEAVE via Back does NOT emit this: the match
## is still live and recoverable there via cancel_leave(), which is the
## entire point of a leave-confirmation screen — nothing is torn down until
## the player actually confirms.
signal gameplay_stop_requested()

## Read-only for consumers: only the private _transition() below assigns it.
var screen: Screen = Screen.BOOT


func boot_complete() -> void:
	if screen != Screen.BOOT:
		return
	_transition(Screen.HOME)


func open_mode_select() -> void:
	if screen != Screen.HOME:
		return
	_transition(Screen.MODE)


func open_pens() -> void:
	if screen != Screen.HOME:
		return
	_transition(Screen.PENS)


## Settings is reachable only from HOME. In particular this is a no-op from
## PLAYING: pausing a live match for settings is host-owned suspend behavior,
## not application-flow navigation (see CONTRACTS-app-flow.md).
func open_settings() -> void:
	if screen != Screen.HOME:
		return
	_transition(Screen.SETTINGS)


## CONFIRM_LEAVE -> HOME. The player confirmed leaving a live match: this is
## one of the two points that actually ends the Game Session, so it emits
## gameplay_stop_requested().
func confirm_leave() -> void:
	if screen != Screen.CONFIRM_LEAVE:
		return
	_transition(Screen.HOME)
	gameplay_stop_requested.emit()


## CONFIRM_LEAVE -> PLAYING. The player backed out of leaving: the match was
## never torn down, so no signal fires — this is a pure resume.
func cancel_leave() -> void:
	if screen != Screen.CONFIRM_LEAVE:
		return
	_transition(Screen.PLAYING)


## MODE -> PLAYING. The only place gameplay_start_requested can ever fire.
func start_match(mode: String) -> void:
	if screen != Screen.MODE:
		return
	_transition(Screen.PLAYING)
	gameplay_start_requested.emit(mode)


## PLAYING -> HOME. The match concluded on its own (not via leave-confirm):
## the other point that ends the Game Session, so it emits
## gameplay_stop_requested().
func end_match() -> void:
	if screen != Screen.PLAYING:
		return
	_transition(Screen.HOME)
	gameplay_stop_requested.emit()


## true = the back press was consumed by a navigation change; false = there
## is nothing behind the current screen and the host should quit the app.
func handle_back() -> bool:
	match screen:
		Screen.BOOT, Screen.HOME:
			return false
		Screen.MODE, Screen.PENS, Screen.SETTINGS:
			_transition(Screen.HOME)
			return true
		Screen.CONFIRM_LEAVE:
			# Back while confirming leave cancels the leave, same as cancel_leave().
			_transition(Screen.PLAYING)
			return true
		Screen.PLAYING:
			# Never straight out of PLAYING — always route through confirmation.
			_transition(Screen.CONFIRM_LEAVE)
			return true
		_:
			return false


func _transition(to: Screen) -> void:
	var from := screen
	screen = to
	screen_changed.emit(from, to)
