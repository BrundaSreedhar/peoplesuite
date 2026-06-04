# PeopleSuite APIs

End-to-end cloud-native SaaS (REST only, no UI): two Node.js microservices, AWS DynamoDB + S3, Layer 7 load balancing (nginx or ingress-nginx), OAuth 2.0 client credentials.

---

## Lab requirements (original)

- **Employee** microservice: profile and photo APIs
- **AuthorizationService**: OAuth client credentials token endpoint
- **AWS**: DynamoDB + S3
- **Layer 7 load balancer**: nginx (Docker Compose) or ingress-nginx (Kubernetes)
- **Submit**: code, cloud resource screenshots, API test screenshots

---

## Architecture

| Component | Location | Role |
|-----------|----------|------|
| AuthorizationService | `services/authorization` | Issue bearer tokens |
| Employee service | `services/employee` | Profiles (DynamoDB), photos (S3) |
| nginx | `nginx/nginx.conf` + `docker-compose.yml` | L7 LB for local Compose |
| ingress-nginx | `k8s/ingress.yaml` | L7 LB for minikube |

### AWS resources

| Resource | Default name | Purpose |
|----------|--------------|---------|
| DynamoDB | `Client_Credentials` | `client_id` (hash), `access_token` (sort), `client_secret`, `contact_email` |
| DynamoDB | `Employee_Profiles` | `employee_id` (hash), profile fields |
| S3 | `PHOTO_BUCKET` | Objects at `employees/{EmployeeID}/photo` |

---

## API reference

Replace `{base}` with your load balancer URL:

- Docker Compose: `http://localhost`
- minikube (test script): `http://127.0.0.1:8888` via port-forward
- minikube (tunnel): `http://127.0.0.1`

Replace `{EmployeeID}` with a **7-digit** ID (e.g. `1234567`).

### 1. Issue access token

| | |
|--|--|
| **Service** | AuthorizationService |
| **Method** | `POST` |
| **Path** | `/peoplesuite/apis/token` |
| **Auth** | None (credentials in query string) |

**Query parameters**

| Parameter | Required | Value |
|-----------|----------|--------|
| `grant_type` | Yes | `client_credentials` |
| `client_Id` or `client_id` | Yes | e.g. `testclient` (max 10 chars) |
| `client_secret` | Yes | e.g. `abcdefghgobbledegook1234` |

**Example request**

```http
POST {base}/peoplesuite/apis/token?grant_type=client_credentials&client_Id=testclient&client_secret=abcdefghgobbledegook1234
```

**Example response** `200`

```json
{
  "access_token": "550e8400-e29b-41d4-a716-446655440000",
  "token_type": "Bearer",
  "grant_type": "client_credentials"
}
```

Use `access_token` in later calls: `Authorization: Bearer <access_token>`.

---

### 2. Create employee profile

| | |
|--|--|
| **Service** | Employee |
| **Method** | `POST` |
| **Path** | `/peoplesuite/apis/employees/{EmployeeID}/profile` |
| **Auth** | `Authorization: Bearer <access_token>` |

**JSON body**

| Field | Format |
|-------|--------|
| `first_name` | string |
| `last_name` | string |
| `start_date` | `YYYY-MM-DD` |
| `country` | 2-letter ISO-3166 (e.g. `GB`, `US`) |

**Example request**

```http
POST {base}/peoplesuite/apis/employees/1234567/profile
Authorization: Bearer <access_token>
Content-Type: application/json

{"first_name":"Ada","last_name":"Lovelace","start_date":"1843-10-01","country":"GB"}
```

**Example response** `201`

```json
{
  "employee_id": "1234567",
  "first_name": "Ada",
  "last_name": "Lovelace",
  "start_date": "1843-10-01",
  "country": "GB"
}
```

---

### 3. Get employee profile

| | |
|--|--|
| **Service** | Employee |
| **Method** | `GET` |
| **Path** | `/peoplesuite/apis/employees/{EmployeeID}/profile` |
| **Auth** | `Authorization: Bearer <access_token>` |

**Example request**

```http
GET {base}/peoplesuite/apis/employees/1234567/profile
Authorization: Bearer <access_token>
```

