'''
Author: Audrey Yang 97855340+wyang10@users.noreply.github.com
Date: 2025-12-31 14:43:07
LastEditors: Audrey Yang 97855340+wyang10@users.noreply.github.com
LastEditTime: 2025-12-31 17:36:22
FilePath: /my-lambda-function/lambda_function.py
Description: 这是默认设置,请设置`customMade`, 打开koroFileHeader查看配置 进行设置: https://github.com/OBKoro1/koro1FileHeader/wiki/%E9%85%8D%E7%BD%AE
'''
def lambda_handler(event, context):
    print(event)
    
    if "contact-info" in event:
        print("Processing order...")
        return event
    else:
        print("ERROR: Contact Info not found!")
        raise Exception("ContactInfoNotFound")