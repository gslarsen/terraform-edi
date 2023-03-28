import sys
import logging
import pymysql
import json

# rds settings
# region
rds_host = "mysqlforlambda.ctempmbutv6y.us-east-1.rds.amazonaws.com"
user_name = "admin"
password = "Cfgauss11!Aws"
db_name = "ExampleDB"
# endregion

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
            message = json.loads(record['body'])
            print(f"BODY before .loads: {type(message)}")
            json_msg = json.dumps(message)
            print(f"BODY after .loads: {json_msg}")

            sql_string = f"insert into tenders (tender) values ({json.dumps(json_msg)})" #{json.dumps(message)}

            with conn.cursor() as cur:
                cur.execute(sql_string)
                conn.commit()
                # cur.execute("select * from tenders order by id desc limit 1")
                # logger.info("The following items have been added to the database:")
                # for row in cur:
                #     item_count += 1
                #     logger.info(row)
                item_count += 1
            conn.commit()

            # return "Added %d items to RDS MySQL table" % item_count
         
        except Exception as err:
            print(f"FAILED MESSAGE ID: {record['messageId']}; Unexpected {err=}, {type(err)=}")
            failed_messages_to_reprocess.append({"itemIdentifier": record['messageId']})
            
    logger.info(f"Added {item_count} items to the MySQL ExampleDB - tenders table")
    batch_failure_response['batchItemFailures'] = failed_messages_to_reprocess
    print("batch_failure_response", batch_failure_response)
    return batch_failure_response
    