**Example response** `200` — same fields as create.

---

### 4. Upload employee photo

| | |
|--|--|
| **Service** | Employee |
| **Method** | `POST` |
| **Path** | `/peoplesuite/apis/employees/{EmployeeID}/photo` |
| **Auth** | `Authorization: Bearer <access_token>` |

**Body:** `multipart/form-data`, field name `file` (or JSON with `photo_base64`).

**Example request**

```http
POST {base}/peoplesuite/apis/employees/1234567/photo
Authorization: Bearer <access_token>
Content-Type: multipart/form-data

file=@/path/to/photo.jpg
```

**Example response** `201`

```json
{
  "employee_id": "1234567",
  "bucket": "peoplesuite-employee-photos-brunda",
  "key": "employees/1234567/photo",
  "content_type": "image/jpeg",
  "size_bytes": 12345
}
```

S3 object path: `employees/{EmployeeID}/photo` in `PHOTO_BUCKET`.

---

### 5. Download employee photo

| | |
|--|--|
| **Service** | Employee |
| **Method** | `GET` |
| **Path** | `/peoplesuite/apis/employees/{EmployeeID}/photo` |
| **Auth** | `Authorization: Bearer <access_token>` |

**Example request**

```http
GET {base}/peoplesuite/apis/employees/1234567/photo
Authorization: Bearer <access_token>
```

**Response:** binary image bytes (`Content-Type` from upload).

---

## Execution steps

### Prerequisites

- Node.js 20+, npm
- AWS CLI configured (`aws sts get-caller-identity`)
- Docker Desktop (for Compose or minikube driver)
- minikube + kubectl (for Kubernetes path)

**Test OAuth client** (created by `setup-aws.sh`):

- `client_id`: `testclient`
- `client_secret`: `abcdefghgobbledegook1234` (SHA-256 hash stored in DynamoDB)

---

### Step 1 — Configure environment

```bash
cd peoplesuite
cp .env.example .env
```

Edit `.env`:

```env
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=<your-key>
AWS_SECRET_ACCESS_KEY=<your-secret>
PHOTO_BUCKET=peoplesuite-employee-photos-YOURNAME
CLIENT_CREDENTIALS_TABLE=Client_Credentials
EMPLOYEE_PROFILES_TABLE=Employee_Profiles
```

---

### Step 2 — Create AWS resources

```bash
chmod +x scripts/*.sh
export AWS_REGION=us-east-1
export PHOTO_BUCKET=peoplesuite-employee-photos-YOURNAME   # match .env
./scripts/setup-aws.sh
```

**Verify (screenshot for lab):**

- AWS Console → DynamoDB → `Client_Credentials`, `Employee_Profiles` (table definitions + sample item)
- AWS Console → S3 → your `PHOTO_BUCKET` bucket

---

### Step 3a — Run with Docker Compose + nginx

```bash
docker compose build
docker compose up
```

Load balancer: `http://localhost` (port 80).

---

### Step 3b — Run with minikube (alternative)

```bash
minikube start
minikube addons enable ingress

# Update PHOTO_BUCKET in k8s/configmap.yaml if needed
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/configmap.yaml

./scripts/build-minikube-images.sh
./scripts/create-aws-secret.sh    # loads AWS keys from .env — do NOT use REPLACE_ME example secret

kubectl apply -f k8s/authorization-deployment.yaml
kubectl apply -f k8s/employee-deployment.yaml
kubectl apply -f k8s/ingress.yaml

kubectl get pods -n peoplesuite -w   # wait until READY 1/1
```

---

### Step 4 — Run API tests (screenshot-friendly output)

Scripts print **method, endpoint, full URL, headers, body, and JSON response** for each call.

**Minikube (recommended):**

```bash
./scripts/test-minikube-apis.sh
```

**With photo upload/download:**

```bash
export PHOTO_FILE=/full/path/to/your-image.jpg
./scripts/test-minikube-apis.sh
```

**Docker Compose:**

```bash
export BASE_URL=http://localhost
./scripts/test-apis.sh
export PHOTO_FILE=/full/path/to/your-image.jpg
./scripts/test-apis.sh
```

**Optional — manual curl** (quote URLs in zsh):

