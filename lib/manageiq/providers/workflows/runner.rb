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

        attr_reader :workflow_instances

        def initialize
          require "floe"
          require "concurrent/hash"

          @workflow_instances = Concurrent::Hash.new
          @docker_wait_thread = nil
        end

        def start
          $workflows_log.debug("Runner: Starting workflows runner...")
          self.docker_wait_thread = Thread.new { loop { docker_wait } }
          $workflows_log.debug("Runner: Starting workflows runner...Complete")
        end

        def stop
          $workflows_log.debug("Runner: Stopping workflows runner...")
          stop_thread(docker_wait_thread)

          self.docker_wait_thread = nil
          $workflows_log.debug("Runner: Stopping workflows runner...Complete")
        end

        def add_workflow_instance(workflow_instance, queue_args)
          workflow_instances[workflow_instance.manager_ref] ||= [workflow_instance, queue_args]
        end

        def delete_workflow_instance(workflow_instance)
          workflow_instances.delete(workflow_instance.manager_ref)
        end

        private

        attr_accessor :docker_wait_thread

        def docker_wait
          docker_runner = Floe::Runner.for_resource("docker")
          docker_runner.wait do |event, data|
            execution_id, runner_context = data.values_at("execution_id", "runner_context")
            $workflows_log.debug("Runner: Caught event [#{event}] for workflow [#{execution_id}] container [#{runner_context["container_ref"]}]")

            workflow_instance, queue_args = workflow_instances[execution_id]
            next if workflow_instance.nil?

            $workflows_log.debug("Runner: Queueing update for WorkflowInstance ID: [#{workflow_instance.id}]")

            workflow_instance.run_queue(**queue_args)
          end
        rescue => err
          $workflows_log.warn("Error: [#{err}]")
          $workflows_log.log_backtrace(err)
        end

        def stop_thread(thread)
          return if thread.nil?

          thread.kill
          thread.join(0)
        end
      end
    end
  end
end
