module ManageIQ
  module Providers
    module Workflows
      class BuiltinMethods < Floe::BuiltinRunner::Methods
        def self.api(params, secrets, context)
          return BuiltinRunner.error!({}, :cause => "You must provide either Url or Path, not both") if params.key?("Url") && params.key?("Path")

          unless params.key?("Url")
            path         = params.delete("Path") || "/"
            api_base_url = context.execution["_manageiq_api_url"]

            params["Url"] ||= ::URI.join(api_base_url, path).to_s
          end

          params["Options"] ||= {}
          params["Options"]["Encoding"] ||= "JSON"

          params["Headers"] ||= {}
          params["Headers"]["ContentType"] ||= "application/json"

          http(params, secrets, context)
        end

        def self.email(params, _secrets, context)
          options = params.slice("To", "From", "Subject", "Cc", "Bcc", "Body", "Attachment").transform_keys { |k| k.downcase.to_sym }
          options[:from] ||= ::Settings.smtp.from
          options[:to]   ||= context.execution["_requester_email"]
          miq_task = ::GenericMailer.deliver_task(:generic_notification, options)

          {"miq_task_id" => miq_task.id}
        end

        private_class_method def self.email_status!(runner_context)
          miq_task_status!(runner_context)
        end

        def self.embedded_ansible(params, _secrets, _context)
          repository_url, repository_branch, playbook_name, playbook_id = params.values_at("RepositoryUrl", "RepositoryBranch", "PlaybookName", "PlaybookId")

          vars = params
                 .slice("Hosts", "ExtraVars", "BecomeEnabled", "Timeout", "Verbosity", "CredentialId", "CloudCredentialId", "NetworkCredentialId", "VaultCredentialId")
                 .transform_keys { |k| k.underscore.to_sym }

          vars[:execution_ttl] = vars.delete(:timeout) if vars.key?(:timeout)
          %i[credential_id cloud_credential_id network_credential_id vault_credential_id].each do |key|
            new_key = key.to_s.chomp("_id").to_sym
            vars[new_key] = vars.delete(key) if vars.key?(key)
          end

          if playbook_id
            playbook = ::ConfigurationScriptPayload.find_by(:id => playbook_id)
            return BuiltinRunner.error!({}, :cause => "Unable to find Playbook: Id: [#{playbook_id}] Repository: [#{repository.name}]") if playbook.nil?
          else
            repository = ::ConfigurationScriptSource.find_by(:scm_url => repository_url, :scm_branch => repository_branch)
            return BuiltinRunner.error!({}, :cause => "Unable to find Repository: URL: [#{repository_url}] Branch: [#{repository_branch}]") if repository.nil?

            playbook = ::ConfigurationScriptPayload.find_by(:configuration_script_source => repository, :name => playbook_name)
            return BuiltinRunner.error!({}, :cause => "Unable to find Playbook: Name: [#{playbook_name}] Repository: [#{repository.name}]") if playbook.nil?
          end

          unless playbook.class <= ::ManageIQ::Providers::EmbeddedAnsible::AutomationManager::Playbook
            return BuiltinRunner.error!({}, :cause => "Invalid playbook: ID: [#{playbook.id}] Type: [#{playbook.type}]")
          end

          job = playbook.run(vars)

          {"miq_task_id" => job.miq_task_id}
        end

        private_class_method def self.embedded_ansible_status!(runner_context)
          miq_task_status!(runner_context)
        end

        def self.provision_execute(_params, _secrets, context)
          object_type, object_id = context.execution.values_at("_object_type", "_object_id")
          return BuiltinRunner.error!({}, :cause => "Missing MiqRequestTask type") if object_type.nil?
          return BuiltinRunner.error!({}, :cause => "Missing MiqRequestTask id")   if object_id.nil?

          miq_request_task = ::MiqRequestTask.find_by(:id => object_id.to_i)
          return BuiltinRunner.error!({}, :cause => "Unable to find MiqReqeustTask id: [#{object_id}]")                        if miq_request_task.nil?
          return BuiltinRunner.error!({}, :cause => "Calling provision_execute on non-provisioning request: [#{object_type}]") unless miq_request_task.class < ::MiqProvisionTask

          new_options = context.input.symbolize_keys.slice(*miq_request_task.options.keys)
          miq_request_task.options_will_change!
          miq_request_task.options.merge!(new_options)
          miq_request_task.save!
          miq_request_task.execute_queue

          {"miq_request_task_id" => miq_request_task.id}
        end

        private_class_method def self.provision_execute_status!(runner_context)
          miq_request_task_status!(runner_context)
        end

        def self.retire_execute(params, _secrets, context)
          object_type, object_id = context.execution.values_at("_object_type", "_object_id")
          return BuiltinRunner.error!({}, :cause => "Missing MiqRequestTask type") if object_type.nil?
          return BuiltinRunner.error!({}, :cause => "Missing MiqRequestTask id")   if object_id.nil?

          miq_request_task = ::MiqRequestTask.find_by(:id => object_id.to_i)
          return BuiltinRunner.error!({}, :cause => "Unable to find MiqReqeustTask id: [#{object_id}]")               if miq_request_task.nil?
          return BuiltinRunner.error!({}, :cause => "Calling retire_execute on non-retire request: [#{object_type}]") unless miq_request_task.class < ::MiqRetireTask

          new_options = params.transform_keys { |k| k.underscore.to_sym }

          miq_request_task.options_will_change!
          miq_request_task.options.merge!(new_options)
          miq_request_task.save!
          miq_request_task.execute_queue

          {"miq_request_task_id" => miq_request_task.id}
        end

        private_class_method def self.retire_execute_status!(runner_context)
          miq_request_task_status!(runner_context)
        end

        # general methods

        private_class_method def self.miq_task_status!(runner_context)
          miq_task = ::MiqTask.find_by(:id => runner_context["miq_task_id"])
          return BuiltinRunner.error!(runner_context, :cause => "Unable to find MiqTask id: [#{runner_context["miq_task_id"]}]") if miq_task.nil?

          runner_context["running"] = miq_task.state != ::MiqTask::STATE_FINISHED

          unless runner_context["running"]
            runner_context["success"] = miq_task.status == ::MiqTask::STATUS_OK
            if runner_context["success"]
              runner_context["output"] = miq_task.message
            else
              BuiltinRunner.error!(runner_context, :cause => miq_task.message)
            end
          end

          runner_context
        end

        private_class_method def self.miq_request_task_status!(runner_context)
          miq_request_task = ::MiqRequestTask.find_by(:id => runner_context["miq_request_task_id"])

          case miq_request_task&.statemachine_task_status
          when nil
            reason = "Unable to find MiqRequestTask id: [#{runner_context["miq_request_task_id"]}]"
            BuiltinRunner.error!(runner_context, :cause => reason)
          when "error"
            reason = miq_request_task.message&.sub(/^Error: /, "")
            BuiltinRunner.error!(runner_context, :cause => reason)
          when "retry"
            runner_context["running"] = true
            runner_context
          when "ok"
            BuiltinRunner.success!(runner_context, :output => {"Result" => miq_request_task.completed_state})
          end
        end
      end
    end
  end
end
