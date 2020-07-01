import os
import mysql.connector
from mysql.connector import errorcode

config = {
  'user': 'root',
  'password': os.environ['DB_PASS'],
  'host': os.environ['DB_HOST'],
  'database': 'test1',
  'raise_on_warnings': True
}

def db_test(request):
    """Responds to any HTTP request.
    Args:
        request (flask.Request): HTTP request object.
    Returns:
        Response message with db records or error.
    """
    #request_json = request.get_json()

    response_msg = "Oops"

    print("Attempting to connect to database")
    try:
        cnx = mysql.connector.connect(**config)
        cursor = cnx.cursor()

        query = ("SELECT id, name FROM users")
        cursor.execute(query)

        response_msg = "<ul>"

        for (id, name) in cursor:
            response_msg += "<li>{} ({})</li>".format(name, id)
        
        response_msg += "</ul>"

        cursor.close()
        cnx.close()
    except mysql.connector.Error as err:
        print(err)

        if err.errno == errorcode.ER_ACCESS_DENIED_ERROR:
            response_msg = "Something is wrong with your user name or password"
        elif err.errno == errorcode.ER_BAD_DB_ERROR:
            response_msg = "Database does not exist"
        else:
            response_msg = err
    else:
        print("Closing DB connection ...")
        cnx.close()

    print("Returning: {}".format(response_msg))
    return response_msg