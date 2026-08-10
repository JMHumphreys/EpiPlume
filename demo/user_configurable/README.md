# User-configurable facility demonstration

This workflow prepares EpiPlume HYSPLIT runs from a facility inventory, a release schedule, and a YAML configuration. The tracked records are synthetic placeholders for workflow testing only; they are not real facilities and have no scientific interpretation.

## Inputs

`facilities.csv` has one facility per row. Required columns are `facility_id`, `facility_name`, `latitude`, and `longitude`. Optional supported columns are `facility_type`, `status`, `event_datetime_utc`, and `notes`. IDs must be unique, whitespace-free, and safe in filenames (`A-Z`, `a-z`, digits, `.`, `_`, and `-`). Coordinates use WGS84 decimal degrees.

`release_schedule.csv` has one source/release per row. `source_facility_id` and `release_datetime_utc` are required. Optional `duration_hours`, `release_height_m`, `particle_count`, `species_id`, and `notes` columns provide run-specific values. A blank override inherits the corresponding `simulation` default from `demo.yml`; blank is never interpreted as zero.

All timestamps must explicitly denote UTC, preferably `YYYY-MM-DDTHH:MM:SSZ`. The equivalent `+00:00` suffix is accepted and normalized to `Z`. Local time and timezone-less timestamps are rejected.

`demo.yml` contains shared simulation, receptor, meteorology, execution, Atlas, and reporting settings. Paths are relative to the repository root. Set `meteorology.meteorology_directory` (or `HYSPLIT_METEOROLOGY_DIRECTORY`) and `execution.hysplit_install_directory` (or the existing HYSPLIT environment configuration) before a real submission. Do not add usernames or personal absolute paths to the tracked template.

## Complete workflow

Edit the CSV and YAML templates, then run from the repository root:

```bash
Rscript scripts/run_user_configurable_demo.R validate --config demo/user_configurable/demo.yml
Rscript scripts/run_user_configurable_demo.R prepare --config demo/user_configurable/demo.yml --dry-run
```

Review `<run-root>/meteorology/meteorology_inventory.csv`. A dry run records missing meteorology and an unresolved HYSPLIT executable without executing or downloading anything. For a submission-ready preparation, remove `--dry-run`; preparation then fails unless the executable resolves and, when configured, all meteorology is ready.

The preparation output prints the exact run root and next commands. On Atlas:

```bash
bash hpc/submit_user_configurable_demo.sh test_runs/user_configurable_demo/<RUN_ID>
squeue -u "$USER"
Rscript scripts/run_user_configurable_demo.R status --run-root test_runs/user_configurable_demo/<RUN_ID>
Rscript scripts/run_user_configurable_demo.R retry-manifest --run-root test_runs/user_configurable_demo/<RUN_ID>
Rscript scripts/run_user_configurable_demo.R report --run-root test_runs/user_configurable_demo/<RUN_ID>
```

The wrapper submits the existing `hpc/atlas_hysplit_array.sbatch` worker and records the array job ID below the prepared run root. The audit writes `combined/run_audit.csv` and `combined/run_status_summary.csv`. The retry manifest excludes `completed_valid` runs; review it before resubmission. The HTML report reads saved artifacts only and is safe to render while runs are incomplete.

Status is deliberately explicit: missing output is not zero exposure. A completed parsed run with receptor rows and no intercepts can support a zero-exposure result; `missing_output`, `parse_failed`, and `receptor_failed` mean the evidence is unavailable. Receptors outside the configured evaluation distance remain distinct when the existing extraction output records that state.

To use real data, replace every placeholder row, retain the headers, validate in UTC, review the normalized copies and manifest under `<run-root>/inputs/`, and confirm source coordinates and meteorology before submitting. Original input files are never modified.
