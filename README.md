# samples of work

SCOMWeb_Demo.ps1: .net form for user input, creates application-specific XML, verifies against schema, looks up destination server and merges into master XML file on appropriate server

WeekyTrapConfigDump.ps1: For NNM, parse actions into .csv showing each trap, whether or not it is enabled, and the Perl script called. Also looks at log file for each Perl script and displays last modified timestamp

location_correlation.mrl: For TrueSight, creates 5-minute window and deduplicates specific events based on host name and "TrapData"

datastore_path_correlation.mrl: For TrueSight, create 3-minute window and deduplicate events from same VCenter resource pool

vscode-mrl: source code for https://marketplace.visualstudio.com/items?itemName=mike-mcgrail.mrl
