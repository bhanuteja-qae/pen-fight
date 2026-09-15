---
status: accepted
---

# Separate application flow from live game sessions

Pen-Fight currently launches directly into a live match, but Offline Android V1 adds boot, Home, mode selection, Pens, Settings, Solo, and leave/re-entry flows. Application flow will own navigation, global settings, and Android Back behavior, and will create a Game Session only while the player is in active play; the Game Session owns match rules and presentation, while `TurnState` remains pure gameplay logic.

## Considered options

A single always-instantiated gameplay scene could show or hide menus with visibility flags, or remain paused behind application screens. Those options were rejected because the current gameplay scene begins a turn at startup and owns idle-forfeit, physics-resolution, input-lock, and automation timing; retaining it behind menus would couple navigation to live match state and make bot timers, score, gates, and settings vulnerable to hidden progression or stale callbacks.

## Consequences

Offline Android V1 needs a new application root above the existing gameplay scene. Entering play creates a configured Game Session; leaving play tears it down, and application screens never depend on a live `TurnState`. Global settings and Back navigation move to application ownership, while gameplay tests remain able to instantiate the gameplay scene directly without navigating the application shell.
