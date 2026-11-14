# Mobile Workshop coverage

This pass expands the Car tab on native iOS and Qt Android. Drive, Garage, Session, and PC administration are outside this pass. It isn't a claim of complete desktop parity or live-game certification.

Both mobile apps now have Engine & protection, Handling & gearbox, World & recovery, Body · experimental, and Presets & recovery groups.

| Control | iOS | Android |
| --- | --- | --- |
| Power slider, finite positive numeric entry, 100% restoration | Yes | Yes |
| Engine RPM/limiter/peak readback and torque curve | Yes; selectable readback engine | Yes; all engine summaries, first engine curve |
| RPM editor using current engines' allowed range | Yes | Yes |
| Clutch protection and clutch readback | Yes | Yes |
| Engine strength 0.1–100×, protection, stock limits | Yes | Yes |
| Beam deformation protection | Yes | Yes |
| Grip, sliding grip, brakes, steering, ESC mode | Yes | Yes |
| Actual ratios, forward edits, suggested extra gear, remove last | Yes | Yes |
| Gravity entry and seven planet presets | Yes | Yes |
| Repair, fire, extinguish, deflate, bounce start/stop | Yes | Yes |
| Experimental width/length/height with explicit consent | Yes | Yes |
| Reset persistence, restoration status and errors | Yes | Yes |
| Save current accepted preset, review/apply, progress, cancel | Yes; PC-owned storage | Yes; PC-owned storage |
| Confirmed full reset, available below every group | Yes | Yes |

Power is applied explicitly on mobile rather than continuously during slider movement. Ratio editing uses a forward-ratio field plus actual readback, rather than the PC's per-row comparison editor. Seeded-tune previews, preset rename/notes/import/export, and detailed preset compatibility inspection still need mobile workflows. Those remain on the PC for now; this pass doesn't silently add a remote filesystem API.

New endpoints require a PC host advertising `state.remoteWorkshop.version: 2`. The host publishes only preset summaries, not private notes, JSON files, installation paths, or credentials. Presets are validated and applied by the existing desktop backend. A failed later step doesn't roll back earlier accepted steps. Cancel stops unsent steps, not changes the game already accepted.

All changes retain exact target identity, connection sequence, rate limits, live telemetry, ownership, stopped-speed, capability, and server-policy checks. Unsupported controls stay disabled. Stop bouncing and preset cancellation remain recovery actions. Full-reset and preset confirmations retain the reviewed target so they can't apply to a newly selected vehicle.

Dimension consent doesn't make resizing safe. It changes physical nodes and beam rest lengths; suspension, props, and controllers can conflict. Mass and tires stay unchanged. BeamMP resizing isn't synchronized to other players. Engine and clutch protection remain adapter-specific, not whole-car invulnerability.

Validation belongs in GitHub Actions: PC Qt tests cover command dispatch and consent, Qt mobile tests visit all five groups at phone/tablet sizes, and native iOS tests cover limits, compatibility, engine dispatch, keyboard dismissal, and stale-state disabling with a synthetic TLS fixture. Physical phones and live BeamNG/BeamMP still need testing.
