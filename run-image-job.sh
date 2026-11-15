#!/usr/bin/env bash
set -euo pipefail

job_name="image-job-$(date +%s)-$$"

kubectl --context kind-assessment -n assessment create job "$job_name" \
  --from=cronjob/image-job
