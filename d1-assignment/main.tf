#S3 Buckets

#Creation of bucket for Firehouse raw data
resource "aws_s3_bucket" "raw_clickstream" {
  bucket = "makuvaro-clickstream-raw"
}

#Enable versioning for the raw bucket
resource "aws_s3_bucket_versioning" "raw_versioning" {
  bucket = aws_s3_bucket.raw_clickstream.id
  versioning_configuration {
    status = "Enabled"
  }
}

#Creation of bucket for tranformed data
resource "aws_s3_bucket" "curated_clickstream" {
  bucket = "makuvaro-clickstream-curated"
}

#Enable versioning for the curated bucket
resource "aws_s3_bucket_versioning" "curated_versioning" {
  bucket = aws_s3_bucket.curated_clickstream.id
  versioning_configuration {
    status = "Enabled"
  }
}

##Creation of bucket to store Glue scripts
resource "aws_s3_bucket" "glue_scripts" {
  bucket = "makuvaro-clickstream-scripts"
}

# Upload Glue ETL script to S3 Glue scripts bucket
resource "aws_s3_object" "glue_script" {
  bucket = aws_s3_bucket.glue_scripts.bucket
  key    = "simple_transform.py"
  source = "${path.module}/simple_transform.py"
  etag   = filemd5("${path.module}/simple_transform.py")
}


#Firehose

#Creation of IAM Role for Firehose to access S3
resource "aws_iam_role" "firehose_role" {
  name = "clickstream-firehose-role"

  #Trust relationship policy to allow Firehose to assume this role  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
        Effect = "Allow"
        Principal = { Service = "firehose.amazonaws.com" }
        Action = "sts:AssumeRole" #Required for service roles
    }]
  })
}

#IAM Policy document defining permissions for Firehose to write to S3 and log to CloudWatch
data "aws_iam_policy_document" "firehose_policy" {
    # Permissions to read/write to the raw S3 bucket  
    statement {
        effect = "Allow"
        sid = "S3Access"

        # Permissions for S3 actions needed by Firehose
        actions = [
        "s3:AbortMultipartUpload",
        "s3:GetBucketLocation",
        "s3:GetObject",
        "s3:ListBucket",
        "s3:ListBucketMultipartUploads",
        "s3:PutObject"
        ]

        # Resources for the raw S3 bucket and its objects can be accessed by Firehose
        resources = [
        aws_s3_bucket.raw_clickstream.arn,    #The bucket itself
        "${aws_s3_bucket.raw_clickstream.arn}/*" #All objects within the bucket
        ]
    }
    
    # Permissions to write logs to CloudWatch
    statement {
        effect = "Allow"
        sid = "Logging"

        actions = [
        "logs:PutLogEvents",    #Write log events
        "logs:CreateLogGroup",  #Create log groups
        "logs:CreateLogStream", #Create log streams
        "logs:DescribeLogStreams" #Describe log streams
        ]

        resources = ["*"]   #Allow access to all log resources
    }
}

# Attach the IAM policy to the Firehose role
resource "aws_iam_role_policy" "firehose_policy_attach" {
  role = aws_iam_role.firehose_role.id
  policy = data.aws_iam_policy_document.firehose_policy.json
}

# Creation of Kinesis Firehose Delivery Stream to deliver data to the raw S3 bucket
resource "aws_kinesis_firehose_delivery_stream" "clickstream_to_raw" {
    name = "clickstream-firehose"
    destination = "extended_s3" #Using extended_s3 to allow for more configuration options for Firehose to write to S3

    #Extended S3 configuration for Firehose
    extended_s3_configuration {
        role_arn = aws_iam_role.firehose_role.arn
        bucket_arn = aws_s3_bucket.raw_clickstream.arn

        buffering_size = 5 #Buffer until 5MB of data is collected to limit number of PUT requests
        buffering_interval = 60 #Buffer for up to 60 seconds before delivering data to S3
        compression_format = "GZIP" #Store data in compressed GZIP format to save storage space

        #Prefix and error output prefix for organizing data in S3
        prefix = "year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
        error_output_prefix = "errors/!{firehose:error-output-type}/"
    }
}

