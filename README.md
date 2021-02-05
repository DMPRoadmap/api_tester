# v1_api_tester

This script can be used to verify that the V1 API of a DMPRoadmap system is functioning and configured properly.

## Testing the API

This script reqires that you have an instance of the DMPRoadmap system running locally or on a server that you have access to.

Please note that it only tests the API as an ApiClient (e.g. an external system) not an individual User.

To run it you must pass in 3 arguments: the host, your client id and your client secret.
For example: `ruby dmproadmap_api_tester.rb http://localhost:3000 1234567890 0987654321`

If you do not yet have an API Client, you can create one by logging into the DMPRoadmap system as a SuperAdmin and then navigating to the 'Api Clients' page via the 'Admin' menu. The system will auto-generate your client_id and client_secret once the record has been created.

## Further reading

See the [API V1 Documentation](https://github.com/DMPRoadmap/roadmap/wiki/API-Documentation-V1) for more info on how to use the API.

