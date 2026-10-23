# Partnerships, table conferences and Audio Ball doubles

Design plan requested on 23 October 2026. Implementation and scoped live-account
verification were subsequently requested on the same day. The source changes
are implemented; verification results and their limits are recorded below.
The maintainer subsequently requested release 2.0.5.5 / build 256 and a GitHub
push. The earlier verification below remains evidence for its recorded source,
not a claim that the later audio refinements were tested live.
Earlier completed fixes and audits are separate.

The maintainer approved implementation of this plan. The Audio Ball section
includes the subsequent clarification: retain the ordinary listening model and
penalize a fresh defence key press while the ball is flying to the partner,
not every input outside the player's turn. The later refinement also removes
automatic defender/fault speech and gives the fault its own goal sound.

## 1. Goals and implementation order

1. Make choosing a tournament partner unambiguous, including replacing a
   pending invitation, changing an established partnership and notifications.
2. Preserve mutually agreed teams. Automatically pair the remaining entrants
   at tournament start, without allowing the organizer to choose their partners.
3. Explain precisely why a tournament cannot start.
4. Disconnect the table's conference when its member leaves the table, and
   provide Ctrl+Shift+M for the native microphone mute toggle.
5. Design and implement Audio Ball doubles using the existing game framework,
   alternating players and the ordinary Audio Ball listening model.

Implement and verify the partnership/start flow before adding doubles. Do not
couple tournament pairing to the Audio Ball client or conference membership.

## 2. Source baseline before this implementation

- `lib/tournaments/public_preview.rb` provides participant partner selection;
  choosing another person currently submits a new choice directly.
- `lib/tournaments/registration_projection.rb` projects pending requests and
  reciprocal pairs. Its current request map already keeps one outgoing target
  per participant; investigate repeated invitations and their visible messages
  instead of assuming it stores several simultaneous confirmed partnerships.
- `lib/tournaments/participant_partner_picker.rb` and `public_service.rb`
  currently allow an organizer to reconfigure established pairs.
- `lib/table_voice_screen.rb` already uses native Conference channels and
  distinguishes creator and guest disconnection. Extend the shared table-leave
  lifecycle rather than adding special cases to individual games.
- Audio Ball currently has two playing seats. Its controls, flight ownership,
  score/set rules and local sound preferences are described in
  [AUDIO_BALL.md](AUDIO_BALL.md).

These are source observations, not newly reproduced live defects.

## 3. Partner selection: proposed participant workflow

Use one shared per-tournament partnership state, not independent UI flags:

- A participant has at most one confirmed partner and one active outgoing
  invitation. A pending invitation is not an established team.
- An existing outgoing invitation is shown with its recipient. Selecting that
  person again does not send another invitation or notification.
- Selecting a different recipient asks whether to replace the existing pending
  invitation, naming both people. Cancelling leaves the old invitation intact.
- Replacing a pending invitation invalidates the previous choice. Its stale
  notification must not subsequently establish a team.
- Form a team only after both participants agree to that exact proposal. An
  explicit Accept action is clearer than requiring the recipient to discover
  that choosing the sender a second time means acceptance.
- Incoming proposals may be listed together. Accepting one makes conflicting
  pending proposals inactive; it never puts a participant into two teams.
- Someone already in an established pair is not an available invitation target.
  To choose another partner, a participant first explicitly confirms dissolving
  the current pair. Name the affected partner and notify them after confirmation.
  Do not silently dissolve a team merely because its member browsed another name.
- Keep established pairs fixed after the tournament starts. A withdrawal or
  participant removal before start leaves the remaining member available.

Keep the existing Participants entry and contextual actions. Show the current
partner or pending invitation in the relevant view, preserve focus on refresh,
and hide actions that no longer apply. Avoid another permanent settings screen.

### Agreed Participants view for team tournaments

The maintainer reports redundant reciprocal rows such as "Balteam — partner:
Papierek" followed by "Papierek — partner: Balteam". The display should present
each established team once, above entrants who do not yet belong to a team,
without losing access to actions concerning an individual member.

The maintainer accepted the grouped view, with one Participants list rather
than two separate lists switched with Tab:

- Use one ordinary Participants list. Show established teams first and unpaired
  people below them. Do not add another Tab stop, a filter, or decorative
  headings or summary rows as though they were participant accounts.
