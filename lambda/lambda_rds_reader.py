import json
import urllib3
import os

http = urllib3.PoolManager()

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
        
        # Call VPC Lattice proxy Lambda via HTTPS
        vpc_lattice_endpoint = os.environ['VPC_LATTICE_ENDPOINT']
        if not vpc_lattice_endpoint.startswith('http'):
            vpc_lattice_endpoint = f'https://{vpc_lattice_endpoint}'
        
        response = http.request(
            'POST',
            vpc_lattice_endpoint,
            body=json.dumps({'transaction_id': transaction_id}),
            headers={'Content-Type': 'application/json'},
            timeout=25.0
        )
        
        # Parse response
        result = json.loads(response.data.decode('utf-8'))
        
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
