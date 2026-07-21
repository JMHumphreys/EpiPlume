# Atlas SLURM-array HYSPLIT execution

GitHub repository [`JMHumphreys/EpiPlume`](https://github.com/JMHumphreys/EpiPlume) is the authoritative source for Atlas code. Commit and push changes from the development checkout, then pull committed changes on Atlas. Do not manually patch tracked scripts on Atlas.

## Atlas environment

Create the ignored, machine-specific configuration once:

```bash
cd /project/hpai_plume/EpiPlume
cp config/atlas.env.example config/atlas.env
${EDITOR:-vi} config/atlas.env
```

The file must define:

- `EPIPLUME_REPO_DIR`: Atlas checkout directory.
- `EPIPLUME_R_LIBS_USER`: personal R 4.5 library containing `splitr`.
- `EPIPLUME_HYSPLIT_INSTALL_DIRECTORY`: directory containing native `hycs_std` and `parhplot`.
- `EPIPLUME_SLURM_ACCOUNT`: allocation passed to `sbatch`.
- `EPIPLUME_GCC_MODULE`: Atlas GCC module.
- `EPIPLUME_R_MODULE`: Atlas R module.

Set `EPIPLUME_ATLAS_ENV_FILE` to use a different environment file. Values already exported as `EPIPLUME_*` override file values. The shared loader deliberately unsets inherited `R_LIBS` and replaces any unrelated inherited `R_LIBS_USER` with `EPIPLUME_R_LIBS_USER`; this prevents another project's library, such as an inherited login environment, from hiding the EpiPlume `splitr` installation.

The loader purges and loads GCC, udunits, GDAL, PROJ, GEOS, Git, and R. It verifies that R can load `splitr`. Execution scripts also verify that `hycs_std` and `parhplot` exist, are executable Linux ELF binaries, and have no unresolved shared libraries. The collector loads the same module and R library environment but skips HYSPLIT binary preflight because it does not execute HYSPLIT.

Use a native RHEL 9 HYSPLIT build. The repository convention is:

```text
/project/hpai_plume/EpiPlume/software/hysplit-atlas/exec/hycs_std
/project/hpai_plume/EpiPlume/software/hysplit-atlas/exec/parhplot
```

Windows `.exe` binaries and binaries copied from incompatible Linux distributions are not valid Atlas installations.

## Architecture and ownership

The submitter verifies shared meteorology with downloads disabled, classifies durable run state, and writes an immutable array map. Each selected map row becomes one SLURM task. A worker acquires only that run's `.execution.lock`, modifies only its run directory, and atomically replaces only its own JSON/RDS status shard.

Workers never write `manifest_execution_ledger.*`, `completed_run_index.*`, the targets store, or meteorology. The collector is submitted with `afterany:<array_job_id>`, so task failure cannot suppress collection. It validates shards and durable products, merges shared state once, refreshes the completed-run index, runs the ordinary pipeline twice, and verifies final state.

Maps, shards, logs, and collection products all live beneath the configured scenario output root:

```text
<root>/slurm_array/maps/
<root>/slurm_array/shards/<submission_id>/
<root>/slurm_array/logs/
<root>/slurm_array/collections/<submission_id>/
```

Submission IDs contain the scenario, UTC creation time, short Git SHA, and map hash. Existing maps are never overwritten.

| Durable state | Action | Authorization |
|---|---|---|
| `planned`, `ready` | `execute` | execution flag and environment variable |
| `execution_failed` | `retry_execution` | `--retry-failed` and `EPIPLUME_ALLOW_FAILED_RETRY=true` |
| `parse_failed`, `receptor_failed` | `resume_postprocessing` | `--include-postprocessing`; no HYSPLIT execution |
| `completed` | excluded | none |

`running`, `invalid`, and `meteorology_blocked` stop map creation. Duplicate manifest or selected run IDs also stop submission.

## Pull committed changes on Atlas

First confirm that Atlas has no uncommitted tracked edits, then align it with GitHub:

```bash
cd /project/hpai_plume/EpiPlume
git status --short
git fetch origin
git switch feature/slurm-array-run-shards
git reset --hard origin/feature/slurm-array-run-shards
```

The hard reset is intentional only for the clean Atlas code checkout: GitHub is authoritative. Ignored scenario products remain in place.

## One-run dry test and execution

Choose one inspected `planned` or `ready` run. The dry run performs environment and HYSPLIT preflight, verifies meteorology, writes the immutable map, and prints both `sbatch` commands without submitting:

```bash
./hpc/submit_atlas_hysplit_array.sh \
  --config config/facility_exchange_demo.yml \
  --manifest local/facility_exchange_demo/manifests/hysplit_run_manifest.csv \
  --run-ids INSPECTED_RUN_ID \
  --max-concurrent 1 \
  --dry-run
```

Review the map summary and printed paths. Then submit only that same task:

```bash
./hpc/submit_atlas_hysplit_array.sh \
  --config config/facility_exchange_demo.yml \
  --manifest local/facility_exchange_demo/manifests/hysplit_run_manifest.csv \
  --run-ids INSPECTED_RUN_ID \
  --max-concurrent 1
```

Do not start a four-run retry until this task and its collector have been reviewed.

For one previously failed run, inspect its shard, logs, run metadata, and execution lock first. A deliberate retry requires both safeguards:

```bash
EPIPLUME_ALLOW_FAILED_RETRY=true ./hpc/submit_atlas_hysplit_array.sh \
  --config config/facility_exchange_demo.yml \
  --manifest local/facility_exchange_demo/manifests/hysplit_run_manifest.csv \
  --run-ids INSPECTED_FAILED_RUN_ID \
  --retry-failed \
  --max-concurrent 1 \
  --dry-run
```

Remove `--dry-run` only after reviewing its output.

## Monitor and recover

The submitter prints the array and collector job IDs. Inspect both together:

```bash
squeue -j ARRAY_JOB_ID,COLLECTOR_JOB_ID
sacct -j ARRAY_JOB_ID,COLLECTOR_JOB_ID --format=JobID,State,Elapsed,MaxRSS,ExitCode
tail -f <scenario-root>/slurm_array/logs/ARRAY_JOB_ID_*.out
tail -f <scenario-root>/slurm_array/logs/collect_COLLECTOR_JOB_ID.out
```

The submitted-job record is written to `<scenario-root>/slurm_array/collections/<submission_id>_submitted_jobs.txt`. Collection diagnostics are under `<scenario-root>/slurm_array/collections/<submission_id>/`.

The collector returns nonzero for failed, missing, or invalid shards, while retaining valid durable results. Preserve all failed historical submissions, maps, shards, logs, and collection reports. Correct the cause and create a new submission for only the inspected affected run; never overwrite or delete the earlier evidence.

Whole-manifest verification is written to `final_verification.log` as an informational check. An incomplete historical run outside the submitted array produces a warning but does not make an otherwise successful collector fail. Set `EPIPLUME_STRICT_MANIFEST_VERIFICATION=true` before submission only when the collector should require completion of the entire configured manifest.
