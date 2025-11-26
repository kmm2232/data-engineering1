# Serverless Data Processing Pipeline(ETL)

# Overview
Repository contains a fully automated, serverless data pipeline built on AWS. Uses Terraform to deploy: Amazon Kinesis Data Firehose, Raw S3 Bucket, Glue ETL job, Curated S3 Bucket, Glue Crawler, Athena Workgroup + Query outputs, IAM roles + plocies, and Script upload automation. The pipeline allows anyone to send JSON events into Firehose and query the transformed results in Athena.

# Prerequisites
1. Terraform
    https://developer.hashicorp.com/terraform/downloads
2. AWS CLI
    https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html
3. AWS Credentials
    Run: aws configure
    proivde AWS Access Key, AWS Secret Key
    Region: us-east-1
4. Permissions Required
    The user deploying Terraform must have:
        S3 Full Access
        Glue Full Access
        Firehose Full Access
        IAM CreateRole / AttachPolicy
        Athena Full Access
        CloudWatch Logs access

# Deployment Instructions
1. Clone repository
2. Open d1-assignment repository:
    cd d1-assignment
3. Spin up terraform
    terraform init
    terraform plan
    terraform apply -> Types yes when prompted

# Test Pipeline
1. Send event to AWS firehose using command:
    aws firehose put-record \
  --delivery-stream-name clickstream-firehose \
  --record "{\"Data\":\"$(printf '{\"user_id\":\"user67\",\"session_id\":\"s1\",\"page\":\"/home\",\"timestamp\":1732410000000,\"to_be_dropped\":\"Should_not_be_here\"}' | base64 | tr -d '\n')\"}"
2. After a few minutes confirm data appears in S3 bucket using the following command:
    *s3://makuvaro-clickstream-raw/year=YYYY/month=MM/day=DD/*.json.gz*
3. Navigate to AWS Console-> Glue-> Jobs
4. Run job *clickstream-transform-job*
5. Confirm data appears in S3 bucket using the following command:
    *s3://makuvaro-clickstream-curated/year=YYYY/month=MM/day=DD/*.parquet*
6. Navigate tp AWS Console-> Glue-> Crawlers
7. Run crawler *clickstream-curated-crawler*
8. Navigate to Glue Data Catalog:
    Table appears with partition columns(year, month,day) with no *to_be_deleted* column 
9. Navigate to AWS Console-> Athena
10. Select Workgroup *clickstream-analytics*
11. Select Database *clickstream_analytics_db*
12. Run Queries:
    SELECT * FROM clickstream_curated LIMIT 10;
13. Confirm query results appear in S3 bucket:
    *s3://makuvaro-clickstream-athena-results/*

# Cleanup
1. Empty all S3 buckets
2. Run command:
    *terraform destroy*

# Trouble shooting
Firehose Error:
    Ensure Base64 command matches style provided in the README

# Author
Karl Makuvaro 