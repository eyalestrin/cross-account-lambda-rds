import json
import psycopg2
import boto3
import os

def lambda_handler(event, context):
    try:
        # Parse API Gateway event
        body = json.loads(event.get('body', '{}'))
        transaction_id = body.get('transaction_id')
        
        if not transaction_id:
            return {
                'statusCode': 400,
                'headers': {'Access-Control-Allow-Origin': '*'},
                'body': json.dumps({'error': 'transaction_id required'})
            }
        
        # Get DB credentials from Secrets Manager
        secrets_client = boto3.client('secretsmanager')
        secret = json.loads(secrets_client.get_secret_value(SecretId=os.environ['DB_SECRET_ARN'])['SecretString'])
        
        # Connect to RDS
        conn = psycopg2.connect(
            host=secret['host'],
            database=secret['dbname'],
            user=secret['username'],
            password=secret['password'],
            sslmode='require'
        )
        
        # Query specific transaction
        cur = conn.cursor()
        cur.execute("SELECT description FROM transactions WHERE transaction_id = %s", (int(transaction_id),))
        row = cur.fetchone()
        
        cur.close()
        conn.close()
        
        # Return result
        result = {transaction_id: row[0] if row else None}
        
        return {
            'statusCode': 200,
            'headers': {'Access-Control-Allow-Origin': '*'},
            'body': json.dumps(result)
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': {'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({'error': str(e)})
        }
