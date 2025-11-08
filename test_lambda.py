import json

# Simulate proxy Lambda response
def test_proxy():
    transaction_id = "10234567"
    # This is what proxy returns
    proxy_response = {
        'statusCode': 200,
        'body': json.dumps({transaction_id: "Online purchase at Amazon"})
    }
    print("Proxy Lambda returns:")
    print(json.dumps(proxy_response, indent=2))
    
    # This is what frontend Lambda parses
    lattice_response = proxy_response
    result = json.loads(lattice_response.get('body', '{}'))
    print("\nFrontend Lambda parses body to:")
    print(json.dumps(result, indent=2))
    
    # This is what frontend returns to API Gateway
    frontend_response = {
        'statusCode': 200,
        'headers': {'Access-Control-Allow-Origin': '*'},
        'body': json.dumps(result)
    }
    print("\nFrontend Lambda returns:")
    print(json.dumps(frontend_response, indent=2))
    
    # This is what HTML receives
    html_data = json.loads(frontend_response['body'])
    print("\nHTML receives:")
    print(json.dumps(html_data, indent=2))
    
    # This is what HTML looks for
    description = html_data.get(transaction_id)
    print(f"\nHTML looks for data['{transaction_id}']:")
    print(f"Result: {description}")

test_proxy()