- Each team row names every member once, for example "Balteam, Papierek".
  A team is a group, not a synthetic ELTEN user. Apply the same design to teams
  larger than two; do not hard-code the view around doubles.
- Enter on a team opens a short member list. Each member has their own selectable
  row, and Enter there opens the usual native ELTEN user menu. Escape returns to
  the same selected team in Participants. A team-row context action also provides
  access to the member list.
- Each unpaired person has one row below the teams. Enter opens their native
  user menu directly. Pending partner proposals do not count as established
  teams and do not duplicate their senders or recipients among team rows.
- Keep authorized individual organizer actions in the relevant person context
  menu, including the member sublist. Do not turn removing one entrant into
  removing a whole team, or use the new view to restore organizer pair overrides.
- If there are no teams or no unpaired people, simply omit that kind of row.
  Explain an entirely empty list without creating a fake actionable account.
  Individual tournaments retain the ordinary person-per-row Participants view.
- Derive the main list and member sublists from the same validated roster/team
  projection. Each registered person belongs to exactly one display group.
  Use stable team/member identities, not labels or row positions, and revalidate
  actions if a partnership changes while its member list is open.
- Update quietly. Pair formation/dissolution may change the grouped rows,
  but must not reopen dialogs or repeat the entire roster. Preserve selection
  where the same team/person still exists and handle a removed selection safely.

This adds one Enter when opening a paired person's user menu in exchange for
reading each team once in the main view. Individual participants and their
native user menus remain available.

## 4. Partnership notifications

Treat partnership proposals, tournament enrollment invitations and invitations
to play a tournament match as different actions with clear wording.

- A proposal names the sender and tournament and leads directly to Accept /
  Decline for that proposal, not an unrelated tournament list.
- Notify both affected participants when a pair becomes established or is
  dissolved. A pending-proposal cancellation goes to its recipient only.
- Replacing an outgoing request gives its former recipient a clear cancellation,
  not a second still-actionable request. Declining informs the sender.
- When automatic start pairing assigns a partner, tell both players who their
  partner is and identify the tournament.
- Generate messages from confirmed applied transitions. A merely acknowledged
  row which was rejected as obsolete is not a successful partnership.
- Opening an obsolete notification explains that it is no longer current. It
  must not restore an old pair, send a new invitation or produce an empty item.
- Deduplicate notifications by the confirmed operation/transition. Reloads,
  reconnects and revisiting Participants must not replay announcements.

Retain authenticated display names, localized text and the existing notification
mechanism. Do not add polling or a separate partner-notification transport.

## 5. Organizer powers and automatic pairing

Recommended target: remove manual partner assignment by the organizer, rather
than retaining a special organizer override restricted to unpaired people.
The organizer may choose their own partner under the same participant rules.
Normal registration administration remains separate.

At tournament start:

1. Load and validate the current registered entrants and confirmed pairs.
2. Leave every mutually agreed pair intact.
3. Collect only entrants who still have no confirmed partner. Pending proposals
   do not reserve anyone or block random completion.
4. Randomly pair those entrants once. Do not offer manual selection of the
   outcome, a preview that can be rerolled, or a reroll button.
5. Persist the accepted roster, preserved pairs and random completion as the
   source for the tournament schedule. End obsolete pending proposals.
6. Announce the resulting partners and start the tournament through its normal
   start path.

Use one start-preparation path for manual and scheduled starts. A retry or lost
response must recover the existing draw/start, not produce new teams. Revalidate
the roster generation at the write boundary; a changed roster cannot silently
inherit a draw for different entrants. Keep current operation journals,
authenticated ordered records and reconciliation. Existing append-only claims
are not server transactions, and drawing instead of manual assignment is not
proof of protection from a modified client.

If the unpaired count is odd, do not drop someone, break an established team or
invent a walkover to make the count fit. Block start and explain the issue.
Likewise, state missing entrants, invalid team sizes or other unmet game/format
requirements explicitly. For example: "Nie można rozpocząć turnieju: bez pary
pozostały 3 osoby. Potrzebna jest parzysta liczba uczestników bez partnera."
A network error is not evidence of a missing entrant or an empty participant list.

