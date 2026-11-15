# Readread model configuration

These project instructions implement the owner's choice: Astra plans, cheaper models implement and test. `AGENTS.md` explicitly loads these choices; this file does not depend on a globally enabled plugin hook.

planning: gpt-6-astra @high
strongest judgment: gpt-6-astra @high
feature, refactoring: gpt-6.1-sol @high
bug-fix: gpt-6.1-sol @high
swarm workers: gpt-6.1-sol @high
verification: gpt-6-luna @high
default effort: high

Use the session's available model list to validate these names before dispatch. Keep expensive planning bounded; use implementation and verification agents for subsequent repair loops.
