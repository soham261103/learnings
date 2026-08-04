# Shell Scripting — Learn, Remember, Master

link for linux fundamentals : https://github.com/iam-veeramalla/ultimate-linux-guide/tree/main
> **Goal:** Go from zero to writing production-ready bash scripts.  
> **How to use this guide:** Read one section, run every example, then do the practice at the end.  
> **Primary shell:** Bash (`#!/bin/bash`) — the most common shell for scripting on Linux, macOS, WSL, and Git Bash.

---

## Table of Contents

1. [What Is Shell Scripting?](#1-what-is-shell-scripting)
2. [Your First Script](#2-your-first-script)
3. [How the Shell Thinks (Mental Model)](#3-how-the-shell-thinks-mental-model)
4. [Variables](#4-variables)
5. [Quoting — The #1 Source of Bugs](#5-quoting--the-1-source-of-bugs)
6. [Command Substitution & Expansion](#6-command-substitution--expansion)
7. [Arithmetic & Comparisons](#7-arithmetic--comparisons)
8. [Conditionals (if / case)](#8-conditionals-if--case)
9. [Loops](#9-loops)
10. [Functions](#10-functions)
11. [Input, Output & Pipes](#11-input-output--pipes)
12. [Arrays](#12-arrays)
13. [String Manipulation](#13-string-manipulation)
14. [Working with Files & Directories](#14-working-with-files--directories)
15. [Exit Codes & Error Handling](#15-exit-codes--error-handling)
16. [Debugging Scripts](#16-debugging-scripts)
17. [Script Arguments & Flags](#17-script-arguments--flags)
18. [Best Practices for Production Scripts](#18-best-practices-for-production-scripts)
19. [Real-World Patterns](#19-real-world-patterns)
20. [Quick Reference Cheat Sheet](#20-quick-reference-cheat-sheet)
21. [Practice Exercises](#21-practice-exercises)

---

## 1. What Is Shell Scripting?

A **shell** is a program that reads your commands and runs them. A **shell script** is a text file of commands the shell executes in order — like a recipe.

| Shell   | Notes |
|---------|-------|
| `bash`  | Most popular for scripting. Feature-rich. **Use this.** |
| `sh`    | POSIX shell. Minimal. On many Linux distros, `/bin/sh` → `dash` (not bash). |
| `dash`  | Fast, minimal. Used as `/bin/sh` on Debian/Ubuntu. |
| `zsh`   | Default on modern macOS. Bash-compatible for most scripts. |
| `ksh`   | Korn shell. Older enterprise systems. |

**File extension:** `.sh` (convention, not required)

**Remember:** Write `#!/bin/bash` at the top. Don't assume `/bin/sh` is bash — on modern Linux, `/bin/sh` is often `dash`, which lacks many bash features.

---

## 2. Your First Script

```bash
#!/bin/bash
# This is a comment — the shell ignores it

echo "Hello, World!"
echo "My name is $USER"
```

### Shebang (`#!`)

The first line `#!/bin/bash` tells the OS: *"Run this file with bash."*

| Line | Name | Purpose |
|------|------|---------|
| `#!` | Shebang | Magic bytes that mark an executable script |
| `/bin/bash` | Interpreter path | Which program runs the script |

### Three Ways to Run a Script

```bash
# 1. Make executable, then run directly (preferred)
chmod +x myscript.sh
./myscript.sh

# 2. Explicitly invoke bash
bash myscript.sh

# 3. Use sh (only if script is POSIX-compatible)
sh myscript.sh
```

**Remember the order:**
1. **Write** the script
2. **chmod +x** (only needed for `./script.sh`)
3. **Run** it

---

## 3. How the Shell Thinks (Mental Model)

Before variables and loops, understand the **execution pipeline**:

```
You type a command
       ↓
Shell parses it (splits words, expands variables)
       ↓
Shell finds the program (PATH lookup)
       ↓
Program runs → returns exit code (0 = success, non-zero = failure)
       ↓
Shell moves to next line (or handles if/loop logic)
```

### Key Concepts to Internalize

| Concept | Meaning | Memory trick |
|---------|---------|--------------|
| **Command** | A program name + arguments: `ls -la /tmp` | Verb + options + target |
| **Exit code** | Number returned when a command finishes | **0 = OK**, anything else = problem |
| **STDOUT** | Normal output (file descriptor 1) | What you see |
| **STDERR** | Error output (file descriptor 2) | Error messages |
| **STDIN** | Input (file descriptor 0) | What you type or pipe in |
| **Pipeline** | `cmd1 \| cmd2` — stdout of cmd1 → stdin of cmd2 | Assembly line |

```bash
# See the exit code of the last command
ls /tmp
echo $?          # 0 if ls succeeded

ls /nonexistent
echo $?          # 2 (or other non-zero)
```

---

## 4. Variables

### Declaring and Using

```bash
name="Soham"           # No spaces around =
age=25                 # Numbers don't need quotes
readonly PI=3.14       # Cannot be changed
unset temp_var         # Delete a variable

echo "Hello, $name"    # Hello, Soham
echo "Hello, ${name}"  # Same — braces required for clarity
```

**Remember:** `VAR=value` — **no spaces** around `=`.  
`VAR = value` is wrong — the shell tries to run `VAR` as a command.

### Special Variables (Memorize These)

| Variable | Meaning |
|----------|---------|
| `$0` | Script name |
| `$1`, `$2`, ... | Positional arguments |
| `$#` | Number of arguments |
| `$@` | All arguments as separate words |
| `$*` | All arguments as one string |
| `$?` | Exit code of last command |
| `$$` | Current process ID (PID) |
| `$!` | PID of last background job |
| `$HOME` | User's home directory |
| `$PWD` | Current directory |
| `$USER` / `$USERNAME` | Current username |
| `$PATH` | Directories searched for commands |

```bash
#!/bin/bash
echo "Script: $0"
echo "First arg: $1"
echo "Total args: $#"
echo "All args: $@"
```

### Environment Variables

```bash
export MY_VAR="visible to child processes"
env | grep MY_VAR

# Set for one command only
MY_VAR=hello ./other_script.sh
```

**Remember:** `export` makes a variable available to programs your script launches.

### Local Variables in Functions

```bash
my_func() {
    local count=0    # Only exists inside this function
    count=$((count + 1))
    echo $count
}
```

---

## 5. Quoting — The #1 Source of Bugs

| Quote type | Behavior |
|------------|----------|
| **No quotes** | Shell splits on spaces and expands variables |
| **Single `'...'`** | Literal — nothing is expanded |
| **Double `"..."`** | Variables and `$()` expand; spaces preserved |

```bash
name="John Doe"

# WRONG — word splitting breaks it
echo $name          # prints: John Doe (works here by luck)
files=$(ls *.txt)   # breaks if filenames have spaces

# RIGHT
echo "$name"        # John Doe
echo '$name'        # literal: $name

# WRONG
echo "File count: $(ls *.txt | wc -l)"   # fragile

# RIGHT — always quote variable expansions
for f in *.txt; do
    echo "Processing: $f"
done
```

**Golden rule:** *Always double-quote variable expansions unless you have a specific reason not to.*

```bash
# Safe pattern
cp "$source" "$destination"
rm -f "$file"
echo "User is: $USER"
```

---

## 6. Command Substitution & Expansion

### Command Substitution — Run a Command, Capture Output

```bash
# Modern style (preferred)
today=$(date +%Y-%m-%d)
files=$(ls /tmp)

# Old style (avoid in new scripts)
today=`date +%Y-%m-%d`
```

### Brace Expansion

```bash
echo {a,b,c}          # a b c
echo file{1,2,3}.txt  # file1.txt file2.txt file3.txt
echo {1..5}           # 1 2 3 4 5
mkdir -p project/{src,tests,docs}
```

### Pathname (Glob) Expansion

```bash
ls *.sh               # All .sh files
ls file?.txt          # file1.txt, fileA.txt (one char)
ls file[0-9].txt      # file0.txt through file9.txt
ls file[!0-9].txt     # NOT starting with digit
```

**Remember:** Globs don't match hidden files (starting with `.`) unless you include the dot: `.*`

### Arithmetic Expansion

```bash
echo $((3 + 5))       # 8
echo $((10 / 3))      # 3 (integer division)
```

---

## 7. Arithmetic & Comparisons

### Arithmetic — Use `$(( ))`

```bash
a=10
b=3

echo $((a + b))       # 13
echo $((a - b))       # 7
echo $((a * b))       # 30
echo $((a / b))       # 3
echo $((a % b))       # 1
echo $((a ** 2))      # 100 (exponent — bash 4+)

# Increment
((a++))
((a += 5))
```

### String Comparisons — Use `[[ ]]` (bash built-in)

```bash
name="admin"

[[ "$name" == "admin" ]]    && echo "match"
[[ "$name" != "guest" ]]    && echo "not guest"
[[ -z "$name" ]]             # True if empty
[[ -n "$name" ]]             # True if NOT empty
[[ "$str1" < "$str2" ]]      # Lexicographic compare
```

### Numeric Comparisons — Inside `(( ))` or `[[ ]]`

```bash
num=10

# Using (( )) — no $ needed for variables
(( num > 5 ))    && echo "greater"
(( num == 10 ))  && echo "equals ten"

# Using [[ ]] with -eq, -ne, -lt, -gt, -le, -ge
[[ $num -gt 5 ]]  && echo "greater"
```

| Test | Meaning | Use for |
|------|---------|---------|
| `-eq` | Equal | Numbers |
| `-ne` | Not equal | Numbers |
| `-lt` | Less than | Numbers |
| `-gt` | Greater than | Numbers |
| `-le` | Less or equal | Numbers |
| `-ge` | Greater or equal | Numbers |
| `==` | Equal | Strings (in `[[ ]]`) |
| `!=` | Not equal | Strings |

**Remember:** `-eq` is for **numbers**, `==` is for **strings**. Don't mix them.

### File Tests — Extremely Useful

```bash
file="/etc/passwd"

[[ -f "$file" ]]    # Regular file exists
[[ -d "$file" ]]    # Directory exists
[[ -e "$file" ]]    # Anything exists
[[ -r "$file" ]]    # Readable
[[ -w "$file" ]]    # Writable
[[ -x "$file" ]]    # Executable
[[ -s "$file" ]]    # Non-empty file
[[ ! -f "$file" ]]  # Does NOT exist
```

---

## 8. Conditionals (if / case)

### if / elif / else

```bash
#!/bin/bash

read -p "Enter a number: " num

if (( num > 100 )); then
    echo "Large number"
elif (( num > 10 )); then
    echo "Medium number"
else
    echo "Small number"
fi
```

```bash
# File check pattern (use this constantly)
if [[ -f "$config_file" ]]; then
    source "$config_file"
else
    echo "Config not found: $config_file" >&2
    exit 1
fi
```

### Combining Conditions

```bash
# AND
if [[ -f "$file" && -r "$file" ]]; then
    echo "Readable file"
fi

# OR
if [[ "$env" == "prod" || "$env" == "staging" ]]; then
    echo "Non-dev environment"
fi

# NOT
if [[ ! -d "$dir" ]]; then
    mkdir -p "$dir"
fi
```

### case — Pattern Matching (Like switch)

```bash
read -p "Action (start|stop|restart): " action

case "$action" in
    start)
        echo "Starting service..."
        ;;
    stop)
        echo "Stopping service..."
        ;;
    restart)
        echo "Restarting..."
        ;;
    *)
        echo "Unknown action: $action" >&2
        exit 1
        ;;
esac
```

**Remember:** Every `case` branch ends with `;;`. The `*)` branch is the default (like `default:` in other languages).

---

## 9. Loops

### for — Iterate Over a List

```bash
# Over explicit list
for fruit in apple banana cherry; do
    echo "I like $fruit"
done

# Over command output
for user in $(cut -d: -f1 /etc/passwd); do
    echo "User: $user"
done

# C-style for loop
for ((i = 0; i < 5; i++)); do
    echo "Count: $i"
done
```

### while — Loop While Condition Is True

```bash
count=0
while (( count < 5 )); do
    echo "Count: $count"
    ((count++))
done
```

```bash
# Read file line by line (safe method)
while IFS= read -r line; do
    echo "Line: $line"
done < "$input_file"
```

**Remember:** `IFS= read -r line` prevents backslash issues and respects line boundaries.

### until — Loop Until Condition Is True

```bash
count=0
until (( count >= 5 )); do
    echo "Count: $count"
    ((count++))
done
```

### Loop Control

```bash
for i in {1..10}; do
    [[ $i -eq 5 ]] && continue    # skip 5
    [[ $i -eq 8 ]] && break       # stop at 8
    echo $i
done
```

| Loop | Use when |
|------|----------|
| `for` | You know the list or count upfront |
| `while` | Condition-based; reading streams |
| `until` | Waiting for something to become true |

---

## 10. Functions

```bash
#!/bin/bash

# Basic function
greet() {
    echo "Hello, $1!"
}

greet "World"    # Hello, World!

# Function with local variables and return value
is_even() {
    local num=$1
    (( num % 2 == 0 ))
    return $?    # 0 = true, 1 = false
}

if is_even 4; then
    echo "4 is even"
fi
```

### Return Values — Two Different Meanings

```bash
# 1. Exit code (0-255) — for success/failure
check_file() {
    [[ -f "$1" ]]
    return $?
}

# 2. stdout — for returning data
get_timestamp() {
    date +%Y-%m-%d_%H:%M:%S
}

ts=$(get_timestamp)
echo "Now: $ts"
```

**Remember:**
- `return` sets the **exit code** (0 = success). Only 0-255.
- To return **text/data**, use `echo` and capture with `$()`.

```bash
# Function template to copy
my_function() {
    local arg1=$1
    local arg2=$2

    # validate
    if [[ -z "$arg1" ]]; then
        echo "Error: arg1 required" >&2
        return 1
    fi

    # do work
    echo "result"
    return 0
}
```

---

## 11. Input, Output & Pipes

### Redirecting Output

```bash
echo "log entry" > log.txt       # Overwrite file
echo "more" >> log.txt           # Append to file
echo "error" >&2                 # Write to stderr
command &> all_output.txt        # Redirect stdout + stderr
command > out.txt 2>&1           # Same (POSIX style)
```

### Redirecting Input

```bash
wc -l < file.txt                 # Read from file
while read -r line; do
    echo "$line"
done < input.txt
```

### Pipes

```bash
# Chain commands
cat access.log | grep "ERROR" | sort | uniq -c | sort -rn

# pipefail — fail if ANY command in pipeline fails
set -o pipefail
false | true
echo $?    # 1 (without pipefail, this would be 0)
```

### Here Documents — Inline Input

```bash
cat << EOF
This is a multi-line
block of text.
Current user: $USER
EOF
```

### Here Strings (bash 4+)

```bash
grep "pattern" <<< "$variable_content"
```

### Reading User Input

```bash
read -p "Enter your name: " name
read -s -p "Password: " password    # -s = silent (no echo)
echo
read -t 5 -p "Quick! Enter something (5s): " input   # timeout
```

---

## 12. Arrays

```bash
# Indexed array
fruits=("apple" "banana" "cherry")
echo "${fruits[0]}"          # apple
echo "${fruits[@]}"          # all elements
echo "${#fruits[@]}"         # count: 3

# Add element
fruits+=("date")

# Loop over array
for fruit in "${fruits[@]}"; do
    echo "$fruit"
done
```

```bash
# Associative array (bash 4+) — like a dictionary/map
declare -A colors
colors[red]="#FF0000"
colors[green]="#00FF00"
colors[blue]="#0000FF"

for key in "${!colors[@]}"; do
    echo "$key → ${colors[$key]}"
done
```

**Remember:** Always quote `"${array[@]}"` when looping — preserves elements with spaces.

---

## 13. String Manipulation

Bash has built-in string operations — no need for `sed` for simple tasks.

```bash
str="Hello, World!"

# Length
echo "${#str}"                    # 13

# Substring
echo "${str:0:5}"                 # Hello
echo "${str:7}"                   # World!

# Replace
echo "${str/World/Bash}"          # Hello, Bash!  (first match)
echo "${str//l/L}"                # HeLLo, WorLd!  (all matches)

# Remove prefix/suffix
file="report.tar.gz"
echo "${file%.gz}"                # report.tar  (remove shortest suffix)
echo "${file%%.gz}"               # report.tar  (remove longest suffix)
echo "${file#report.}"            # tar.gz      (remove shortest prefix)

# Case conversion (bash 4+)
echo "${str^^}"                   # HELLO, WORLD!
echo "${str,,}"                   # hello, world!

# Default values
echo "${UNDEFINED:-default}"      # default (var unset or empty)
echo "${UNDEFINED:=default}"      # sets var to default if unset
echo "${VAR:?Error: VAR required}" # exit with error if unset
```

| Pattern | Meaning |
|---------|---------|
| `${var:-default}` | Use default if unset/empty |
| `${var:=default}` | Assign default if unset/empty |
| `${var:+alternate}` | Use alternate if var IS set |
| `${var:?message}` | Fatal error if unset/empty |

---

## 14. Working with Files & Directories

### Essential Commands in Scripts

```bash
# Create
mkdir -p /tmp/myapp/{logs,cache,data}

# Copy / Move
cp -r "$src_dir" "$dest_dir"
mv "$old_name" "$new_name"

# Delete safely
rm -f "$file"           # file only
rm -rf "$dir"           # directory — BE CAREFUL

# Find files
find /var/log -name "*.log" -mtime +7        # older than 7 days
find . -type f -name "*.sh" -executable

# Check disk space
df -h /
du -sh /var/log/*
```

### Safe Temporary Files

```bash
# Always use mktemp — never hardcode /tmp/myfile
tmpfile=$(mktemp)
trap 'rm -f "$tmpfile"' EXIT    # cleanup on exit

echo "data" > "$tmpfile"
```

### Reading Config Files

```bash
# source a config file (runs it as bash)
if [[ -f "$CONFIG" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG"
fi
```

---

## 15. Exit Codes & Error Handling

### The set Built-in — Your Safety Net

Put this at the top of every serious script:

```bash
#!/bin/bash
set -euo pipefail
```

| Flag | Meaning |
|------|---------|
| `set -e` | Exit immediately if any command fails |
| `set -u` | Treat unset variables as errors |
| `set -o pipefail` | Pipeline fails if any command in it fails |

```bash
# Temporarily disable -e when needed
set +e
some_command_that_might_fail
result=$?
set -e

if (( result != 0 )); then
    echo "Command failed with code $result" >&2
fi
```

### Explicit Exit

```bash
exit 0     # Success
exit 1     # General error
exit 2     # Misuse (e.g., bad arguments)
```

### trap — Run Code on Exit/Signal

```bash
cleanup() {
    echo "Cleaning up..."
    rm -f "$tmpfile"
}
trap cleanup EXIT

# On Ctrl+C
trap 'echo "Interrupted"; exit 130' INT TERM
```

### Error Messages — Always to stderr

```bash
log_error() {
    echo "ERROR: $*" >&2
}

log_info() {
    echo "INFO: $*"
}
```

---

## 16. Debugging Scripts

```bash
# Run with trace (see every command before it runs)
bash -x script.sh

# Or add to script temporarily
set -x    # enable tracing
# ... code ...
set +x    # disable tracing

# Debug one function only
debug_func() {
    set -x
    # function body
    set +x
}
```

```bash
# Print debug messages conditionally
DEBUG=false

debug() {
    $DEBUG && echo "DEBUG: $*" >&2
}

debug "Variable x=$x"
```

### shellcheck — Static Analysis (Use This!)

```bash
# Install: https://www.shellcheck.net/
shellcheck myscript.sh
```

Common issues shellcheck catches:
- Unquoted variables
- Wrong test operators
- Useless `cat`
- Missing shebang

---

## 17. Script Arguments & Flags

### Manual Parsing

```bash
#!/bin/bash

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <filename>" >&2
    exit 1
fi

filename=$1
echo "Processing: $filename"
```

### getopts — Built-in Flag Parser

```bash
#!/bin/bash

verbose=false
output=""

while getopts "vo:" opt; do
    case $opt in
        v) verbose=true ;;
        o) output=$OPTARG ;;
        ?) echo "Usage: $0 [-v] [-o file]" >&2; exit 1 ;;
    esac
done

shift $((OPTIND - 1))    # shift past parsed options
remaining_args=("$@")

$verbose && echo "Verbose mode on"
echo "Output file: $output"
echo "Remaining: ${remaining_args[@]}"
```

**Remember:** `getopts` only handles single-character flags (`-v`, `-o file`). For long options (`--verbose`), use a library or manual parsing.

---

## 18. Best Practices for Production Scripts

### Script Template (Copy This)

```bash
#!/bin/bash
#
# Script: deploy.sh
# Purpose: Deploy application to target environment
# Usage: ./deploy.sh [-e env] [-v]
#

set -euo pipefail
IFS=$'\n\t'

# ── Constants ──────────────────────────────────────────
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_NAME="$(basename "$0")"

# ── Defaults ─────────────────────────────────────────────
ENV="dev"
VERBOSE=false

# ── Functions ────────────────────────────────────────────
log()   { echo "[$(date +'%H:%M:%S')] $*"; }
error() { echo "ERROR: $*" >&2; exit 1; }

usage() {
    echo "Usage: $SCRIPT_NAME [-e env] [-v]"
    exit 1
}

parse_args() {
    while getopts "e:vh" opt; do
        case $opt in
            e) ENV=$OPTARG ;;
            v) VERBOSE=true ;;
            h) usage ;;
            ?) usage ;;
        esac
    done
}

main() {
    parse_args "$@"
    log "Deploying to: $ENV"
    # ... your logic here
}

main "$@"
```

### Rules to Live By

1. **Always** use `set -euo pipefail`
2. **Always** quote `"$variables"`
3. **Always** check file/arg existence before using
4. **Never** hardcode paths — use variables or `SCRIPT_DIR`
5. **Never** run `rm -rf "$var"` without validating `$var` is not empty
6. **Use** `mktemp` and `trap` for temp files
7. **Send** errors to stderr (`>&2`), normal output to stdout
8. **Run** `shellcheck` before committing
9. **Add** a usage/help message
10. **Use** `main()` function pattern for organization

### Dangerous Patterns to Avoid

```bash
# DANGEROUS — if $dir is empty, deletes everything
rm -rf "$dir"/*
# SAFER
[[ -n "$dir" && -d "$dir" ]] && rm -rf "${dir:?}"/*

# DANGEROUS — eval with user input
eval "$user_input"

# DANGEROUS — unquoted variables in find -exec
find . -name "*.tmp" -exec rm {} \;
# BETTER
find . -name "*.tmp" -delete
```

---

## 19. Real-World Patterns

### Pattern 1: Retry Logic

```bash
retry() {
    local max_attempts=$1
    shift
    local attempt=1

    until "$@"; do
        if (( attempt >= max_attempts )); then
            echo "Failed after $max_attempts attempts" >&2
            return 1
        fi
        echo "Attempt $attempt failed. Retrying..." >&2
        ((attempt++))
        sleep 2
    done
}

retry 3 curl -sf https://api.example.com/health
```

### Pattern 2: Parallel Execution

```bash
MAX_JOBS=4
job_count=0

for file in data/*.csv; do
    process_file "$file" &
    ((job_count++))

    if (( job_count >= MAX_JOBS )); then
        wait -n           # wait for any one job to finish
        ((job_count--))
    fi
done
wait    # wait for all remaining
```

### Pattern 3: Logging with Timestamps

```bash
LOG_FILE="/var/log/myapp.log"

log() {
    local level=$1; shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a "$LOG_FILE"
}

log "INFO" "Service started"
log "ERROR" "Connection failed"
```

### Pattern 4: Lock File (Prevent Duplicate Runs)

```bash
LOCK_FILE="/tmp/myscript.lock"

exec 200>"$LOCK_FILE"
flock -n 200 || { echo "Already running" >&2; exit 1; }

# script runs exclusively here
```

### Pattern 5: Dry Run

```bash
DRY_RUN=false

run() {
    if $DRY_RUN; then
        echo "[DRY RUN] $*"
    else
        "$@"
    fi
}

run rm -f /tmp/old_cache
```

---

## 20. Quick Reference Cheat Sheet

### Test Operators

```
Files:     -f  -d  -e  -r  -w  -x  -s  -L
Numbers:   -eq  -ne  -lt  -gt  -le  -ge
Strings:   ==  !=  -z  -n  <  >
```

### Redirections

```
cmd > file      stdout to file (overwrite)
cmd >> file     stdout to file (append)
cmd 2> file     stderr to file
cmd &> file     both to file
cmd < file      stdin from file
cmd1 | cmd2     pipe
```

### Special Variables

```
$0 $1 $# $@ $* $? $$ $! $HOME $PWD $PATH
```

### String Ops

```
${#var}         length
${var:pos:len}  substring
${var/old/new}  replace first
${var//old/new} replace all
${var:-default} default value
```

### One-Liners Worth Knowing

```bash
# Backup a file with timestamp
cp "$file" "${file}.bak.$(date +%Y%m%d)"

# Count lines in file
wc -l < "$file"

# Check if command exists
command -v git &>/dev/null && echo "git found"

# Run command in script's directory
cd "$(dirname "$0")"

# Lowercase a variable
name_lower="${name,,}"
```

---

## 21. Practice Exercises

Work through these in order. Solutions build on previous concepts.

### Level 1 — Basics

1. Write a script that prints your name, today's date, and current directory.
2. Write a script that takes a name as argument and prints `"Hello, <name>!"`.
3. Write a script that checks if a file exists and prints its size.

### Level 2 — Logic

4. Write a script that checks if a number is even or odd.
5. Write a FizzBuzz script (1-100): multiples of 3 → Fizz, 5 → Buzz, both → FizzBuzz.
6. Write a script that counts how many `.sh` files are in a directory.

### Level 3 — Real Tools

7. Write a backup script: copy a file to `filename.YYYY-MM-DD.bak`.
8. Write a log analyzer: count ERROR, WARN, INFO lines in a log file.
9. Write a script with `-v` (verbose) and `-h` (help) flags using `getopts`.

### Level 4 — Production Quality

10. Write a script with `set -euo pipefail`, functions, error handling, and a `main()` entry point.
11. Write a script that retries a curl command up to 3 times.
12. Write a script that processes all `.csv` files in a directory and logs results with timestamps.

### Sample Solution (Exercise 5 — FizzBuzz)

```bash
#!/bin/bash
for ((i = 1; i <= 100; i++)); do
    output=""
    (( i % 3 == 0 )) && output+="Fizz"
    (( i % 5 == 0 )) && output+="Buzz"
    echo "${output:-$i}"
done
```

---

## Learning Path Summary

```
Week 1: Sections 1-5   → Variables, quoting, running scripts
Week 2: Sections 6-9   → Logic, loops, conditionals
Week 3: Sections 10-14 → Functions, I/O, files, arrays
Week 4: Sections 15-19 → Error handling, debugging, production patterns
Ongoing: Section 21    → Practice exercises until fluent
```

**Final tip:** The best way to remember shell scripting is to **automate something real** — backup a folder, parse a log, deploy a project. Every script you write makes the next one easier.
