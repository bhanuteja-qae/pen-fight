# Pen-Fight

Pen-Fight is an offline Android game about committing one physical pen flick at a time, reading the result, and adapting across short competitive matches. This glossary defines the shared product language for local hot-seat play and the solo Rival Circuit.

## Play structure

**Game Session**:
One visit to active play, beginning after mode selection and ending when the player returns Home. A Game Session has at most one active Match at a time and may contain rematches.
_Avoid_: App session, run

**Round**:
One contest beginning with both pens placed on the table and ending with a single authoritative verdict. A Round may contain multiple alternating Flicks.
_Avoid_: Turn, game

**Match**:
A best-of-N sequence of Rounds that produces one Match winner.
_Avoid_: Series, session, game

**Hot-seat Series**:
The persistent count of completed Match wins between the current two Local Players. It survives Game Sessions and starts fresh when either Local Player identity is replaced.
_Avoid_: Match score, lifetime score, Solo record

**Solo Progress**:
The device-local record of defeated Rivals, earned Mastery Stamps, and Rival Circuit completion. It is separate from the Hot-seat Series.
_Avoid_: XP, account level, Hot-seat record

## Competitors and control

**Local Player**:
One of exactly two editable human identities stored on the device for hot-seat play. A cosmetic spelling or capitalization edit preserves the identity; replacing the person starts a new Hot-seat Series after confirmation.
_Avoid_: Account, profile, red player, blue player

**Participant**:
One competitor in a Match. A Participant represents either a Local Player or a Rival and is assigned a Slot, Controller, Pen Model, and effective Pen Profile for that Match.
_Avoid_: User, slot, controller

**Slot**:
An internal table position assigned to a Participant for a Match. A Slot may use identifiers such as red or blue, but it is never a player identity, Rival identity, or display name.
_Avoid_: Player, side, bot

**Controller**:
The source of legal Flick intent for a Participant. V1 Controllers are Human or Bot.
_Avoid_: Participant, player identity

**Flick**:
One committed pen action defined by direction, power, and grip position. Once committed, the physical result is authoritative and cannot be corrected, retried, or overridden.
_Avoid_: Shot, move, turn

## Modes, rules, and pens

**Game Mode**:
The participant arrangement for a Game Session. V1 Game Modes are Hot Seat and Solo.
_Avoid_: Classic, Pen Powers, difficulty

**Ruleset**:
The rule variant governing pen behavior independently of Game Mode. V1 Rulesets are Classic and Pen Powers.
_Avoid_: Game Mode, difficulty

**Classic**:
The default Ruleset in which every Pen Model uses the same Control physics, preserving symmetric hot-seat play while retaining each model’s visual identity.
_Avoid_: Cosmetic mode, standard difficulty

**Pen Powers**:
The optional Ruleset in which each Pen Model uses its fixed, visible Pen Profile with an explicit strength and cost.
_Avoid_: Power-ups, upgrades, abilities

**Pen Model**:
One of the four fixed visible pen identities. A Pen Model keeps the same size and appearance across Rulesets.
_Avoid_: Skin, class, Slot

**Pen Profile**:
A Pen Model’s physical behavior under Pen Powers. Classic normalizes every Pen Model to the Control profile; Pen Powers applies the model’s own profile.
_Avoid_: Skin, velocity stat, upgrade

## Solo opponents and progression

**Rival**:
One authored solo opponent with a visible identity, a recognizable strategic habit, and one Mastery Stamp challenge.
_Avoid_: Difficulty level, bot slot

**Bot Profile**:
The decision style and bounded judgment noise that make a Rival behave distinctly. It never grants hidden physical advantages or changes a Flick after commitment.
_Avoid_: Bot stats, difficulty multiplier, Pen Profile

**Rival Circuit**:
The solo path against authored Rivals. V1 ships a single Rival; beating it completes the Circuit and leaves it freely selectable, without introducing an economy.
_Avoid_: Campaign, ladder, season

**Mastery Stamp**:
One optional, non-repeatable skill challenge associated with a Rival. A Mastery Stamp records demonstrated play; it is not currency, an upgrade, or a requirement to continue.
_Avoid_: Achievement points, reward currency, quest
