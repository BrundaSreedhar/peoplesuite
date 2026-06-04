#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost}"
CLIENT_ID="${CLIENT_ID:-testclient}"
CLIENT_SECRET="${CLIENT_SECRET:-abcdefghgobbledegook1234}"
EMPLOYEE_ID="${EMPLOYEE_ID:-1234567}"

print_call() {
  local title="$1"
  shift
  echo ""
  echo "================================================================================"
  echo "  ${title}"
  echo "================================================================================"
  while [ $# -gt 0 ]; do
    printf "  %-12s %s\n" "$1" "$2"
    shift 2
  done
  echo "--------------------------------------------------------------------------------"
}

print_response() {
  echo "  Response:"
  if command -v node >/dev/null 2>&1; then
    node -e "console.log(JSON.stringify(JSON.parse(require('fs').readFileSync(0,'utf8')),null,2))" <<<"$1" | sed 's/^/    /'
  else
    echo "$1" | sed 's/^/    /'
  fi
  echo "================================================================================"
}

echo "PeopleSuite API test run"
echo "  Base URL:    ${BASE_URL}"
echo "  Employee ID: ${EMPLOYEE_ID} (7 digits)"
echo "  Client ID:   ${CLIENT_ID}"

TOKEN_URL="${BASE_URL}/peoplesuite/apis/token?grant_type=client_credentials&client_Id=${CLIENT_ID}&client_secret=${CLIENT_SECRET}"

print_call "1. OAuth — Issue access token (AuthorizationService)" \
  "Method:" "POST" \
  "Endpoint:" "/peoplesuite/apis/token" \
  "Full URL:" "${TOKEN_URL}" \
  "Query:" "grant_type=client_credentials" \
  "Query:" "client_Id=${CLIENT_ID}" \
  "Query:" "client_secret=${CLIENT_SECRET}" \
  "Auth:" "(none — credentials in query string)"

TOKEN_RESPONSE="$(curl -sS -X POST "${TOKEN_URL}")"
print_response "${TOKEN_RESPONSE}"

ACCESS_TOKEN="$(node -e "
  const d = JSON.parse(require('fs').readFileSync(0, 'utf8'));
  if (!d.access_token) {
    console.error('Token request failed. Fix AWS credentials: ./scripts/create-aws-secret.sh');
    console.error(JSON.stringify(d, null, 2));
    process.exit(1);
  }
  process.stdout.write(d.access_token);
" <<<"${TOKEN_RESPONSE}")"

AUTH_HEADER="Authorization: Bearer ${ACCESS_TOKEN}"
PROFILE_URL="${BASE_URL}/peoplesuite/apis/employees/${EMPLOYEE_ID}/profile"
PROFILE_BODY='{"first_name":"Ada","last_name":"Lovelace","start_date":"1843-10-01","country":"GB"}'

print_call "2. Employee — Create profile (POST)" \
  "Method:" "POST" \
  "Endpoint:" "/peoplesuite/apis/employees/${EMPLOYEE_ID}/profile" \
  "Full URL:" "${PROFILE_URL}" \
  "Header:" "Authorization: Bearer <access_token>" \
  "Header:" "Content-Type: application/json" \
  "Body:" "${PROFILE_BODY}"

PROFILE_CREATE_RESPONSE="$(curl -sS -X POST \
  -H "${AUTH_HEADER}" \
  -H "Content-Type: application/json" \
  -d "${PROFILE_BODY}" \
  "${PROFILE_URL}")"
print_response "${PROFILE_CREATE_RESPONSE}"

print_call "3. Employee — Get profile (GET)" \
  "Method:" "GET" \
  "Endpoint:" "/peoplesuite/apis/employees/${EMPLOYEE_ID}/profile" \
  "Full URL:" "${PROFILE_URL}" \
  "Header:" "Authorization: Bearer <access_token>"

PROFILE_GET_RESPONSE="$(curl -sS -X GET \
  -H "${AUTH_HEADER}" \
  "${PROFILE_URL}")"
print_response "${PROFILE_GET_RESPONSE}"

PHOTO_URL="${BASE_URL}/peoplesuite/apis/employees/${EMPLOYEE_ID}/photo"

if [ -n "${PHOTO_FILE:-}" ] && [ -f "${PHOTO_FILE}" ]; then
  print_call "4. Employee — Upload photo (POST)" \
    "Method:" "POST" \
    "Endpoint:" "/peoplesuite/apis/employees/${EMPLOYEE_ID}/photo" \
    "Full URL:" "${PHOTO_URL}" \
    "Header:" "Authorization: Bearer <access_token>" \
    "Body:" "multipart/form-data, field: file=@${PHOTO_FILE}"

  PHOTO_UPLOAD_RESPONSE="$(curl -sS -X POST \
    -H "${AUTH_HEADER}" \
    -F "file=@${PHOTO_FILE}" \
    "${PHOTO_URL}")"
  print_response "${PHOTO_UPLOAD_RESPONSE}"

  print_call "5. Employee — Download photo (GET)" \
    "Method:" "GET" \
    "Endpoint:" "/peoplesuite/apis/employees/${EMPLOYEE_ID}/photo" \
    "Full URL:" "${PHOTO_URL}" \
    "Header:" "Authorization: Bearer <access_token>" \
    "Output:" "/tmp/${EMPLOYEE_ID}-photo.out"

  curl -sS -X GET \
    -H "${AUTH_HEADER}" \
    -o "/tmp/${EMPLOYEE_ID}-photo.out" \
    "${PHOTO_URL}"
  echo "    Saved binary response to /tmp/${EMPLOYEE_ID}-photo.out ($(wc -c </tmp/${EMPLOYEE_ID}-photo.out | tr -d ' ') bytes)"
  echo "================================================================================"
else
  echo ""
  echo "  (Skipped photo upload/download — set PHOTO_FILE=/path/to/image.jpg to include)"
fi

echo ""
echo "All API tests completed successfully."
