# encoding = utf-8
# Author: Mike McGrail
# Date: Oct 1, 2021
# Written for customer

import os
import sys
import time
import datetime
import json
import requests
import dateutil.parser

'''
    IMPORTANT
    Edit only the validate_input and collect_events functions.
    Do not edit any other part in this file.
    This file is generated only once when creating the modular input.
'''

# If you want to create single instance mod input, uncomment this method.
def use_single_instance_mode():
    return True

def validate_input(helper, definition):
    #plant = definition.parameters.get('plant', None)'
    #Not currently validating inputs, will catch with try/except in collect_events
    pass

def get_checkpoint(helper, key):
    state = helper.get_check_point(key)

    #if state exists, return it
    if (state not in [None,'']):
        return state
    #if nonexistent, set to 0 for 1st iteration
    else:
        helper.log_debug("ta_mike no existing checkpoint for key=%s, saving as 0" % str(key))
        helper.save_check_point(key, 0)
        return 0
        
def write_events(helper, ew, input_type, stanza_name, data):
    event = helper.new_event(source=input_type, index=helper.get_output_index(stanza_name), sourcetype=helper.get_sourcetype(stanza_name), data=data)
    ew.write_event(event)

def collect_events(helper, ew):
  
  '''
  sample data:
  {
    "ICS_DATA": [
        {
            "DATA": {
                "SEQUENCE": "001",
                "NUMBER": "00001",
                "PLANT": "1",
                "SECTION": "A0",
                "NOTES": "HELLO WORLD",
                "CREATION_TIME": "2021-01-01T00:00:01"
            }
        },...
   
  Below code extracts and retains only nested json inside "DATA"{}
  '''
  
  
    input_type = helper.get_input_type()
    #iterate through input stanzas (one input stanza per plant)
    for stanza_name in helper.get_input_stanza_names():
        plant_endpoint = helper.get_arg('plant', stanza_name)
        helper.log_info("ta_mike stanza_name=%s plant_endpoint=%s" % (str(stanza_name), str(plant_endpoint)))
        
        try:
            #use requests module GET method -> text -> JSON
            ics_details=json.loads(requests.get(plant_endpoint).text)
            #ics_details=json.load(open('/opt/splunk821/splunk/tracking.json',)) #for testing local file, uncomment this line and comment line above
            
            #set checkpoint time
            checkpoint_key = stanza_name + "_key"
            checkpoint_time = get_checkpoint(helper, checkpoint_key)
            count = 0
            
            #iterate through response
            for nested_data in ics_details["ICS_DATA"]:
                #convert CREATION_TIME to epoch timestamp
                timestamp = datetime.datetime.strptime(nested_data["DATA"]["CREATION_TIME"],'%Y-%m-%dT%H:%M:%S')
                event_time = (timestamp - datetime.datetime(1970, 1, 1)).total_seconds()
            
                #get timestamp for first result to use as checkpoint
                if count==0:
                    first_time = event_time
                    
                #compare time, drop events older than checkpoint
                if event_time > checkpoint_time:
                    data = json.dumps(nested_data["DATA"])
                    write_events(helper, ew, input_type, stanza_name, data)
                    helper.log_debug("ta_mike writing event, event_time=%s checkpoint_time=%s" % (str(event_time), str(checkpoint_time)))
                else:
                    helper.log_debug("ta_mike skipping event, event_time=%s checkpoint_time=%s" % (str(event_time), str(checkpoint_time)))
                
                count+=1
            
            #done with JSON response, upodate checkpoint for this stanza
            max_time = max(first_time, checkpoint_time)
            helper.log_info("ta_mike events for stanza_name=%s indexed" % str(stanza_name))
            helper.save_check_point(checkpoint_key, max_time)
            
        except Exception as e:
            helper.log_error(e)
        
    
        '''
        #to delete checkpoint keys, uncomment this section
        checkpoint_key = stanza_name + "_key"
        helper.delete_check_point(checkpoint_key)
        helper.log_debug("deleting checkpoint for stanza %s" % str(stanza_name))
        '''
