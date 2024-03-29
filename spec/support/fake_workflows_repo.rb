module Spec
  module Support
    class FakeWorkflowsRepo < Spec::Support::FakeGitRepo
      private

      # Generates a single file
      #
      # If it is a reserved file name/path, then the contents are generated,
      # otherwise it will be a empty file.
      #
      def file_content(full_path)
        dummy_workflow_data_for(full_path) if full_path.fnmatch?("**/*.asl", File::FNM_EXTGLOB)
      end

      def dummy_workflow_data_for(_filename)
        <<~WORKFLOW_DATA
          {"Comment": "hello world", "States": {"Start": {"Type": "Succeed"}}, "StartAt": "Start"}
        WORKFLOW_DATA
      end
    end
  end
end
