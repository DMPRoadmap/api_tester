# DMPRoadmap API Tester

This application can be used to verify that the API of a running DMPRoadmap system is functioning and configured properly.

## Installation:

Install all of the necessary gem dependencies:
Run `bundle install`

Startup the Sinatra based test app:
Run `ruby api_test.rb`

Load the test site in your browser at `http://localhost:4567`. Then:
1. Enter the hostname of the system you want to test (e.g. http://localhost:3000)
2. Select the API version you want to test and click 'Start testing'
3. On the version specific page, enter the necessary credentials and the the button for the test you want to run.

## Notes

You must have DMPRoadmap running either locally or on a server!

If your version of DMPRoadmap does not support a specific version of the API, then those tests will fail! To see what versions of the API your installation supports, check the `[project root path]/app/controllers/api/` directory of your DMPRoadmap system.

Please do not use this test suite to verify other organization's DMPRoadmap systems. It should only be used to test your own installations.

All tests are meant to simply verify the basic request/response cycle of the API they do not test that the content of responses are accurate. Simply receiving an HTTP 200/201 is considered a successful test for this application.

Any tests that attempt to retrieve a PDF document will be displayed as a string in the response. The test just ensures that the API responds properly. It does not attempt to ensure that the response is a valid PDF document. See the DMPRoadmap integration tests for verifying proper PDF creation.

## Further reading

See the [DMPRoadmap wiki](https://github.com/DMPRoadmap/roadmap/wiki/) for more info on how to use each of the API versions.

