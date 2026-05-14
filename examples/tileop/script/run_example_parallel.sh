#!/usr/bin/env bash
# Copyright (c) 2026 Huawei Technologies Co., Ltd.
# This program is free software, you can redistribute it and/or modify it under the terms and conditions of
# CANN Open Software License Agreement Version 2.0 (the "License").
# Please refer to the License for details. You may not use this file except in compliance with the License.
# THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND, EITHER EXPRESS OR IMPLIED,
# INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT, MERCHANTABILITY, OR FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE in the root of the software repository for the full text of the License.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TILEOP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ROOT_DIR="$(cd "${TILEOP_ROOT}/../.." && pwd)"
RUNNER="${SCRIPT_DIR}/run_example.py"
TESTCASE_ROOT="${TESTCASE_ROOT:-${TILEOP_ROOT}/src/testcase}"

RUN_MODE="${RUN_MODE:-npu}"
SOC_VERSION="${SOC_VERSION:-a5}"
PTOAS_BIN="${PTOAS_BIN:-${ROOT_DIR}/.local/v0.6-pre/ptoas}"
WORK_SPACE="${WORK_SPACE:-}"
TESTCASE="${TESTCASE:-}"
TESTCASE_PREFIX="${TESTCASE_PREFIX:-}"
JOBS="${JOBS:-}"

log() {
  echo "[$(date +'%F %T')] $*"
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

[[ -f "${RUNNER}" ]] || die "missing runner: ${RUNNER}"
[[ -d "${TESTCASE_ROOT}" ]] || die "missing testcase root: ${TESTCASE_ROOT}"
[[ -x "${PTOAS_BIN}" ]] || die "missing executable ptoas: ${PTOAS_BIN}"
[[ -n "${WORK_SPACE}" ]] || die "WORK_SPACE is required"

if [[ -z "${JOBS}" ]]; then
  if command -v nproc >/dev/null 2>&1; then
    JOBS="$(nproc)"
  else
    JOBS=1
  fi
fi

[[ "${JOBS}" =~ ^[0-9]+$ ]] || die "JOBS must be a positive integer, got: ${JOBS}"
[[ "${JOBS}" -ge 1 ]] || die "JOBS must be >= 1"

mkdir -p "${WORK_SPACE}"
WORK_SPACE="$(cd "${WORK_SPACE}" && pwd)"
SUMMARY_FILE="${WORK_SPACE}/parallel-summary.tsv"
RUNNER_LOG="${WORK_SPACE}/parallel-runner.log"

discover_testcases() {
  if [[ -n "${TESTCASE}" ]]; then
    [[ -d "${TESTCASE_ROOT}/${TESTCASE}" ]] || die "unknown testcase: ${TESTCASE}"
    printf "%s\n" "${TESTCASE}"
    return 0
  fi

  find "${TESTCASE_ROOT}" -mindepth 1 -maxdepth 1 -type d | sort | while read -r dir; do
    local name
    name="$(basename "${dir}")"
    if [[ -n "${TESTCASE_PREFIX}" && "${name}" != "${TESTCASE_PREFIX}"* ]]; then
      continue
    fi
    printf "%s\n" "${name}"
  done
}

readarray -t TESTCASES < <(discover_testcases)
[[ "${#TESTCASES[@]}" -gt 0 ]] || die "no testcases found under ${TESTCASE_ROOT}"

: > "${SUMMARY_FILE}"
: > "${RUNNER_LOG}"

declare -A PID_TO_TESTCASE=()

launch_testcase() {
  local testcase="$1"
  local case_work="${WORK_SPACE}/cases/${testcase}"
  local case_log="${WORK_SPACE}/${testcase}.log"

  mkdir -p "${case_work}"
  log "[${testcase}] launch" | tee -a "${RUNNER_LOG}"
  (
    cd "${ROOT_DIR}"
    python3 "${RUNNER}" \
      -r "${RUN_MODE}" \
      -v "${SOC_VERSION}" \
      -t "${testcase}" \
      -p "${PTOAS_BIN}" \
      --work-dir "${case_work}"
  ) >"${case_log}" 2>&1 &

  local pid=$!
  PID_TO_TESTCASE["${pid}"]="${testcase}"
}

reap_one() {
  local pid="$1"
  local testcase="${PID_TO_TESTCASE[${pid}]}"
  local result="FAIL"
  local detail="1"

  if wait "${pid}"; then
    result="PASS"
    detail="0"
  fi

  printf '%s\t%s\t%s\n' "${testcase}" "${result}" "${detail}" >> "${SUMMARY_FILE}"
  log "[${testcase}] ${result} (${detail})" | tee -a "${RUNNER_LOG}"
  unset 'PID_TO_TESTCASE['"${pid}"']'
}

log "=== TileOp Validation Parallel ===" | tee -a "${RUNNER_LOG}"
log "WORK_SPACE=${WORK_SPACE}" | tee -a "${RUNNER_LOG}"
log "RUN_MODE=${RUN_MODE}" | tee -a "${RUNNER_LOG}"
log "SOC_VERSION=${SOC_VERSION}" | tee -a "${RUNNER_LOG}"
log "PTOAS_BIN=${PTOAS_BIN}" | tee -a "${RUNNER_LOG}"
log "TESTCASE=${TESTCASE:-<all>}" | tee -a "${RUNNER_LOG}"
log "TESTCASE_PREFIX=${TESTCASE_PREFIX:-<none>}" | tee -a "${RUNNER_LOG}"
log "JOBS=${JOBS}" | tee -a "${RUNNER_LOG}"
log "TOTAL_TESTCASES=${#TESTCASES[@]}" | tee -a "${RUNNER_LOG}"

next_index=0
while [[ "${next_index}" -lt "${#TESTCASES[@]}" || "${#PID_TO_TESTCASE[@]}" -gt 0 ]]; do
  while [[ "${next_index}" -lt "${#TESTCASES[@]}" && "${#PID_TO_TESTCASE[@]}" -lt "${JOBS}" ]]; do
    launch_testcase "${TESTCASES[${next_index}]}"
    next_index="$((next_index + 1))"
  done

  if [[ "${#PID_TO_TESTCASE[@]}" -eq 0 ]]; then
    continue
  fi

  while true; do
    for pid in "${!PID_TO_TESTCASE[@]}"; do
      if ! kill -0 "${pid}" 2>/dev/null; then
        reap_one "${pid}"
        break 2
      fi
    done
    sleep 1
  done
done

pass_count="$(awk -F '\t' '$2 == "PASS" {count++} END {print count + 0}' "${SUMMARY_FILE}")"
fail_count="$(awk -F '\t' '$2 != "PASS" {count++} END {print count + 0}' "${SUMMARY_FILE}")"

log "PASS=${pass_count} FAIL=${fail_count}" | tee -a "${RUNNER_LOG}"
log "summary: ${SUMMARY_FILE}" | tee -a "${RUNNER_LOG}"

if [[ "${fail_count}" -ne 0 ]]; then
  die "parallel validation finished with ${fail_count} failing testcase(s)"
fi

log "All ${pass_count} testcase(s) passed" | tee -a "${RUNNER_LOG}"
