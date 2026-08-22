verdict: DOCKED

# Issue #39 documentation docking

## Changed surfaces reviewed

- Native editable review text surface and Return/keypad/modifier/IME routing.
- Real AppKit keyboard, multiline, exact-draft, undo/selection, accessibility, scroll, and
  first-responder tests.
- Review coordinator read-only and exact-once confirmation tests.

## Documents checked

- `README.md`
- `CHANGELOG.md`
- `docs/README.md`
- `docs/api.md`
- `docs/architecture.md`
- `docs/streaming-speech-design.md`
- `docs/decisions/D-38-01.md`
- `docs/decisions/D-39-01.md`
- `.env.example`
- Issue #39 body and mission results

## Result

All user-visible keyboard behavior, native editor implications, compatibility semantics, validation
evidence, and unchanged Issue #38 safety/async boundaries are reflected. API, environment, setup,
credential, and transport documents carry explicit no-impact reasons. No docking gap remains.

