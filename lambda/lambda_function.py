import os
import json
import time
import base64
import boto3
from botocore.exceptions import ClientError

s3_client = boto3.client('s3')

def lambda_handler(event, context):
    start_time = time.time()
    
    # Read bucket and prefix strictly from environment variables
    bucket = os.environ.get('BUCKET')
    prefix = os.environ.get('PREFIX', '')
    if prefix and not prefix.endswith('/'):
        prefix += '/'

    # Determine requested path from event (Function URL / API Gateway format)
    raw_path = event.get('rawPath', '')
    if not raw_path and 'requestContext' in event:
        raw_path = event['requestContext'].get('http', {}).get('path', '')
    if not raw_path:
        raw_path = event.get('path', '/')

    status_code = 200
    headers = {}
    is_base64 = False
    body = ""

    function_name = context.function_name if context else os.environ.get('AWS_LAMBDA_FUNCTION_NAME', 'cv-func-23l-3055')

    try:
        if raw_path in ['/', '/index.html']:
            # Fetch index.html
            key = f"{prefix}index.html"
            obj = s3_client.get_object(Bucket=bucket, Key=key)
            content = obj['Body'].read().decode('utf-8')
            
            # Replace placeholder with Lambda and function name
            replacement = f"Lambda {function_name}"
            content = content.replace("{{HOSTED_ON}}", replacement)
            
            status_code = 200
            headers = {
                'Content-Type': 'text/html; charset=utf-8',
                'Cache-Control': 'max-age=60'
            }
            body = content

        elif raw_path == '/style.css':
            # Fetch style.css
            key = f"{prefix}style.css"
            obj = s3_client.get_object(Bucket=bucket, Key=key)
            content = obj['Body'].read().decode('utf-8')
            
            status_code = 200
            headers = {
                'Content-Type': 'text/css; charset=utf-8'
            }
            body = content

        elif raw_path == '/cv.pdf':
            # Fetch binary PDF
            key = f"{prefix}cv.pdf"
            obj = s3_client.get_object(Bucket=bucket, Key=key)
            raw_bytes = obj['Body'].read()
            
            status_code = 200
            headers = {
                'Content-Type': 'application/pdf'
            }
            is_base64 = True
            body = base64.b64encode(raw_bytes).decode('utf-8')

        else:
            # 404 for anything else
            status_code = 404
            headers = {
                'Content-Type': 'text/html; charset=utf-8'
            }
            body = "<!DOCTYPE html><html><head><title>404 Not Found</title></head><body><h1>404 Not Found</h1><p>The requested URL was not found on this server.</p></body></html>"

    except Exception as e:
        status_code = 500
        headers = {'Content-Type': 'text/html'}
        body = f"<html><body><h1>Internal Error</h1><p>{str(e)}</p></body></html>"

    # Compute execution duration in milliseconds
    elapsed_ms = round((time.time() - start_time) * 1000, 2)

    # Log exactly one JSON line per request with fields: fn, path, status, ms
    log_record = {
        "fn": function_name,
        "path": raw_path,
        "status": status_code,
        "ms": elapsed_ms
    }
    print(json.dumps(log_record))

    return {
        'statusCode': status_code,
        'headers': headers,
        'isBase64Encoded': is_base64,
        'body': body
    }
