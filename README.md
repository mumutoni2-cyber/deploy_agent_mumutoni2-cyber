The link to the video explaining how I worked on the project .

(https://www.loom.com/share/7fc1f51d5a8144bba2130b81d7d11855)


# Deploy Agent

`deploy_agent.sh` attendance tracker project from the files in `templates/`, runs it, and archives its logs.

## Requirements

- `bash`, `python3`, `zip`
- A `templates/` folder next to the script containing `attendance_checker.py`, `assets.csv` and `config.json`

## Running the script and selecting a feature

```bash
chmod +x deploy_agent.sh
./deploy_agent.sh
```

With no argument you get a menu:

```
========== Deploy Agent ============
  1) deploy   - create a new attendance tracker project
  2) run      - run the attendance checker
  3) archive  - archive the log files
Choose 1, 2 or 3:
```

You can also skip the menu by passing the feature as an argument: `./deploy_agent.sh deploy` (or `1`), `./deploy_agent.sh run` (or `2`), `./deploy_agent.sh archive` (or `3`).

Each feature asks for a project name (letters, numbers, `-`, `_`) and works on `attendance_tracker_<name>/`.

### Deploy creates this structure

```
attendance_tracker_<name>/
├── attendance_checker.py     (chmod +x)
├── Helpers/
│   ├── assets.csv            student roster
│   └── config.json           (chmod 600)
└── reports/                  attendance.log / absent.log are written here
```

During deploy you choose the roster: **A** copies the first N students from the template (5 total sessions), **B** generates a fresh roster with all counts at 0 (1 session). At the end the app is started once to verify the deployment.

## How the threshold update works

After the structure is built, deploy asks `Update the attendance alert thresholds? (y/n)`.

- **n**: defaults stay (warning 75, failure 50).
- **y**: you're prompted for a warning and a failure value (Enter keeps the default). Both must be whole numbers with `failure < warning <= 100`, otherwise the deploy aborts and the unfinished folder is removed.

The values are edited in place in `Helpers/config.json` with `sed`, which replaces the numbers after `"warning":` and `"failure":`. The result goes to a temporary file that then replaces the original.

## How log archiving works

Choose **archive** and enter the project name. For each of `attendance.log` and `absent.log` in `reports/`, the script moves the file into its own archive directory and adds a timestamp to the name:

```
attendance_tracker_<name>/
├── reports/                      (logs are moved out of here)
└── archives/
    ├── attendance/attendance_YYYYMMDD_HHMMSS.log
    └── absent/absent_YYYYMMDD_HHMMSS.log
```

Example: `archives/attendance/attendance_20261013_223719.log`. Both logs from one run share the same timestamp. A log that doesn't exist is skipped with a message. Because the files are moved, `reports/` is empty afterwards and the next run of the checker starts fresh logs.

## Testing the Ctrl+C / Ctrl+Z path

While deploying, the script traps `INT` (Ctrl+C) and `TSTP` (Ctrl+Z). Once setup finishes, the trap is removed, so Ctrl+C then behaves normally.

1. Run `./deploy_agent.sh deploy` and enter a project name, e.g. `test`.
2. At any later prompt (the A/B roster choice or the threshold questions), press **Ctrl+C** (or **Ctrl+Z**).
3. Expected output:
   ```
   !! Deployment interrupted. Saving what was created so far...
   Incomplete project archived to: .../attendance_tracker_test_archive.zip
   Removed the incomplete directory: attendance_tracker_test
   Session closed cleanly.
   ```
4. Check the results:
   ```bash
   ls                                          # no attendance_tracker_test/, but the .zip exists
   unzip -l attendance_tracker_test_archive.zip
   ```

If you interrupt before the project folder exists (e.g. at the name prompt), you get "Nothing had been created yet" and no zip. The script exits with status 130.

### What the .zip contains

A snapshot of the partially built project at the moment of the interrupt, with `attendance_tracker_<name>/` as the top-level folder. Depending on how far deployment got, that is some or all of:

- `attendance_checker.py`
- `Helpers/config.json`
- `Helpers/assets.csv` (only if the roster step was reached)
- the empty `reports/` directory

The unzipped folder is then deleted, so the zip is the only copy.

## Testing the deployed application structure

After a normal deploy, verify the structure like this:

```bash
./deploy_agent.sh deploy                    # name: 1, roster option A or B, answer y to thresholds
cd attendance_tracker_1
ls -R                                       # attendance_checker.py, Helpers/{assets.csv,config.json}, reports/
ls -l attendance_checker.py Helpers/config.json   # -rwx... for the script, -rw------- for config
cat Helpers/config.json                     # warning/failure match what you entered; total_sessions is 5 (A) or 1 (B)
head Helpers/assets.csv                     # header + the chosen number of students
```

Then check that the app works end to end:

1. The deploy finishes by launching `attendance_checker.py`. Confirm it starts and writes `reports/attendance.log` and `reports/absent.log`.
2. Run `./deploy_agent.sh archive` with the same name and confirm the two timestamped files appear under `archives/attendance/` and `archives/absent/`, and `reports/` is empty.
3. Re-run deploy with the same name and confirm the overwrite prompt appears, and that answering `n` aborts without touching the existing folder.
4. Try bad input (a name with spaces, a non-numeric student count, `failure >= warning`) and confirm each is rejected with an `error:` message.
