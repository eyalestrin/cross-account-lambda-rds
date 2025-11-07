import json
import psycopg2
import boto3
import os

def lambda_handler(event, context):
    secrets_client = boto3.client('secretsmanager')
    secret = json.loads(secrets_client.get_secret_value(SecretId=os.environ['DB_SECRET_ARN'])['SecretString'])
    
    conn = psycopg2.connect(
        host=secret['host'],
        database=secret['dbname'],
        user=secret['username'],
        password=secret['password']
    )
    
    cur = conn.cursor()
    cur.execute("SELECT transaction_id, description FROM transactions")
    rows = cur.fetchall()
    
    result = {row[0]: row[1] for row in rows}
    
    cur.close()
    conn.close()
    
    return {
        'statusCode': 200,
        'body': json.dumps(result)
    }
