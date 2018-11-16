# trees
Delta packages based on ostree repos (pine,trub).

The deltas are built following the base image revisions.

## Templates
In templates are stored:
- specific configurations for each application in their own subfolders
- `runc.json` the default container `OCI` specification used
- `runc.sh` the shell wrapper to the `runc` container runtime
- `containerpilot.json5` the template used by the runc shell wrapper 
which uses the specific application configuration to generate the containerpilot config file

## image.conf
Used for additional container configurations, like limits and for container runtime env vars
## image.env
- `services` space separated list of processes that will run inside the container
- `x_exec` base command to execute for service `x` (defaults to service name)
- `x_args` double comma separated list of arguments to pass to service command
- `x_port` port the service is listenining to
- `x_res` resources specification for service
- `x_when_src` when to start checking
- `x_when_freq` when to
- `x_health_exec` command for health checks
- `watches` services to monitor with consul
- `watch_x_inter` service check interval 

##### TODO
- cross-version package deltas (not urgent)
