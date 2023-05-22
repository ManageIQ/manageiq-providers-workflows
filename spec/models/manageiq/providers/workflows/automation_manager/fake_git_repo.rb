class FakeGitRepo
  attr_reader :file_struct, :repo_path, :repo, :index

  def self.generate(repo_path, file_struct)
    new(repo_path, file_struct).generate
  end

  def initialize(repo_path, file_struct)
    @repo_path   = Pathname.new(repo_path)
    @name        = @repo_path.basename
    @file_struct = file_struct
  end

  def generate
    build_repo(repo_path, file_struct)

    git_init
    git_add_all
    git_commit_initial
  end

  # Create a new branch (don't checkout)
  #
  #   $ git branch other_branch
  #
  def git_branch_create(new_branch_name)
    repo.create_branch(new_branch_name)
  end

  private

  # Generate repo structure based on file_structure array
  #
  # By providing a directory location and an array of paths to generate,
  # this will build a repository directory structure.  If a specific entry
  # ends with a '/', then an empty directory will be generated.
  #
  # Example file structure array:
  #
  #     file_struct = %w[
  #       roles/defaults/main.yml
  #       roles/meta/main.yml
  #       roles/tasks/main.yml
  #       host_vars/
  #       hello_world.yml
  #     ]
  #
  def build_repo(repo_path, file_structure)
    file_structure.each do |entry|
      path          = repo_path.join(entry)
      dir, filename = path.split unless entry.end_with?("/")
      FileUtils.mkdir_p(dir || entry)

      next unless filename

      build_file(dir, filename)
    end
  end

  # Generates a single file
  #
  # If it is a reserved file name/path, then the contents are generated,
  # otherwise it will be a empty file.
  #
  def build_file(repo_rel_path, entry)
    full_path = repo_rel_path.join(entry)
    content   = if filepath_match?(full_path, "**/*.asl")
                  dummy_workflow_data_for(full_path.basename)
                end

    File.write(full_path, content)
  end

  # Given a collection of glob based `File.fnmatch` strings, confirm
  # whether any of them match the given path.
  #
  def filepath_match?(path, *acceptable_matches)
    acceptable_matches.any? { |match| path.fnmatch?(match, File::FNM_EXTGLOB) }
  end

  # Init new repo at local_repo
  #
  #   $ cd /tmp/clone_dir/hello_world_local && git init .
  #
  def git_init
    @repo  = Rugged::Repository.init_at(repo_path.to_s)
    @index = repo.index
  end

  # Add new files to index
  #
  #   $ git add .
  #
  def git_add_all
    index.add_all
    index.write
  end

  # Create initial commit
  #
  #   $ git commit -m "Initial Commit"
  #
  def git_commit_initial
    author = {:email => "admin@localhost", :name => "admin", :time => Time.now.utc}

    Rugged::Commit.create(
      repo,
      :message    => "Initial Commit",
      :parents    => [],
      :tree       => index.write_tree(repo),
      :update_ref => "HEAD",
      :author     => author,
      :committer  => author
    )
  end

  def dummy_workflow_data_for(_filename)
    <<~WORKFLOW_DATA
      {"Comment": "hello world"}
    WORKFLOW_DATA
  end
end
