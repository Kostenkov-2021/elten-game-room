# Axel Pong and Audio Ball leaderboards

Both games opt into the shared leaderboard registry through
`GameRoomSportsRankings::Game`. Their existing tournament result and goal
exports supply the outcome; this module does not run a second scorekeeper.
Singles and doubles are separate. Each teammate receives the full team score.
Audio Ball exports goals across all accepted sets, not set wins or only the
last set. Only a terminal human-only roster is eligible; an earlier bot does
not disqualify it. Later replacements cannot change the winning-point roster.

## Identity and persistence

Ordinary results use the existing statistical match identity; rematches get a
new identity. Tournament results use the canonical publication, schedule,
fixture and leg. The ordinary observer skips tournament-bound sessions: the
confirmed result/administrative receipt supplies that outcome exactly once.
An all-zero settlement or a draw does not create a win. Technical forfeits use
the same goal scores as the tournament, with no separately invented target.
Legacy games missing an identity or score cannot acquire guessed results.

`sports_match_results` is a public append-only table containing one whole
match per report. Multiple clients can race to report the same match. The
lowest server row ID is canonical; retries acknowledge that existing result.
The original date stays canonical if append acknowledgement and server replay
timestamps differ. Different participants, outcome, mode or goal scores are
conflicts, not another match. These are client-reported results, not an
anti-cheat or a server-authoritative game implementation.

Terminal callbacks copy bounded scalar records into memory. The existing
analytics worker framework persists `sports-rankings-pending.json` and uploads
it, with account/runtime guards, atomic storage, bounded passes and the same
retry policy. No result request or file write is made during an ongoing match.
A ranking failure must not stop play or invalidate a confirmed tournament
result. Table access governs this deliberately public feature; the separate
development-mode opt-out for anonymous activity statistics is unchanged.

## Ordering and presentation

Each match contributes a win/loss component and a bounded goal-ratio component,
weighted by the actual winning side's goals divided by 100. Winner and loser
use the same weight, including a set winner with fewer total goals. User-facing
text describes wins, goal advantage and match length without exposing formulas.
Wins/losses and goal counters themselves are unweighted.

Dates use Europe/Warsaw. Seven- and thirty-day periods include today; the
half-year and year are calendar-month intervals ending today. My statistics
covers all recorded history. Equal internal scores share a place. Lists show
only place and username; Enter opens six read-only counters and balances.
Internal ordering points are not displayed, including in player details.

Native background tasks keep reads and Refresh off the UI thread. Each read
rechecks the schema. Snapshots are bounded by a highest server ID; data and
canonical-group pagination continue after short nonempty pages. Manual Refresh
and every attempted write invalidate the 15-second/4096-match report cache.
Closing or changing accounts discards pending UI results without waiting on I/O.

Deploy the one new table by merging it into the fresh complete owner schema;
do not change existing tables, stamp protection, notifications or file quotas.
Tests: `test/statistics/sports_rankings_*_test.rb` and
`test/tournaments/sports_rankings_test.rb`.
