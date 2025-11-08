import json
import boto3
import os

lambda_client = boto3.client('lambda')

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
        
        # Call RDS proxy Lambda directly cross-account
        response = lambda_client.invoke(
            FunctionName='arn:aws:lambda:us-east-1:466790345536:function:rds-proxy-lambda',
            InvocationType='RequestResponse',
            Payload=json.dumps({'body': json.dumps({'transaction_id': transaction_id})})
        )
        
        # Parse response
        response_payload = json.loads(response['Payload'].read())
        result = json.loads(response_payload.get('body', '{}'))
        
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
