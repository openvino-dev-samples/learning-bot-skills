# Best Practices, Pitfalls & Checklist (local AI skill packaging)

> Imported from `local-ai-skill-authoring`.

## Exit code convention

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error (bad args, no permission, unsupported hardware) |
| 2 | Connection / communication error |
| 3 | Model downloading — needs `--continue` |

## Logging

Write logs to a per-host log dir (Marvis: `%USERPROFILE%\.openvino\log\`):
- PowerShell: `<skill>-client-<timestamp>.log`
- Python client: `<skill>-client-py-<timestamp>.log`
- Python server: `<skill>-server-py-<timestamp>.log`

Format: `[YYYY-MM-DD HH:MM:SS] [<role> pid=<PID>] <message>`. Use absolute paths, never relative.

## UTF-8 encoding (mandatory)

Every Python script must configure UTF-8 at startup or Chinese output is garbled:

```python
def _configure_stream_encoding(stream) -> None:
    reconfigure = getattr(stream, "reconfigure", None)
    if callable(reconfigure):
        reconfigure(encoding="utf-8")

_configure_stream_encoding(sys.stdout)
_configure_stream_encoding(sys.stderr)
```

## Best practices

1. Keep the exact directory layout; no runtime files in root, no extra nesting.
2. Prefer INT4/INT8 OpenVINO models; publish publicly (e.g. ModelScope).
3. GPU-first device selection, CPU fallback.
4. Declare accurate `mem_need_gb`.
5. On server init failure set `state="error"` + full traceback; client retries (e.g. `ERROR_RETRY_MAX=3`, shutdown then restart).
6. Hot-update safe: run server from the temp copy; hash-compare to auto-restart; no hardcoded absolute paths into the install dir.
7. Bilingual triggers in SKILL.md; Chinese user-facing output; English logs/internal errors.
8. Write `tests/test.ps1` (E2E on real hardware); mock pipe/model in unit tests; `tests/tui_test.py` for interactive testing.

## Common pitfalls

| Pitfall | Note |
|---------|------|
| Renaming `run.ps1` | Host hardcodes the name — must keep |
| Forgetting UTF-8 | Chinese output garbled |
| Downloading to final dir | Must use `.partial` + atomic rename |
| Spawning server directly (Marvis) | Go through the process manager for memory mgmt + host-exit cleanup |
| `$ErrorActionPreference` unset | PowerShell scripts must start with `$ErrorActionPreference = 'Stop'` |
| Relative log paths | Always use absolute paths under the host base dir |
| Mismatched pipe authkey | Client and server must use the same authkey |
| Wrong OpenVINO version | Some optimum-intel / model code needs a specific OpenVINO; pin it and verify `import` paths |

## Build checklist

- [ ] `info.json` `models` list correct (one entry per pipeline stage IR)
- [ ] `SKILL.md` frontmatter has full bilingual triggers
- [ ] `meta.json` `use_cases` covers typical scenarios
- [ ] `requirements.txt` pins critical versions
- [ ] `run.ps1` first line does hardware detection (host-specific)
- [ ] First-run download works, including `--continue`
- [ ] Unsupported hardware prints the platform error and exits 1
- [ ] Logs are clean, no secrets leaked
