###
# Confirm connectivity from Splunk to SentinelOne
# Instructions:
# 1. Place script in desired location (e.g.: /tmp/splunk_test_script.py)
# 2. Replace line 16 <token> with SentinelOne API log read token
# 3. Navigate to Splunk bin directory (e.g: /opt/splunk/bin/)
# 4. Execute the command  ./splunk cmd python /tmp/splunk_test_script.py
# Note: replace /tmp/splunk_test_script.py if different
####

import requests
import json

datasetConfig = {
    "endpoint": "https://app.us1.dataset.com/api/query",
    "token": "<token>" #TODO: replace <string> with SentinelOne log read API key
}

def main():
    payload = '{"queryType": "log","startTime": "1h"}'
    payload = json.loads(payload)
    ds_headers = { "Authorization": "Bearer " + datasetConfig["token"] }

    try:
        r = requests.post(url=datasetConfig["endpoint"], json=payload, headers=ds_headers)
        r_json = r.json()
        print(r_json)
    except:
        print("failed to connect or parse results")

if __name__ == "__main__":
    main()
