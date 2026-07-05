# Serverless Image-Processing Pipeline

An event-driven, serverless pipeline on AWS that ingests uploaded images, processes
them asynchronously, stores their metadata, and serves it back over a REST API.
Every piece of infrastructure is defined as code with Terraform and secured with
least-privilege IAM.

Built in the `ap-south-1` (Mumbai) region.

---

## Architecture

```
                        ┌────────────────────────────┐
   Upload (PUT)         │                            │
   ────────────►  S3 (uploads/)                       │
                        │                            │
                   S3 event notification              │
                        │                            │
                        ▼                            │
                   SQS main queue ──(3 failed tries)──► SQS dead-letter queue
                        │                                      │
                   event source mapping                  CloudWatch alarm
                        │                                      │
                        ▼                                      ▼
                   Lambda (processor)                     SNS ──► email alert
                        │
             reads object metadata from S3
                        │
                        ▼
                   DynamoDB (metadata)
                        ▲
                        │  GetItem
   GET /images/{id}     │
   ────────────►  API Gateway ──► Lambda (query) ──► JSON response
```

**Flow in words:** a client uploads an image to S3. S3 emits an event to an SQS
queue, which decouples ingestion from processing. A Lambda function consumes the
queue, reads the object's metadata, and writes a record to DynamoDB. A separate
API Gateway + Lambda lets clients read those records back over HTTPS. Anything that
fails processing three times is routed to a dead-letter queue, which triggers a
CloudWatch alarm that emails an operator via SNS.

---

## AWS services used

| Service        | Role in the pipeline                                        |
|----------------|-------------------------------------------------------------|
| S3             | Stores uploaded images; emits events on new uploads         |
| SQS            | Decouples upload from processing; retries; dead-letter queue |
| Lambda         | Processes images (processor) and serves reads (query)       |
| DynamoDB       | Stores image metadata (on-demand, point-in-time recovery)   |
| API Gateway    | Public HTTP API in front of the query function              |
| IAM            | Least-privilege execution roles per function                |
| CloudWatch     | Alarm on the dead-letter queue; Lambda logs                 |
| SNS            | Email notification when the pipeline detects a failure      |
| Terraform      | Defines and provisions all of the above as code             |

---

## Repository structure

```
.
├── main.tf            # Terraform + AWS provider config, default tags
├── variables.tf       # Input variables (region, project name)
├── s3.tf              # Uploads bucket + public-access block + encryption
├── sqs.tf             # Main queue, dead-letter queue, S3 notification
├── dynamodb.tf        # Metadata table
├── iam.tf             # Processor Lambda's least-privilege role
├── lambda.tf          # Processor function + SQS event source mapping
├── api.tf             # Query function, its role, and the HTTP API
├── monitoring.tf      # DLQ CloudWatch alarm + SNS email alerts
├── outputs.tf         # Key outputs (bucket name, API URL, etc.)
├── lambda_src/
│   └── lambda_function.py   # Processor: SQS → S3 metadata → DynamoDB
└── query_src/
    └── query_function.py    # Query: DynamoDB GetItem → JSON
```

---

## Design decisions

**Why a queue between S3 and Lambda, rather than triggering Lambda directly?**
The SQS queue decouples ingestion from processing. A burst of uploads simply fills
the queue instead of overwhelming downstream services, and it provides built-in
retries plus a dead-letter queue so failures are captured rather than lost.

**Why a dead-letter queue?**
After three failed processing attempts, a message is moved to the DLQ instead of
being retried forever or silently dropped. A CloudWatch alarm watches the DLQ and
sends an email via SNS, so failures are surfaced, not hidden.

**Why on-demand (PAY_PER_REQUEST) DynamoDB?**
The workload is bursty and unpredictable. On-demand billing scales to zero when
idle (no cost for unused capacity) and scales up automatically under load, with no
capacity planning to manage.

**Why least-privilege IAM roles?**
Each Lambda has its own role scoped to exactly what it needs. The processor can
read the queue, read objects from the uploads bucket (`s3:GetObject` on the
object-level ARN), and write to the table (`dynamodb:PutItem`). The query function
can only read (`dynamodb:GetItem`). No wildcards; the write path and read path have
distinct, minimal permissions.

**Why an S3 event prefix filter (`uploads/`)?**
Processing is only triggered for objects under `uploads/`. This prevents a feedback
loop if processed artifacts are ever written back into the same bucket.

**Why the SQS visibility timeout (300s) vs the Lambda timeout (30s)?**
The queue's visibility timeout comfortably exceeds six times the function timeout,
following AWS guidance, so a message stays hidden long enough for processing to
complete before it could be redelivered.

---

## Security highlights

- The uploads bucket blocks all public access and encrypts objects at rest.
- SQS and DynamoDB are encrypted at rest by default.
- Every function runs under a dedicated, least-privilege IAM role.
- The account uses a non-root admin user with MFA for day-to-day work; the
  Terraform credentials belong to a separate machine user.
- Environment-specific values (e.g. the alert email) live in a git-ignored
  `terraform.tfvars`, never committed.

---

## Deploying it yourself

Prerequisites: an AWS account, the AWS CLI configured with credentials, and
Terraform installed.

```bash
# 1. Provide your alert email
echo 'alert_email = "you@example.com"' > terraform.tfvars

# 2. Initialize, review, and apply
terraform init
terraform plan
terraform apply

# 3. Confirm the SNS email subscription (check your inbox, including spam)
```

Key outputs after apply include the uploads bucket name and the API base URL.

---

## Testing the pipeline

```bash
# Upload a file (must be under the uploads/ prefix to trigger processing)
aws s3 cp test.jpg s3://<BUCKET_NAME>/uploads/test.jpg

# Read the stored record back over HTTP
curl "<API_BASE_URL>/images/uploads/test.jpg"
```

A successful response returns the record as JSON, including `size_bytes`,
`content_type`, and `status`.

To test failure handling, send a message directly to the dead-letter queue and
watch the CloudWatch alarm fire and email you:

```bash
aws sqs send-message --queue-url <DLQ_URL> --message-body "simulated failure"
```

---

## Tearing it down

Because everything is Infrastructure as Code, the entire stack can be removed and
rebuilt on demand:

```bash
terraform destroy   # remove everything
terraform apply     # rebuild identically
```

---

## Possible enhancements

- Generate real thumbnails and extract image dimensions (e.g. Pillow via a Lambda
  layer or container image).
- Add image labelling with Amazon Rekognition.
- Add a global secondary index or a `status`-based query pattern to DynamoDB.
- Migrate Terraform state to a remote backend (S3 + native state locking).
- Add a CI/CD pipeline (e.g. GitHub Actions) to run `fmt`, `validate`, and `plan`
  on pull requests.
