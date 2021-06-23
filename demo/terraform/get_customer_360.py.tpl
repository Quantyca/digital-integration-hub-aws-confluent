import boto3
from boto3.dynamodb.conditions import Key, Attr


def lambda_handler(event, context):
    dynamodb = boto3.resource('dynamodb')
    
    table = dynamodb.Table('${dynamodb_table_name}')
    
    fe = Attr('CUSTOMER_ID').eq(event['customer_id'])
    response = table.scan(
        FilterExpression=fe        
    )
    items = response['Items']
    
    customer = {
        "CUSTOMER_ID": items[0]['CUSTOMER_ID'],
        "CUSTOMER_FNAME": items[0]['CUSTOMER_FNAME'],
        "CUSTOMER_COUNTRY": items[0]['CUSTOMER_COUNTRY'],
        "CUSTOMER_CITY": items[0]['CUSTOMER_CITY'],
        "CUSTOMER_EMAIL": items[0]['CUSTOMER_EMAIL'],
        "CUSTOMER_LNAME": items[0]['CUSTOMER_LNAME'],
        "ORDERS": []
    }
    
    order_id_list = list(set(elem['ORDER_ID'] for elem in items))
    for order_id in order_id_list:
        order_details = [item for item in items if item["ORDER_ID"] == order_id]
        order = {
            "ORDER_ID": order_id,
            "ORDER_DATE": order_details[0]['ORDER_DATE'],
            "ORDER_DETAILS": []
        }
        for order_detail in order_details:
            order["ORDER_DETAILS"].append({
                "ORDER_DETAILS_ID": order_detail["ORDER_DETAILS_ID"],
                "PRODUCT_NAME": order_detail["PRODUCT_NAME"],
                "PRODUCT_PRICE": order_detail["PRODUCT_PRICE"],
                "PRODUCT_DESC": order_detail["PRODUCT_DESC"],
                "PRODUCT_QTY": order_detail["PRODUCT_QTY"],
            })
        customer["ORDERS"].append(order)
            
    return customer;