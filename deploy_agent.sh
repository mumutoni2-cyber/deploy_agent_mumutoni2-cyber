
# =============================================================================
# deploy_agent.sh - Automated Project Bootstrapping & Process Management
#
# Three features:
#   1) Deploy   - build attendance_tracker_<name>/ from the templates/ folder
#   2) Run      - start the interactive attendance checker
#   3) Archive  - move the generated logs into timestamped archive folders
#

#!/bin/bash
# Folder that holds this script (so it works from any directory)
scriptDirectory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
templates="$scriptDirectory/templates"

# Set while a deployment is in progress (used by the signal handler)
projectDirectory=""
deploying=""


die() {
    echo "error: $1" >&2
    # If we fail half-way through a deployment, remove the unfinished folder
    [[ -n "$deploying" ]] && rm -rf "$projectDirectory"
    exit 1
}

# Ask for a project name and set projectDirectory (e.g. attendance_tracker_term1)
ask_project_name() {
    read -r -p "What is the project name (used as attendance_tracker_<name>): " name
    [[ -n "$name" ]] || die "Project name cannot be empty."
    [[ "$name" =~ ^[A-Za-z0-9_-]+$ ]] || die "Use only letters, numbers, '-' and '_'."
    projectDirectory="$scriptDirectory/attendance_tracker_$name"
}

# Ask for a whole number between $2 and $3. Result is stored in $replyNum.
ask_number() {
    local prompt="$1" min="$2" max="$3" value
    read -r -p "$prompt ($min-$max): " value
    [[ "$value" =~ ^[0-9]+$ ]] || die "'$value' is not a number."
    (( value >= min && value <= max )) || die "Number must be between $min and $max."
    replyNum=$value
}


handle_interrupt() {
    echo ""
    echo "!! Deployment interrupted. Saving what was created so far..."
    trap - INT TSTP   # avoid running twice if the user presses it again

    if [[ -n "$projectDirectory" && -d "$projectDirectory" ]]; then
        local base zipfile
        base="$(basename "$projectDirectory")"
        zipfile="$scriptDirectory/${base}_archive.zip"
        (cd "$scriptDirectory" && zip -rq "$zipfile" "$base")
        echo "Incomplete project archived to: $zipfile"
        rm -rf "$projectDirectory"  
        echo "Removed the incomplete directory: $base"
    else
        echo "Nothing had been created yet, so there is nothing to archive."
    fi
    echo "Session closed cleanly."
    exit 130
}

# Feature 1: Deploy

preflight_checks() {
    echo "Checking requirements..."
    for tool in python3 zip; do
        command -v "$tool" > /dev/null || die "'$tool' is not installed. Please install it and try again."
    done
    for file in attendance_checker.py assets.csv config.json; do
        [[ -f "$templates/$file" ]] || die "Missing template: templates/$file"
    done
    echo "  python3 and zip found, templates present."
}

# Option A: copy the first N students from the template roster
roster_from_template() {
    local total
    total=$(( $(grep -c . "$templates/assets.csv") - 1 ))  
    ask_number "How many students to copy" 1 "$total"
    head -n $(( replyNum + 1 )) "$templates/assets.csv" > "$projectDirectory/Helpers/assets.csv"
    totalSessions=5   
}

# Option B: build a new roster with zero attendance
roster_generated() {
    local names=(Alice Bob Carol David Eve Frank Grace Heidi Ivan Judy
                 Karl Laura Mike Nina Oscar Paula Quinn Rosa Sam Tina)
    local emails=(alice bob carol david eve frank grace heidi ivan judy
                  karl laura mike nina oscar paula quinn rosa sam tina)
    ask_number "How many students to generate" 1 "${#names[@]}"

    {
        echo "Email,Names,Attendance Count,Absence Count"
        for (( i = 0; i < replyNum; i++ )); do
            echo "${emails[i]}@example.com,${names[i]},0,0"
        done
    } > "$projectDirectory/Helpers/assets.csv"
    totalSessions=1  
}

