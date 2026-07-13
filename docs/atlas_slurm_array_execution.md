# Atlas SLURM-array HYSPLIT execution

This workflow distributes a prepared HYSPLIT manifest across a SLURM array without allowing concurrent tasks to modify shared scenario state. It supplements, and does not replace, the validated single-node workflow.

## Architecture and ownership

The submission command verifies the full manifest's shared meteorology with downloads disabled, classifies durable run state, and writes an immutable array map. Each selected map row becomes one SLURM task. A task acquires only that run's `.execution.lock`, works only in that run directory, and atomically replaces only its own JSON/RDS status shard.

Array workers never write `manifest_execution_ledger.*`, `completed_run_index.*`, the targets store, or meteorology. They never invoke the ordinary targets pipeline. This single-writer rule prevents lost ledger updates and incomplete target snapshots when tasks finish concurrently.

The collector is submitted with `afterany:<array_job_id>`, so partial task failure cannot suppress collection. It validates every shard against its immutable map row and durable run products, writes collection diagnostics, merges the shared ledger once, refreshes the completed-run index, runs the ordinary pipeline twice, and verifies the final state.

## Immutable maps and submission identity

Maps are stored under `local/<scenario>/slurm_array/maps/` in CSV and RDS formats. Rows retain manifest order and have consecutive one-based `array_index` values. A submission ID contains the scenario, UTC creation time, short Git SHA, and a hash of the map, for example `facility_exchange_demo__20260713T180000Z__1a90b4e__a81c29ff`. Existing map files are never overwritten.

Selected durable states map to actions as follows:

| Durable state | Action | Authorization |
|---|---|---|
| `planned`, `ready` | `execute` | execution flag and environment variable |
| `execution_failed` | `retry_execution` | `--retry-failed` plus `EPIPLUME_ALLOW_FAILED_RETRY=true` |
| `parse_failed`, `receptor_failed` | `resume_postprocessing` | `--include-postprocessing`; HYSPLIT is not executed |
| `completed` | excluded | none |

`running`, `invalid`, and `meteorology_blocked` stop map creation. Duplicate manifest or selected run IDs also stop submission.

## Status shards

Each task owns `slurm_array/shards/<submission_id>/<run_id>.json` and `.rds`. It writes a starting shard after acquiring the run lock, then replaces the shard after execution validation, parsing, receptor extraction, and finalization. Failed final shards are retained with a nonzero `task_exit_status` and an `error_message`.

The schema records submission/job/task identity, run/action identity, host and process, repository commit, timestamps and elapsed time, pre/post state, whether HYSPLIT was attempted, attempt counts, durable product paths, objective validation results, dispersion row count, warnings, and error/exit status.

## Submit and monitor

From the Atlas repository checkout:

```bash
./hpc/submit_atlas_hysplit_array.sh \
  --config config/facility_exchange_demo.yml \
  --manifest local/facility_exchange_demo/manifests/hysplit_run_manifest.csv \
  --max-concurrent 10
```

The default concurrency cap is 10. Reduce it when filesystem or scheduler load warrants. Use `--dry-run` to verify meteorology, create and summarize the map, and print the `sbatch` command without submitting jobs. The submission output prints `squeue`, `sacct`, and log-tail commands.

To include postprocessing recovery, add `--include-postprocessing`. To retry inspected execution failures in a new submission and preserve the previous shards:

```bash
EPIPLUME_ALLOW_FAILED_RETRY=true ./hpc/submit_atlas_hysplit_array.sh \
  --config config/facility_exchange_demo.yml \
  --manifest local/facility_exchange_demo/manifests/hysplit_run_manifest.csv \
  --retry-failed --run-ids ID1,ID2
```

## Collection and failure recovery

Collection reports are written beneath `slurm_array/collections/<submission_id>/`. Missing shards, unexpected runs, identity/commit/task mismatches, incomplete starting shards, invalid completed claims, absent parse/receptor products, and failures without diagnostics are recorded deterministically. A collector rerun is idempotent: attempt counts are not lowered and an older failed result cannot replace a valid completed ledger row.

The collector returns nonzero if any mapped task failed or any shard is missing or invalid. Its ordinary pipeline and verification steps still run after shard collection so durable successes remain usable. Correct the underlying failure, submit only affected run IDs as a new submission, and collect again; prior maps, shards, logs, and collection reports remain intact.

## Atlas integration test

Before merging, use a fresh four-run simulated scenario or copied fixture products rather than the already-completed 12-run demonstration. Submit with `--max-concurrent 2`, induce one controlled task failure, and confirm four distinct task logs/shards and no ledger modification before collection. Confirm the first collector records three successes and one failure, retry only the failed run in a new submission, then confirm all four complete. Finally run the ordinary pipeline twice and require `targets::tar_outdated()` to return no targets.
