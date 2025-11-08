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
        vpc_lattice_endpoint = os.environ.get('VPC_LATTICE_ENDPOINT')
        if not vpc_lattice_endpoint:
            return {
                'statusCode': 500,
                'headers': {'Access-Control-Allow-Origin': '*'},
                'body': json.dumps({'error': 'VPC_LATTICE_ENDPOINT not configured'})
            }
        
        if not vpc_lattice_endpoint.startswith('http'):
            vpc_lattice_endpoint = f'https://{vpc_lattice_endpoint}'
        
        response = http.request(
            'POST',
            vpc_lattice_endpoint,
            body=json.dumps({'transaction_id': transaction_id}),
            headers={'Content-Type': 'application/json'},
            timeout=50.0,
            retries=False
        )
        
        # Parse VPC Lattice response (has nested body)
        lattice_response = json.loads(response.data.decode('utf-8'))
        result = json.loads(lattice_response.get('body', '{}'))
        
        return {
            'statusCode': 200,
            'headers': {'Access-Control-Allow-Origin': '*'},
            'body': json.dumps(result)
        }
    except urllib3.exceptions.TimeoutError as e:
        return {
            'statusCode': 504,
            'headers': {'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({'error': f'VPC Lattice timeout: {str(e)}'})
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': {'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({'error': str(e)})
        }
