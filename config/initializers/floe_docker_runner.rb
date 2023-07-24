require "floe"
Floe::Workflow::Runner.docker_runner = ManageIQ::Providers::Workflows::Engine.floe_docker_runner
