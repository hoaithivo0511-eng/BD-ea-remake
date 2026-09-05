# T17.17 Verify Report

## Runtime baseline — exact-head PASS

| Gate | Result |
|---|---:|
| Remote HEAD | `b87bd3cf3d3a1c23d748ed0b4addb95a8ea376b4` |
| Remote TREE | `2c1940de27fd6547eee17eb6c34683292c0d189e` |
| Workflow run | `33270273234` |
| Model/source job | `99147403114` PASS |
| Native/MetaEditor job | `99147403240` PASS |
| C++ model regression | 37/37 suites PASS |
| Source contracts T17.11–T17.17 | 7/7 PASS |
| MetaEditor ProbeEA/full EA/native scripts | 0 errors / 0 warnings |
| Native T17.17 | 16/0 PASS |
| Native matrix at that baseline | 25/25 suites PASS |
| Artifact | `blackdragon-t1717-final-owner-qa`, ID `9719955627` |
| Artifact ZIP SHA256 | `25cfa95cdfe2891b613fccc7d0d76baef70002935724887599ac0196522a8fed` |
| BlackDragon.ex5 | 668824 bytes, SHA256 `85db97f43450129f30a5247b78c88a625e11e0fe9f3b6933d1db411428746d55` |

This is exact evidence for the pre-cleanup runtime baseline. It is not a
Strategy Tester result.

## Repository hygiene exact-head gate — pending

The cleanup tree keeps T17.17 trading semantics but changes repository paths,
CI coverage and Panel version text. The new canonical workflow must therefore
run again on its own exact GitHub HEAD/TREE.

Required result:

- repository contract PASS;
- 37/37 C++ suites and seven source contracts PASS;
- ProbeEA, full EA and 27/27 native scripts compile 0/0;
- all 27 native scripts run `ALL GREEN`;
- exact HEAD/TREE/repository/job/runner/toolchain/source/staged/EX5 hashes;
- artifact `blackdragon-current-owner-qa`.

Owner Strategy Tester remains `PENDING_OWNER`. Forward/live remain false,
and PR #28 remains Draft.
