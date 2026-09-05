# DeepSeek Provider Migration Design

## Goal

Replace the AI Frontier Radar workflow's OpenAI dependency with DeepSeek so the daily Chinese digest can run without OpenAI API credits. Preserve GitHub Pages deployment and synchronize the expanded AI designer growth report into its dedicated D-drive folder.

## Selected Approach

Use Horizon's native `deepseek` provider with the current low-cost general model `deepseek-v4-flash` and DeepSeek's OpenAI-compatible endpoint. This is preferred over `deepseek-v4-pro` because the workload makes many classification and analysis calls each day, where lower latency and cost matter more than maximum reasoning depth. A multi-provider fallback is excluded because the existing OpenAI account has no API balance and would add configuration without providing a working fallback.

## Configuration

- Set `ai.provider` to `deepseek`.
- Set `ai.model` to `deepseek-v4-flash`.
- Set `ai.api_key_env` to `DEEPSEEK_API_KEY`.
- Use Horizon's built-in DeepSeek base URL, `https://api.deepseek.com`.
- Keep the existing temperature, token limit, language, concurrency, source, profile, quota, and digest settings unchanged.
- Pass `DEEPSEEK_API_KEY` from the GitHub Actions secret into the Horizon execution step.
- Leave the existing `OPENAI_API_KEY` repository secret unused; removing it is outside this migration and can be done separately.

## Secret Handling

Read the DeepSeek key from the Windows clipboard, validate that it is a non-empty single line, pipe it directly to GitHub CLI as the `DEEPSEEK_API_KEY` Actions secret, and clear the clipboard immediately. The key must never be printed, committed, written to a local file, or included in command output.

## Runtime Flow

The scheduled or manually dispatched workflow checks out the repository, loads `data/config.github.json`, exposes `DEEPSEEK_API_KEY`, and runs Horizon. Horizon uses its existing DeepSeek/OpenAI-compatible client for classification, scoring, and localized enrichment. The creator Top 3 postprocessor then operates on the generated Chinese report, after which the workflow deploys `docs` to `gh-pages`. The local scheduled PowerShell task fetches the latest report into `D:\obsidian\人工智能尝试\AI行业热点日报` using the dated filename defined by the AI Designer Growth Radar specification.

## Failure Handling

- A missing or invalid DeepSeek secret must fail the AI step with an authentication error.
- An exhausted DeepSeek balance must remain visible in the workflow logs rather than silently publishing an empty report.
- The creator postprocessor continues to reject a report with no eligible items, preventing an empty daily page from being deployed.
- No fallback to the unfunded OpenAI account is configured.

## Verification

1. Add or update configuration tests to assert the DeepSeek provider, model, and secret wiring.
2. Run the targeted configuration and workflow tests, followed by the relevant full test suite.
3. Scan tracked files for API-key patterns and confirm the worktree contains no secret material.
4. Push the branch, merge through a pull request, and manually dispatch the daily workflow.
5. Confirm the workflow selects non-zero items, adds exactly one Top 3 section, and deploys `gh-pages`.
6. Enable or verify GitHub Pages, confirm the public report loads, then run the Obsidian sync twice and verify the second run is unchanged.

## Success Criteria

The GitHub Actions run succeeds using `deepseek-v4-flash`, a Chinese AI Designer Growth Radar report is publicly available through GitHub Pages, and the same dated Markdown report exists in `D:\obsidian\人工智能尝试\AI行业热点日报`.
