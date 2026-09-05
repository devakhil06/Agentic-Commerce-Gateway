"""Exercise an isolated development workspace over HTTP without API credentials."""
import argparse
import httpx

parser = argparse.ArgumentParser()
parser.add_argument('--base-url', default='http://127.0.0.1:8080')
args = parser.parse_args()
with httpx.Client(base_url=args.base_url, timeout=90) as client:
    assert client.get('/').status_code == 200
    assert client.get('/api/health').json()['status'] == 'ok'
    response = client.post('/api/v1/auth/demo')
    response.raise_for_status()
    account = response.json()
    client.headers['Authorization'] = 'Bearer '+account['access_token']
    catalog = client.get('/api/v1/catalog/products').json()['products']
    assert len(catalog) == 100
    response = client.post('/api/v1/commerce/discover', json={'message':'Wireless headphones under ₹8,000 for gaming and office meetings'})
    response.raise_for_status()
    discovery = response.json()
    assert discovery['candidates']
    assert all(p['price'] <= 800000 and p['attributes']['wireless'] for p in discovery['candidates'])
    product = discovery['candidates'][0]
    response = client.post('/api/v1/commerce/negotiate', json={'session_id':discovery['session_id'], 'lines':[{'product_id':product['id'],'quantity':1}], 'offered_total':product['price']*96//100})
    response.raise_for_status()
    negotiation = response.json()
    assert negotiation['status'] == 'OFFER_CREATED'
    response = client.post('/api/v1/commerce/quote', json={'negotiation_id':negotiation['id']})
    response.raise_for_status()
    assert response.json()['status'] == 'RESERVED'
    assert client.get('/api/v1/audit').json()['events']
    assert client.get('/api/v1/analytics/revenue').json()['revenue'] == 0
    print('HTTP smoke passed: release page, authentication, 100 products, constrained discovery, negotiation, reserved quote, audit, and zero unverified revenue.')
    print('Provider checkout was deliberately not invoked by this smoke test.')
