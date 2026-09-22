## Codex delegation

Codex is installed locally and is the dedicated worker for:
- game assets
- icons
- textures
- sound effects
- music

When the user asks for these, delegate the production work to Codex using `codex exec`.

Do not use Codex for normal gameplay/programming tasks unless explicitly requested.

Give Codex only the context required for the task.

Codex must write its output under:
.codex-output/

After Codex completes:
- inspect the produced files
- integrate suitable files into the game
- run the relevant project checks
- report the final result to the user

Do not repeatedly call Codex on the same task without a concrete reason.