```bash
# 1. Token
curl -sS -X POST "http://localhost/peoplesuite/apis/token?grant_type=client_credentials&client_Id=testclient&client_secret=abcdefghgobbledegook1234"

# 2. Set token from response
TOKEN="<paste-access_token>"

# 3. Create profile
curl -sS -X POST "http://localhost/peoplesuite/apis/employees/1234567/profile" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"first_name":"Ada","last_name":"Lovelace","start_date":"1843-10-01","country":"GB"}'

# 4. Get profile
curl -sS "http://localhost/peoplesuite/apis/employees/1234567/profile" \
  -H "Authorization: Bearer ${TOKEN}"

# 5. Upload photo
curl -sS -X POST "http://localhost/peoplesuite/apis/employees/1234567/photo" \
  -H "Authorization: Bearer ${TOKEN}" \
  -F "file=@/path/to/photo.jpg"

# 6. Download photo
curl -sS "http://localhost/peoplesuite/apis/employees/1234567/photo" \
  -H "Authorization: Bearer ${TOKEN}" \
  -o downloaded.jpg
```

After a successful photo upload, confirm in S3: `employees/1234567/photo` in your bucket.

---

### Step 5 — What to submit

| Item | Screenshot / artifact |
|------|------------------------|
| Code | This repo (both microservices, nginx, k8s manifests) |
| DynamoDB | Table schemas + items in `Client_Credentials`, `Employee_Profiles` |
| S3 | Bucket name + object after photo upload |
| API tests | Terminal output from `./scripts/test-minikube-apis.sh` or `./scripts/test-apis.sh` |
| Load balancer | Docker Compose (nginx) or minikube ingress |

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `Could not resolve host: peoplesuite.local` | Use `./scripts/test-minikube-apis.sh` or `minikube tunnel` + `BASE_URL=http://127.0.0.1` |
| `ErrImagePull` | `./scripts/build-minikube-images.sh` |
| `storage_error` / invalid AWS token | `./scripts/create-aws-secret.sh` (from `.env`); never apply placeholder `REPLACE_ME` secret |
| `invalid_client_secret` | Use seeded `client_secret` from setup; rebuild auth image if needed |
| No S3 bucket | Re-run `./scripts/setup-aws.sh` with `PHOTO_BUCKET` set |
| Port 80 connection refused | Start `docker compose up` or use minikube test script |
| zsh `parse error near '&'` | Quote the full URL in curl |

---

## Project layout

```
peoplesuite/
├── services/authorization/   # Token API
├── services/employee/        # Profile + photo APIs
├── nginx/                    # Compose load balancer
├── k8s/                      # minikube manifests
├── scripts/
│   ├── setup-aws.sh          # DynamoDB + S3 + seed client
│   ├── create-aws-secret.sh  # K8s AWS credentials from .env
│   ├── build-minikube-images.sh
│   ├── test-apis.sh          # Screenshot-friendly API tests
│   └── test-minikube-apis.sh # Same, via ingress port-forward
├── docker-compose.yml
└── .env.example
```

---

## Original lab specification

<details>
<summary>Full assignment text</summary>

The goal of this lab is to build an end-to-end cloud native SAAS application. This application will have no UI, only REST APIs. You must use a Layer 7 Load Balancer (nginx recommended), Kubernetes locally or Killercoda/KodeKloud, AWS S3 and DynamoDB.

**Employee microservice**

- `GET`/`POST` `/peoplesuite/apis/employees/{EmployeeID}/profile` — EmployeeID (7 digits), First Name, Last Name, Start Date, Country (2-digit ISO-3166)
- `GET`/`POST` `/peoplesuite/apis/employees/{EmployeeID}/photo`

**OAuth 2.0 client credentials**

- **AuthorizationService**: `POST` `/peoplesuite/apis/token` with query params `grant_type`, `client_Id`, `client_secret`
- DynamoDB `Client_Credentials`: `client_id` (hash), `access_token` (sort), `client_secret`, `contact_email`
- On token request: validate client, generate UUID `access_token`, store in DynamoDB
- Protected APIs: `Authorization: Bearer <access_token>`, lookup token in DynamoDB

</details>