# Change the "warning" and "failure" numbers in config.json using sed
update_thresholds() {
    local config="$projectDirectory/Helpers/config.json" warn fail
    read -r -p "Update the attendance alert thresholds? (y/n): " answer
    [[ "$answer" =~ ^[Yy]$ ]] || { echo "Keeping default thresholds (75 / 50)."; return; }

    read -r -p "Warning threshold [75]: " warn;  warn=${warn:-75}
    read -r -p "Failure threshold [50]: " fail;  fail=${fail:-50}

    [[ "$warn" =~ ^[0-9]+$ && "$fail" =~ ^[0-9]+$ ]] || die "Thresholds must be whole numbers."
    (( warn <= 100 && fail < warn )) || die "Need: failure < warning <= 100."

    sed -e "s/\"warning\": [0-9]*/\"warning\": $warn/" \
        -e "s/\"failure\": [0-9]*/\"failure\": $fail/" \
        "$config" > "$config.tmp" && cat "$config.tmp" > "$config" && rm "$config.tmp"
    echo "Thresholds updated: warning=$warn, failure=$fail"
}

deploy() {
    preflight_checks
    ask_project_name

    if [[ -e "$projectDirectory" ]]; then
        read -r -p "$(basename "$projectDirectory") already exists. Overwrite? (y/n): " answer
        [[ "$answer" =~ ^[Yy]$ ]] || die "Deployment aborted - directory already exists."
        rm -rf "$projectDirectory"
    fi
    trap handle_interrupt INT TSTP
    deploying=1

    echo "Creating structure..."
    mkdir -p "$projectDirectory/Helpers" "$projectDirectory/reports"
    cp "$templates/attendance_checker.py" "$projectDirectory/"
    cp "$templates/config.json" "$projectDirectory/Helpers/"

    echo "How should the student roster be built?"
    echo "  A) Copy students from the template (4 prior sessions each)"
    echo "  B) Generate a fresh roster (all counts start at 0)"
    read -r -p "Choose A or B: " choice
    case "$choice" in
        [Aa]) roster_from_template ;;
        [Bb]) roster_generated ;;
        *)    die "Invalid choice '$choice'." ;;
    esac

    sed "s/\"total_sessions\": [0-9]*/\"total_sessions\": $totalSessions/" \
        "$projectDirectory/Helpers/config.json" > "$projectDirectory/Helpers/config.json.tmp" \
        && mv "$projectDirectory/Helpers/config.json.tmp" "$projectDirectory/Helpers/config.json"

    # Permissions
    chmod +x "$projectDirectory/attendance_checker.py"
    chmod 600 "$projectDirectory/Helpers/config.json"
    echo "Permissions set:"
    (cd "$projectDirectory" && ls -l attendance_checker.py Helpers/config.json | awk '{print "  " $1, $NF}')

    update_thresholds

    # Setup finished - Ctrl+C now behaves normally again
    trap - INT TSTP
    deploying=""
    echo "Deployment complete: $projectDirectory"

    echo "Verifying by starting the application..."
    run_app "$projectDirectory"
}


# Feature 2: Run
run_app() {
    local dir="$1"
    if [[ -z "$dir" ]]; then
        ask_project_name
        dir="$projectDirectory"
    fi
    [[ -d "$dir" ]] || die "$(basename "$dir") not found. Deploy it first."
    (cd "$dir" && python3 attendance_checker.py)
}


# Feature 3: Archive logs

archive_logs() {
    ask_project_name
    [[ -d "$projectDirectory" ]] || die "$(basename "$projectDirectory") not found."

    local stamp
    stamp="$(date +%Y%m%d_%H%M%S)"
    local archived=0

    for name in attendance absent; do
        local source="$projectDirectory/reports/$name.log"
        local target_dir="$projectDirectory/archives/$name"
        local target="$target_dir/${name}_$stamp.log"

        if [[ -f "$source" ]]; then
            mkdir -p "$target_dir"
            mv "$source" "$target"
            echo "Archived $name.log -> $target"
            archived=$(( archived + 1 ))
        else
            echo "No $name.log found (nothing to archive)."
        fi
    done

    echo "Done: $archived log file(s) archived."
}


# Menu

choice="$1"
if [[ -z "$choice" ]]; then
    echo "========== Deploy Agent ============"
    echo "  1) deploy   - create a new attendance tracker project"
    echo "  2) run      - run the attendance checker"
    echo "  3) archive  - archive the log files"
    read -r -p "Choose 1, 2 or 3: " choice
fi

case "$choice" in
    1|deploy)  deploy ;;
    2|run)     run_app ;;
    3|archive) archive_logs ;;
    *)         die "Unknown option '$choice'. Use deploy, run or archive." ;;
esac
