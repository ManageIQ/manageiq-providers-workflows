module ManageIQ
  module Providers
    module Workflows
      class Runner
        include Singleton
        include Vmdb::Logging

        attr_reader :workflows

        def initialize
          require "floe"
          require "concurrent/hash"

          @workflows              = Concurrent::Array.new
          @event_queue            = Queue.new
          @workflow_runner_thread = nil
          @docker_wait_thread     = nil
        end

        def start
          self.workflow_runner_thread = Thread.new { workflow_runner }
          self.docker_wait_thread     = Thread.new { docker_wait }
        end

        def stop
          stop_thread(workflow_runner_thread)
          stop_thread(docker_wait_thread)

          self.workflow_runner_thread = nil
          self.docker_wait_thread     = nil
        end

        def add_workflow(wf)
          workflows << wf
          event_queue.push(nil)
          wf
        end

        def delete_workflow(wf)
          workflows.delete(wf)
        end

        private

        attr_accessor :docker_wait_thread, :event_queue, :workflow_runner_thread

        def workflow_runner
          loop do
            ready = workflows.select { |wf| wf.floe_workflow.step_nonblock_ready? }
            $workflows_log.info("Got [#{ready.count}] ready workflows") if ready.count > 0

            ready.each do |wf|
              wf.floe_workflow.run_nonblock
            end

            finished_workflows = workflows.select(&:end?)
            finished_workflows.each do |wf|
              $workflows_log.info("Workflow [#{wf.context.dig("Execution", "Id")}] finished, output: [#{wf.output}]")
              workflows.delete(wf)
            end

            wait_until        = workflows.map(&:wait_until).compact.min
            sleep_duration    = wait_until - Time.now.utc if wait_until
            wait_until_thread = Thread.new { sleep sleep_duration; event_queue.push(nil) } if sleep_duration && sleep_duration > 0

            event, runner_context = event_queue.pop
            stop_thread(wait_until_thread)
            next if event.nil?

            workflows.each do |wf|
              wf_container_ref = wf.context.state.dig("RunnerContext", "container_ref")
              next if wf_container_ref != runner_context["container_ref"]

              wf.context.state["RunnerContext"] = runner_context
            end
          rescue => err
            $workflows_log.warn("Error: [#{err}]")
            $workflows_log.log_backtrace(err)
          end
        end

        def docker_wait
          loop do
            docker_runner = Floe::Runner.for_resource("docker")
            docker_runner.wait { |event, runner_context| event_queue.push([event, runner_context])}
            sleep 1
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
      end
    end
  end
end