Apply the redesigned policy to new starts with an explicit compatibility
boundary. Preserve the rosters, matches, accepted starts and results of existing
started tournaments; do not reinterpret their historical pairing records.

## 6. Table conference lifecycle and microphone shortcut

Leaving a table should also leave its associated native Conference channel.

- Run cleanup after confirmed departure or confirmed table closure, including
  a switch to another table through an invitation. Cancelling or failing the
  table-leave operation must not disconnect the user.
- Merely opening Messages, minimizing the game, closing a settings dialog or
  temporarily losing network updates is not leaving the table.
- Match the exact local table-conference identity, including a retained local
  channel whose published invitation was already cleared. Never disconnect an
  unrelated conference the user joined later.
- Reuse creator/guest behavior: a guest leaves locally; a creator clears only
  their current table invitation. Do not disconnect other guests by force.
- Do not report successful voice disconnection if native leave fails. Provide
  a short actionable failure message and keep the local channel identity so the
  user can still disconnect. Do not trap the user at an already departed table.

Ctrl+Shift+M should toggle the microphone of the active native conference while
using Power Games. Reuse the host's mute state and API; if the host already
handles the key, do not bind a second toggle to the same keypress. Confirm the
result briefly as microphone muted/unmuted. Do not mute game audio, the received
voices or notifications, and do not implement a system-wide keyboard hook.
The microphone interpretation is the proposed meaning of "mute the conference";
whole-conference playback muting would be a different feature.

Do not change Conference premium/access checks or native channel visibility
policy as part of this scope.

## 7. Audio Ball doubles

### Maintainer's direction

- Add a four-player, two-team variant while preserving singles.
- Keep listening like ordinary Audio Ball, rather than creating four artificial
  sound positions or a different interpretation of the three shot sounds.
- Alternate teammates' turns. A game-key press outside the participant's turn
  gives the opposing team a goal, making attention to turn order part of play.

### Proposed turn sequence

Each receiver defends, prepares and returns the ball during their turn. On the
next return to that team, their partner takes over. There is only one active
defender/controller for a flight; the first teammate to press does not acquire
the turn. For teams A1/A2 and B1/B2, one possible sequence is A1, B1, A2, B2,
then A1 again. Names, not these seat codes, belong in player-facing descriptions.

The implementation interleaves each team's ordered seats. It draws the first
server once from all four seats, advances service one place every two points
within a set, and advances the first server one place between sets. Each hit
passes play to the next seat in that ring. The existing point/set targets and
two-point service interval are unchanged. Local listening preferences do not
change this order or who is allowed to act.

### Wrong-turn goal

- Penalize a fresh press of a gameplay action in the focused playfield during
  active play by the wrong participant. Apply one normal opposing-team point
  through the existing accepted goal/result path, not a private local score.
- Do not penalize chat input, settings, help, informational shortcuts,
  spectators, score/set breaks or a network pause.
- Do not treat keyboard autorepeat or a key held from the preceding turn as
  a new wrong-turn action. Clear inherited held state at turn boundaries using
  the existing input ownership rules.
- Scope the decision to the current match/generation/rally/flight and controller.
  Late packets and old turn inputs must not manufacture another goal. Resolve
  simultaneous input, an ordinary miss and a wrong-turn press as at most one
  point, consistently on all clients.
- Bots obey the same turn ownership and action path as humans.

### Listening and settings

Keep the ordinary left/right listening preference and local sound-pack choice
under Ctrl+P. These are personal settings, not organizer-controlled rules. The
provisional default is the normal Audio Ball court feed, including the partner's
exchanges; do not add a new mixer or mute the partner by default.

The implementation uses that normal feed, without extra mix profiles.
Observers keep the ordinary court perspective without receiving game controls
or wrong-turn penalties. The separately approved Pong sound preference below
does not change Audio Ball's mix.

## 8. Verification and completion criteria

### Subsequent approved Axel Pong preference

Add a personal Ctrl+P choice for doubles movement and paddle-contact sounds:
team-position voices (the existing default), or consistent own voices regardless
of team position. In the latter mode the local player's normal steps/contact stay
unchanged and their partner uses the contrasting doubles voice. Do not change
the ball, the opponents, physics or what other clients hear.

