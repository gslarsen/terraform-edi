import sys
import logging
import pymysql
import json
import boto3
from botocore.exceptions import ClientError

# get secret assumes secret mgr is configured for the database
def get_secret():

    secret_name = "poc-demo"
    region_name = "us-east-1"

    # Create a Secrets Manager client
    session = boto3.session.Session()
    client = session.client(
        service_name='secretsmanager',
        region_name=region_name
    )

    try:
        get_secret_value_response = client.get_secret_value(
            SecretId=secret_name
        )
    except ClientError as e:
        # For a list of exceptions thrown, see
        # https://docs.aws.amazon.com/secretsmanager/latest/apireference/API_GetSecretValue.html
        raise e

    # Decrypts secret using the associated KMS key.
    secret = get_secret_value_response['SecretString']

    return secret


# rds settings
secret = json.loads(get_secret())
rds_host = secret['host']
user_name = secret['username']
password = secret['password']
db_name = secret['dbname']

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# create the database connection outside the handler to allow connections to be
# re-used by subsequent function invocations.
try:
    conn = pymysql.connect(host=rds_host, user=user_name, passwd=password, db=db_name, connect_timeout=5)
except pymysql.MySQLError as e:
    logger.error("ERROR: Unexpected error: Could not connect to MySQL instance.")
    logger.error(e)
    sys.exit()

logger.info("SUCCESS: Connection to RDS MySQL instance succeeded")


def lambda_handler(event, context):
    print("EVENT:", event)
    failed_messages_to_reprocess = []
    batch_failure_response = {}
    item_count = 0

    for record in event['Records']:
        try:
            print(f"PROCESSING MESSAGE ID: {record['messageId']}")
            message = json.loads(record['body']) if isinstance(record['body'], str) else record['body']
            json_msg = json.dumps(message)

            sql_string = f"insert into tenders (tender) values ({json.dumps(json_msg)})" #{json.dumps(message)}

            with conn.cursor() as cur:
                cur.execute(sql_string)
                conn.commit()
                item_count += 1
            conn.commit()
        
        except Exception as err:
            print(f"FAILED MESSAGE ID: {record['messageId']}; Unexpected {err=}, {type(err)=}")
            failed_messages_to_reprocess.append({"itemIdentifier": record['messageId']})
            
    logger.info(f"Added {item_count} items to the MySQL ExampleDB - tenders table")
    batch_failure_response['batchItemFailures'] = failed_messages_to_reprocess
    print("batch_failure_response", batch_failure_response)
    return batch_failure_response
    