import sys
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext

# Get job parameters from Terraform
args = getResolvedOptions(sys.argv, [
    "JOB_NAME",
    "RAW_BUCKET",
    "CURATED_BUCKET"
])

#Spark initialization
sc = SparkContext()
#Wrap inside Gluecontext to add glue-sepcifc functionality
glueContext = GlueContext(sc)
spark = glueContext.spark_session   #Used for reading and writing data
# Initialize of Glue job
job = Job(glueContext)
job.init(args["JOB_NAME"], args)

raw_bucket = args["RAW_BUCKET"]
curated_bucket = args["CURATED_BUCKET"]

# Partition paths included so that Glue can read partitioned data
raw_path = f"s3://{raw_bucket}/year=*/month=*/day=*/"

# Partition paths included so that Glue can write partitioned data in the formatted required
curated_path = f"s3://{curated_bucket}/year=25/month=11/day=25/"

#Testing print statements
print("Reading from:", raw_path)
print("Writing to:", curated_path)

df_raw = spark.read.json(raw_path)
# Simple transform of droping a column
df_clean = df_raw.drop("to_be_dropped")
# Write transformed data to curated S3 bucket in Parquet format
df_clean.write.mode("overwrite").parquet(curated_path)
#Tells GLue that a job has completed successfully
job.commit()
