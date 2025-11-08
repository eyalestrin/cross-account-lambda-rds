import json
import psycopg2
import os

def lambda_handler(event, context):
    try:
        # Parse event body
        body = json.loads(event.get('body', '{}'))
        transaction_id = body.get('transaction_id')
        sql = body.get('sql')
        
        # Connect to RDS
        conn = psycopg2.connect(
            host=os.environ['DB_HOST'],
            database=os.environ['DB_NAME'],
            user=os.environ['DB_USER'],
            password=os.environ['DB_PASSWORD']
        )
        cur = conn.cursor()
        
        # Execute SQL or query transaction
        if sql:
            cur.execute(sql)
            conn.commit()
            result = {'message': 'SQL executed successfully'}
        elif transaction_id:
            cur.execute("SELECT description FROM transactions WHERE transaction_id = %s", (int(transaction_id),))
            row = cur.fetchone()
            result = {str(transaction_id): row[0] if row else None}
        else:
            result = {'error': 'No sql or transaction_id provided'}
        
        cur.close()
        conn.close()
        
        return {
            'statusCode': 200,
            'body': json.dumps(result)
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
