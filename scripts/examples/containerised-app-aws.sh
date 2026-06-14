#!/usr/bin/env bash
# Smoke-tests the containerised app running on AWS ECS Fargate via the ALB.
# Looks up the ALB DNS name via the AWS CLI — no terraform output needed.
# Usage: ./scripts/examples/containerised-app-aws.sh
set -euo pipefail
export AWS_PAGER=""
export AWS_PROFILE="${AWS_PROFILE:-sandbox}"

echo "==> Looking up ALB DNS name"
BASE_URL="http://$(aws elbv2 describe-load-balancers \
  --names "tf-public-cloud-app-alb" \
  --query 'LoadBalancers[0].DNSName' \
  --output text)"
echo "     ${BASE_URL}"

echo "==> GET /api/items"
curl -sf "${BASE_URL}/api/items" | jq .

echo "==> GET /api/items/1"
curl -sf "${BASE_URL}/api/items/1" | jq .

echo "==> GET /api/items/99 (expect 404)"
STATUS=$(curl -o /dev/null -sw '%{http_code}' "${BASE_URL}/api/items/99")
if [ "${STATUS}" = "404" ]; then
  echo "     Got expected 404"
else
  echo "     FAIL: expected 404 but got ${STATUS}" >&2
  exit 1
fi

echo "==> GET /actuator/health"
curl -sf "${BASE_URL}/actuator/health" | jq .

echo "==> Done"
