## 2026-04-04

- Mistake: Interpreted "no antonyms" as a request to remove antonyms from the character index.
  Root cause: I treated a terse bug report as an implementation instruction instead of clarifying the likely failure signal.
  Preventative rule: When a short request can mean either "remove X" or "X is missing," prefer the bug-report reading if it fits the product context and verify against the current output before changing schema or UI.

- Mistake: Tried to move a widget test to the second reading unit through viewport-dependent taps before seeding the reader state directly.
  Root cause: I reached for UI navigation first instead of using the reader's existing `PageStorage` state hook, which is more deterministic in tests.
  Preventative rule: When a widget test needs a non-default reading position, seed `PageStorage` or equivalent persisted state first and only use scrolling taps when the navigation path itself is what is under test.

- Mistake: Added a second `ChengyuGuidedChatBackendClient` test helper instead of extending the existing one.
  Root cause: I inserted the new regression fixture near the new test before checking for an existing helper with the same responsibility later in the file.
  Preventative rule: Before adding a new fake client or fixture class in a large test file, search for an existing helper with the same domain name and extend or update that helper first.

- Mistake: Assumed every `guided-chat-fab` opened the same line-level flow.
  Root cause: I changed the direct `ChapterReaderPage` path first without checking the other call site that reuses the same key from the embedded chapter view.
  Preventative rule: When a behavior change is keyed off a shared control name, search every call site for that key before locking in the implementation or test expectations.
