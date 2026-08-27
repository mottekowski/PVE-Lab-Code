#!/usr/bin/env bash
# Shared CSV/evidence functions for AP1 V0.4.2 collectors.
# Normalization principle: one CSV row = one atomic parameter/value pair.
# V0.4.2 keeps the V0.4.1 execution architecture and adds explicit timestamp timezone handling.

set -u -o pipefail
export LC_ALL=C

AP1_TIMEZONE="${AP1_TIMEZONE:-Europe/Berlin}"
if [[ ! -e "/usr/share/zoneinfo/${AP1_TIMEZONE}" ]]; then
    printf 'Invalid AP1_TIMEZONE: %s (zoneinfo file not found)\n' "$AP1_TIMEZONE" >&2
    exit 64
fi
export TZ="$AP1_TIMEZONE"

LOCAL_HOST_SHORT="$(hostname -s 2>/dev/null || hostname)"
LOCAL_HOST_FQDN="$(hostname -f 2>/dev/null || printf '%s' "$LOCAL_HOST_SHORT")"
TARGET_HOST="${AP1_TARGET_HOST:-$LOCAL_HOST_SHORT}"
HOST_SHORT="$TARGET_HOST"
SAFE_HOST="$(printf '%s' "$HOST_SHORT" | tr -c 'A-Za-z0-9._-' '_')"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[1]}")" && pwd)"
SCRIPT_NAME="$(basename -- "${BASH_SOURCE[1]}" .sh)"
RUN_ID="${AP1_RUN_ID:-$(date '+%Y%m%d_%H%M')}"
OUTPUT_ROOT="${AP1_OUTPUT_ROOT:-${SCRIPT_DIR}/outputfiles}"
EVIDENCE_ROOT="${AP1_EVIDENCE_ROOT:-${SCRIPT_DIR}/evidencefiles}"
OUTPUT_DIR="${OUTPUT_ROOT}/${RUN_ID}"
EVIDENCE_DIR="${EVIDENCE_ROOT}/${RUN_ID}/${SAFE_HOST}/${SCRIPT_NAME}"
TMP_ROOT="$(mktemp -d)"
MAX_CELL_CHARS="${MAX_CELL_CHARS:-4000}"
AP1_SSH_USER="${AP1_SSH_USER:-root}"
AP1_SSH_CONNECT_TIMEOUT="${AP1_SSH_CONNECT_TIMEOUT:-10}"
AP1_SSH_OPTIONS="${AP1_SSH_OPTIONS:-}"
mkdir -p "${OUTPUT_DIR}" "${EVIDENCE_DIR}"
trap 'rm -rf "${TMP_ROOT}"' EXIT

is_local_target() {
    case "$TARGET_HOST" in
        "$LOCAL_HOST_SHORT"|"$LOCAL_HOST_FQDN"|localhost|127.0.0.1|::1) return 0 ;;
        *) return 1 ;;
    esac
}

ssh_base_args() {
    printf '%s\0' -n -o BatchMode=yes -o "ConnectTimeout=${AP1_SSH_CONNECT_TIMEOUT}" -o LogLevel=ERROR
}

run_command_target() {
    if is_local_target; then
        "$@"
        return $?
    fi

    local remote_cmd="" q quoted
    for q in "$@"; do
        printf -v quoted '%q' "$q"
        remote_cmd+="${quoted} "
    done

    local -a ssh_args
    ssh_args=(-n -o BatchMode=yes -o "ConnectTimeout=${AP1_SSH_CONNECT_TIMEOUT}" -o LogLevel=ERROR)
    if [[ -n "$AP1_SSH_OPTIONS" ]]; then
        local -a extra
        # AP1_SSH_OPTIONS is intended for simple whitespace-separated OpenSSH options.
        read -r -a extra <<< "$AP1_SSH_OPTIONS"
        ssh_args+=("${extra[@]}")
    fi
    ssh "${ssh_args[@]}" "${AP1_SSH_USER}@${TARGET_HOST}" "$remote_cmd"
}

csv_escape() {
    local value="${1-}"
    value="${value//$'\r'/}"
    value="${value//\"/\"\"}"
    printf '"%s"' "$value"
}

csv_row() {
    local first=1 field
    for field in "$@"; do
        [[ $first -eq 0 ]] && printf ';' >> "${OUTPUT_FILE}"
        csv_escape "$field" >> "${OUTPUT_FILE}"
        first=0
    done
    printf '\n' >> "${OUTPUT_FILE}"
}

collector_init() {
    TARGET_SHEET="$1"
    COLLECTOR_NO="$2"
    FILE_CATEGORY="$3"
    FILE_WHAT="$4"
    OUTPUT_FILE="${OUTPUT_DIR}/${RUN_ID}_${COLLECTOR_NO}_${SAFE_HOST}_${FILE_CATEGORY}_${FILE_WHAT}.csv"
    : > "${OUTPUT_FILE}"
    if [[ "$TARGET_SHEET" == "Network_Platform" ]]; then
        csv_row "Node/Standort" "Segment" "Parameter" "Wert" "Befehl/Quelle" "Zeitstempel" "Validiert (Y/N)" "Kommentar"
    else
        csv_row "Node/Scope" "Kategorie" "Parameter" "Wert" "Befehl/Quelle" "Zeitstempel" "Validiert (Y/N)" "Kommentar"
    fi
}

