# podlogs
A shell tool to get logfiles from one or multiple Pods / Containers in a Kubernetes environment

The goal was to parse the output for errors and warnings, make the output more readable and tail it
for the last n errors/warnings while using kubectl logs command as basis.

The main usage comes in combination with the other tool named "checkpods" (see my repo), where you
can filter Pods by specific criterias, get them in compact view mode and pass the output with
xargs to podlogs. You can get a pretty good overview over hundreds of Pods in seconds on the 
command line without deeper knowledge of kubectl jsonpath or jq commands.
