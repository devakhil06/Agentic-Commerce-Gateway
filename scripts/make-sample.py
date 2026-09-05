"""Export the deterministic SRS demo catalog without invoking a model or API."""
import ast
import csv
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
tree = ast.parse((root / 'backend/app/seed.py').read_text())
function = next(node for node in tree.body if isinstance(node, ast.AsyncFunctionDef))
assignment = next(node for node in function.body if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'bases' for t in node.targets))
bases = ast.literal_eval(assignment.value)
target = root / 'examples/electronics-100.csv'
target.parent.mkdir(exist_ok=True)
with target.open('w', newline='', encoding='utf-8') as file:
    writer = csv.DictWriter(file, fieldnames=['sku','name','category','price','cost','stock','description','attributes','compatibility','delivery_days','return_days','warranty'])
    writer.writeheader()
    for variant in range(10):
        for prefix, name, category, price, cost, attributes, description in bases:
            writer.writerow({'sku':f'{prefix}-{variant+1:03}', 'name':name+(f' · Series {variant+1}' if variant else ''), 'category':category, 'price':price+variant*100, 'cost':cost, 'stock':0 if variant==9 else 60-variant*3, 'description':description, 'attributes':json.dumps(attributes), 'compatibility':json.dumps([f'HDP-{variant+1:03}'] if prefix=='ADP' else ([f'LAP-{variant+1:03}'] if prefix in ('CHR','HUB') else [])), 'delivery_days':3+variant%3, 'return_days':7, 'warranty':'1 year manufacturer warranty'})
print('Wrote examples/electronics-100.csv (100 products, INR rupees).')