normalize_scalar() {
    local value="${1-}"
    value="${value//$'\r'/}"
    value="${value//$'\n'/ }"
    value="${value//$'\t'/ }"
    value="$(printf '%s' "$value" | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"
    printf '%s' "$value"
}

emit_record() {
    local scope="$1" category="$2" parameter="$3" value="$4" source="$5" ts="$6" comment="${7-}"
    value="$(normalize_scalar "$value")"
    if (( ${#value} > MAX_CELL_CHARS )); then
        value="${value:0:MAX_CELL_CHARS}"
        comment="${comment}${comment:+; }TRUNCATED at ${MAX_CELL_CHARS} chars; full value in Evidence"
    fi
    csv_row "$scope" "$category" "$parameter" "$value" "$source" "$ts" "N" "$comment"
}

emit_status() {
    local scope="$1" category="$2" parameter="$3" value="$4" source="$5" ts="$6" comment="${7-}"
    emit_record "$scope" "$category" "Collector Status / ${parameter}" "$value" "$source" "$ts" "$comment"
}

run_capture() {
    local slug="$1" source="$2"
    shift 2
    RUN_TS="$(date --iso-8601=seconds)"
    RUN_STDOUT="${TMP_ROOT}/${slug}.stdout"
    RUN_STDERR="${TMP_ROOT}/${slug}.stderr"
    RUN_RC=0
    run_command_target "$@" >"${RUN_STDOUT}" 2>"${RUN_STDERR}" || RUN_RC=$?
    RUN_EVIDENCE="${EVIDENCE_DIR}/${slug}.txt"
    {
        printf '# AP1 Evidence\n'
        printf 'Coordinator: %s\n' "$LOCAL_HOST_SHORT"
        printf 'TargetHost: %s\n' "$TARGET_HOST"
        printf 'Execution: %s\n' "$(is_local_target && printf local || printf ssh)"
        printf 'Script: %s\n' "$SCRIPT_NAME"
        printf 'RunID: %s\n' "$RUN_ID"
        printf 'Timestamp: %s\n' "$RUN_TS"
        printf 'Timezone: %s\n' "$AP1_TIMEZONE"
        printf 'Command: %s\n' "$source"
        printf 'ExitCode: %s\n' "$RUN_RC"
        printf '%s\n' '--- STDOUT ---'
        cat "$RUN_STDOUT"
        printf '\n%s\n' '--- STDERR ---'
        cat "$RUN_STDERR"
    } > "$RUN_EVIDENCE"
    RUN_EVIDENCE_REL="evidencefiles/${RUN_ID}/${SAFE_HOST}/${SCRIPT_NAME}/${slug}.txt"
}

run_capture_shell() {
    local slug="$1" source="$2" command_string="$3"
    run_capture "$slug" "$source" bash -c "$command_string"
}

run_ready() {
    local scope="$1" category="$2" parameter="$3" source="$4"
    if [[ $RUN_RC -ne 0 ]]; then
        local err
        err="$(head -n 3 "$RUN_STDERR" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g')"
        emit_status "$scope" "$category" "$parameter" "ERROR" "$source" "$RUN_TS" "ExitCode=${RUN_RC}; ${err:-command failed}; Evidence=${RUN_EVIDENCE_REL}"
        return 1
    fi
    if [[ ! -s "$RUN_STDOUT" ]]; then
        emit_status "$scope" "$category" "$parameter" "NO_DATA" "$source" "$RUN_TS" "Command succeeded without stdout; Evidence=${RUN_EVIDENCE_REL}"
        return 1
    fi
    return 0
}

emit_no_data() {
    local scope="$1" category="$2" parameter="$3" source="$4" ts="$5" comment="${6-}"
    emit_status "$scope" "$category" "$parameter" "NO_DATA" "$source" "$ts" "${comment}${comment:+; }Evidence=${RUN_EVIDENCE_REL:-n/a}"
}

emit_kv_colon_file() {
    local scope="$1" category="$2" prefix="$3" source="$4" ts="$5" file="$6" comment="${7-}"
    awk '
        /^[[:space:]]*$/ {next}
        /^[[:space:]]*[-]+[[:space:]]*$/ {next}
        {
            line=$0
            sub(/^[[:space:]]+/, "", line)
            pos=index(line, ":")
            if (pos>0) {
                k=substr(line,1,pos-1); v=substr(line,pos+1)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", k)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
                if (k!="" && v!="") print k "\t" v
            }
        }
    ' "$file" | while IFS=$'\t' read -r k v; do
        emit_record "$scope" "$category" "${prefix}${prefix:+ / }${k}" "$v" "$source" "$ts" "${comment}${comment:+; }Evidence=${RUN_EVIDENCE_REL}"
    done
}

json_object_fields() {
    local file="$1"; shift
    perl "${SCRIPT_DIR}/lib/ap1-json.pl" object "$file" "$@"
}

json_array_fields() {
    local file="$1" path="$2" key="$3"; shift 3
    perl "${SCRIPT_DIR}/lib/ap1-json.pl" array "$file" "$path" "$key" "$@"
}

json_flatten() {
    local file="$1" path="${2:-.}"
    perl "${SCRIPT_DIR}/lib/ap1-json.pl" flatten "$file" "$path"
}

finish_collector() {
    printf 'CSV output written: %s\n' "$OUTPUT_FILE"
    printf 'Evidence directory: %s\n' "$EVIDENCE_DIR"
}
