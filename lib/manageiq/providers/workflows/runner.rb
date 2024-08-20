module ManageIQ
  module Providers
    module Workflows
      class Runner
        include Vmdb::Logging

        class << self
          def runner
            @runner ||= new.tap(&:start)
          end
        end

        attr_reader :workflows

        def initialize
          require "floe"
          require "concurrent/hash"

          @workflows          = Concurrent::Hash.new
          @docker_wait_thread = nil
        end

        def start
          $workflows_log.debug("Runner: Starting workflows runner...")
          self.docker_wait_thread = Thread.new { docker_wait }
          $workflows_log.debug("Runner: Starting workflows runner...Complete")
        end

        def stop
          $workflows_log.debug("Runner: Stopping workflows runner...")
          stop_thread(docker_wait_thread)

          self.docker_wait_thread = nil
          $workflows_log.debug("Runner: Stopping workflows runner...Complete")
        end

        def add_workflow(workflow, queue_args)
          workflows[workflow.id] ||= [workflow, queue_args]
        end

        def delete_workflow(workflow)
          workflows.delete(workflow.id)
        end

        private

        attr_accessor :docker_wait_thread

        def docker_wait
          loop do
            docker_runner = Floe::Runner.for_resource("docker")
            docker_runner.wait do |event, runner_context|
              $workflows_log.info("Runner: Caught event [#{event}] for container [#{runner_context["container_ref"]}]")

              workflow, queue_args = workflow_by_runner_context(runner_context)
              next if workflow.nil?

              $workflows_log.info("Runner: Queueing update for WorkflowInstance ID: [#{workflow.id}]")

              workflow.run_queue(**queue_args)
            end
          rescue => err
            $workflows_log.warn("Error: [#{err}]")
            $workflows_log.log_backtrace(err)
          end
        end

        def stop_thread(thread)
          return if thread.nil?

          thread.kill
          thread.join(0)
        end

        def workflow_by_runner_context(runner_context)
          workflows.detect do |_id, (workflow, _queue_args)|
            context       = workflow.reload.context
            container_ref = context.dig("State", "RunnerContext", "container_ref")

            container_ref == runner_context["container_ref"]
          end&.last
        end
      end
    end
  end
end