Once implementation is requested, update affected tests with each change and
test changed paths and their real dependencies locally and on live accounts.
This is not permission to repeat the whole-project audit or every game campaign.

- Partners: repeated/replaced invitations, cross-invites, competing acceptances,
  decline, cancellation, dissolution, withdrawal, stale notices, reconnect and
  uncertain writes. Verify both participants' actual screens and notifications.
- Participants view: teams of two and larger sizes, every entrant shown once,
  pending versus established pairs, absent row groups and an entirely empty list,
  native user menus from person rows/member sublists, individual organizer
  actions, quiet updates and a team
  change while the member list is open. Individual tournaments retain one list.
- Start: zero/two/four unpaired entrants, an odd remainder, all pairs already
  fixed, a changed roster, organizer as participant, scheduled/manual start and
  retry without reroll. Confirm the exact reason when blocked and unchanged
  accepted historical rosters/results.
- Conferences: creator and guest leave, cancelled leave, table closure, table
  switch, unrelated conference, cleared invitation and failed native leave.
  Verify actual native membership, microphone state and audible communication,
  not only successful service return values.
- Doubles: all four playing seats, ordinary and wrong-turn actions, held keys,
  late/duplicate events, serves, points, sets, bots, spectator host, reconnect,
  host transfer and operation behind another native window. Check singles and
  the existing Duck Racing Audio Ball challenge as affected consumers.
- For audio choices, distinguish real listening checks from state assertions
  and fake sound handles; four accounts on one PC do not prove internet latency.

Before a requested release, update README, affected rules, context help and
translations in every supported language. No release or GitHub operation is
part of this implementation request.

## 9. Verification record

Private evidence is in `tmp/partners-voice-doubles-20261023/`. This was a
scoped implementation, not another whole-project audit or a release.
Across the recorded targeted runs, the latest results for 66 distinct scripts
are passing. Earlier failures and their subsequent corrections remain in the
reports; this is not a claim of a single full-suite 66/66 run.

- Real service, projection, journal and native-form tests cover exact requests,
  replacement, stale acceptance at the write boundary, dissolution, organizer
  restrictions, grouped participant rows, native user menus and notification
  entry without automatic acceptance. Scheduled completion and minimum/odd
  roster reasons are checked locally through the real service and store.
- On four signed-in accounts, a diagnostic tournament preserved the accepted
  pair, drew the remaining pair and presented the same teams to all accounts.
  Request replacement, stale acceptance, decline, cancellation, dissolution and
  reacceptance used the actual server. Retrying an already started tournament
  was rejected without redrawing it.
- Live four-person Audio Ball exposed a missing recipe-field check in the
  doubles first-server replay. It was fixed and a native server-random decode,
  replay and executor regression was added. Four clients then agreed on first
  service, ordinary points, service rotation and a single wrong-turn penalty.
  The automated attempt at a six-hit rally did not complete and is not counted
  as a successful exchange test.
- Native Conference creation/join and the actual microphone toggle were
  exercised. Creator departure withdrew the invitation and left locally; the
  guest stayed connected until leaving the table, then also disconnected despite
  the cleared invitation. The trials found and fixed both an absent initial
  voice value after a join activity and loss of the identity during asynchronous
  native join acknowledgement.
- A partnership notice travelled through the installed application's real
  notification route to the test account. Its actual inbox verified diagnostic
  table evidence asynchronously; the normal presenter supplied a named partner
  and action. The test-only source binding was restored and the exact notice
  revoked. The uninstalled diagnostic app's notification attempts were not
  delivered and are not counted as successful notification tests.
- The temporary tournament was cancelled and only the trial's own table and
  native memberships were closed. Earlier diagnostic publications were retained.
  No schema, protection, quota, installed package, version or GitHub state changed.

The live trials used four accounts on one computer and one connection, with
native forms, handlers, networking and game clients. They do not constitute
physical keyboard tests, human listening checks, a full doubles match, or every
failure/recovery case on separate networks. Local engine/relay tests additionally
cover all four seats, team layouts, normal return rotation, bots, an observer
host, snapshots, scoring and existing singles/Duck Racing consumers. The Pong
preference is checked with controlled sound handles; its subjective sound
balance remains for the maintainer to assess.