#Glue Job

#IAM Role for Glue to access S3 and Glue resources
resource "aws_iam_role" "glue_role" {
    name = "clickstream-glue-role"

    #Trust relationship policy to allow Glue to assume this role
    assume_role_policy = jsonencode({
        Version = "2012-10-17",
        Statement = [{
        Effect = "Allow",
        Principal = { Service = "glue.amazonaws.com" },
        Action = "sts:AssumeRole"    #Required for Glue service roles
        }]
    })
}

#IAM Policy document defining permissions for Glue to access S3 and Glue resource
data "aws_iam_policy_document" "glue_policy" {
    # Permissions for Glue to read/write to S3 buckets
    statement {
        effect = "Allow"
        actions = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket",
        "s3:DeleteObject"
        ]
        resources = [
        aws_s3_bucket.raw_clickstream.arn,
        "${aws_s3_bucket.raw_clickstream.arn}/*",   #Raw bucket and its objects
        aws_s3_bucket.curated_clickstream.arn,
        "${aws_s3_bucket.curated_clickstream.arn}/*",   #Curated bucket
        aws_s3_bucket.glue_scripts.arn,
        "${aws_s3_bucket.glue_scripts.arn}/*"  #Glue scripts bucket
        ]
    }

    # Permissions for Glue to access Glue resources
    statement {
        effect = "Allow"
        actions = ["glue:*"]    #Allow all Glue actions
        resources = ["*"]
    }
}

#Attach the IAM policy to the Glue role
resource "aws_iam_role_policy" "glue_policy_attach" {
    role = aws_iam_role.glue_role.id
    policy = data.aws_iam_policy_document.glue_policy.json
}

#Creation of Glue ETL Job to transform raw clickstream data to curated format
resource "aws_glue_job" "clickstream_transform" {
    name = "clickstream-transform-job"
    role_arn = aws_iam_role.glue_role.arn

    #Define script + engine parameters
    command {
        name = "glueetl"
        script_location = "s3://${aws_s3_bucket.glue_scripts.bucket}/${aws_s3_object.glue_script.key}"
        python_version  = "3"
    }

    # command {
    #     name = "glueetl" #Using Glue ETL engine which is based on Apache Spark
    #     script_location = "s3://${aws_s3_bucket.glue_scripts.bucket}/simple_transform.py"
    #     python_version = "3"
    # }

    #Arguments to pass to the Glue job script
    default_arguments = {
        "--RAW_BUCKET" = aws_s3_bucket.raw_clickstream.bucket
        "--CURATED_BUCKET" = aws_s3_bucket.curated_clickstream.bucket
        "--job-language" = "python"
    }

    glue_version = "4.0"
    worker_type = "G.1X" #Standard Glue worker type with 1 DPU (Data Processing Unit)
    number_of_workers = 2 #Use 2 workers for parallel processing
}

#Creation of Glue Catalog database to store table metadata
resource "aws_glue_catalog_database" "clickstream_db" {
  name = "clickstream_analytics_db" #Database name for Athena and Glue
}

#Crawler

#Creation of Glue Crawler to crawl curated S3 bucket and populate Glue Catalog
resource "aws_glue_crawler" "curated_crawler" {
    name = "clickstream-curated-crawler"
    role = aws_iam_role.glue_role.arn
    database_name = aws_glue_catalog_database.clickstream_db.name

    #Crawler will read from curated bucket
    s3_target {
        path = "s3://${aws_s3_bucket.curated_clickstream.bucket}/"  #Crawl the entire curated bucket
    }
}

#Athena

#Creation of S3 bucket to store Athena query results
resource "aws_s3_bucket" "athena_results" {
  bucket = "makuvaro-clickstream-athena-results"
}

#Creation of Athena Workgroup for clickstream analytics
resource "aws_athena_workgroup" "clickstream_wg" {
    name = "clickstream-analytics"

    #Configuration for Athena quries output
    configuration {
        result_configuration {
        output_location = "s3://${aws_s3_bucket.athena_results.bucket}/results/"
        }
    }
}
