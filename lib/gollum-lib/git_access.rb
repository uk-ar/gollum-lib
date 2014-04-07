# ~*~ encoding: utf-8 ~*~
require 'rugged'
module Grit
  class InvalidGitRepositoryError < StandardError
  end
  class NoSuchPathError < StandardError
  end
  class InvalidObjectType < StandardError
  end
  module GitRuby
    class Repository
      class NoSuchShaFound < StandardError
      end
      class NoSuchPath < StandardError
      end
    end
  end
  class Tree
    attr_reader :rugged_tree
    def initialize(rugged_tree)
      @rugged_tree = rugged_tree
    end
    def id
      @rugged_tree.oid
    end
    def path(path)
      @rugged_tree.path(path)
    end
    def /(file)
      if file =~ /\//
        file.split("/").inject(self) { |acc, x| acc/x } rescue nil
      else
        begin
          obj = @rugged_tree.path(file)
          Tree.new(@rugged_tree.owner.lookup(obj[:oid])) if
            obj[:type] == :tree
        rescue Rugged::TreeError
        end
      end
    end
    def walk_blobs(mode=:postorder)
      @rugged_tree.walk_blobs(mode){|root, b| yield root, b }
    end
    def blobs
      # @rugged_tree.blobs.each
      self
    end
    def each
      @rugged_tree.each_blob.map{ |x| Blob.new(x) }.each{ |x| yield x }
    end
  end
  class Index
    attr_reader :current_tree, :tree, :rugged_repo, :repo #:rugged_index,
    # ref branch name
    def inspect
      "#<Grit::Index:#{object_id} {current_tree: #{current_tree}, tree:#{tree}, rugged_repo: #{rugged_repo}, repo: #{repo}}>"
    end
    def initialize(repo)
      @repo = repo #Grit
      @rugged_repo = repo.rugged_repo
      # if repo.kind_of?(Grit::Repo)
      # else
      #   @rugged_repo = repo
      # end
      @tree = {}
      @current_tree = nil
    end
    def read_tree(treeish)
      tree = @repo.commit(treeish)
      tree = @rugged_repo.lookup(tree.target_id) if tree.type == :direct
      tree = tree.tree if tree.type == :commit
      tree = tree.rugged_tree if tree.class == Grit::Tree
      #p tree
      @rugged_repo.index.read_tree(tree)
      @current_tree = Tree.new(tree)#, @rugged_repo)
    end
    def mkdir_p(path)
      #https://gist.github.com/uniphil/9570964
      path_parts = path.split('/')
      if path_parts.size == 1

      end
    end
    def add(path, data)
      oid = @rugged_repo.write(data, :blob)
      @rugged_repo.index.add(:path => path, :oid => oid, :mode => 0100644)
      @rugged_repo.index.write
      add_grit(path, data)
    end
    def commit(message, parents = nil, actor = nil, last_tree = nil, head = 'master')
      options = {}
      options[:tree] = @rugged_repo.index.write_tree(@rugged_repo)
      options[:author] = { :email => actor.email , :name => actor.name, :time => Time.now } if actor
      options[:committer] = { :email => actor.email , :name => actor.name, :time => Time.now } if actor
      options[:message] = message || ''
      options[:parents] = @rugged_repo.empty? ? [] : [ @rugged_repo.head.target ].compact
      options[:update_ref] = "refs/heads/" + head #head #'HEAD'
      Rugged::Commit.create(@rugged_repo, options)
    end
    def delete(path)
      # @rugged_index.remove(path)
      head_sha = @rugged_repo.references['HEAD'].resolve.target_id
      tree = @rugged_repo.lookup(head_sha).tree

      index = @rugged_repo.index
      index.read_tree(tree)
      @rugged_repo.index.remove(path)

      index_tree_sha = index.write_tree
      index_tree = @rugged_repo.lookup(index_tree_sha)
      # Grit::Tree for '/' method
      @current_tree = Tree.new(index_tree)#, @rugged_repo)
      # @tree[path] = false
      add_grit(path, false)
      # p "tree", @tree, @current_tree.rugged_tree
      # index.read_tree(@current_tree.rugged_tree)
      # index.remove(path)
      # sha = index.write_tree
    end
    # copy from grit
    def add_grit(path, data)
      path = path.split('/')
      filename = path.pop

      current = @tree

      path.each do |dir|
        current[dir] ||= {}
        node = current[dir]
        current = node
      end

      current[filename] = data
    end
  end
  class Blob
    attr_reader :rugged_blob, :name, :oid, :filemode, :type, :mode
    def initialize(blob,rblob=nil)
      @rugged_blob = rblob
      @name = blob[:name]
      @oid = blob[:oid]
      # @filemode = blob[:filemode]
      @mode = blob[:mode]
      @type = blob[:type]
    end
    def data
      @rugged_blob.read_raw.data
    end
    def self.create(repo, atts)
      #{:id=>"4571349a92aa180e230345e4e44c9be7d9d4f96c", :name=>"Elrond.md", :size=>nil, :mode=>33188}
      # p "at", atts
      obj=repo.rugged_repo.lookup(atts[:id])
      self.new({:name => atts[:name], :mode => atts[:mode]}, obj)
                #:oid => atts[:id]},)#:oid => atts[:id]
      # obj.name = atts[:name]
      # obj.mode = atts[:mode]
      #obj
    end
  end
  class Commit
    attr_reader :rugged_commit,:type, :id
    # commit or branch
    def to_s
      id
    end
    def inspect
      %Q{#<Grit::Commit "#{id}" "#{object_id}">}
    end
    def self.list_from_string(repo, text)
      text
    end
    def initialize(rugged_commit)
      @rugged_commit = rugged_commit
      @type = :commit
      #p "type:", rugged_commit.type
      # if rugged_commit.type ==
      #   @id = @rugged_commit.oid
      # else
      #   @id = @rugged_commit.target_id
      # end
    end
    def id
      @rugged_commit.oid
    end
    def sha
      @rugged_commit.oid
    end
    def message
      @rugged_commit.message
    end
    def tree
      return Tree.new(@rugged_commit.tree) if @rugged_commit.type == :commit
      return @rugged_commit if @rugged_commit.type == :tree
    end
    # Grit::GitRuby::Commit
    def author
      a = @rugged_commit.author
      Actor.new(a[:name], a[:email])
    end
    def parents
      @rugged_commit.parents
      #@rugged_commit.parents.map{ |parent| Commit.new(parent)}
    end
  end
  class Actor
    attr_reader :email, :name
    def initialize(name, email)
      @email = email
      @name = name
    end
  end
  class Git
    attr_reader :rugged_repo, :git_dir, :index, :repo
    def initialize(repo, git_dir)
      @repo = repo
      @rugged_repo = repo.rugged_repo
      @index = Index.new(repo)
      @git_dir    = git_dir
      @work_tree  = git_dir.gsub(/\/\.git$/,'')
      @bytes_read = 0
    end
    # def apply_patch(options = {}, head_sha = nil, patch = nil)
    #   # todo
    # end
    # {},"-i","-c","foo","master","--","--","docs"
    def grep(a,b,c,word,commit,f,g,path)
      # -i filename:line
      ret = []#["?:docs/foo:1"]
      ::Rake::FileList.new(@rugged_repo.workdir+path+"/*").egrep(/#{word}/){|filename, count, line| ret << ":#{Pathname(filename).relative_path_from(Pathname(@rugged_repo.workdir))}:#{count}" }
      ret.join
    end
    def ls_files(a,pattern)
      Dir.chdir(@rugged_repo.workdir){|path|
        Dir.glob("**/"+pattern)
      }.join("\n")
    end
    def log(options,commit_sha,c,path)
      walker = Rugged::Walker.new(@rugged_repo)
      walker.sorting(Rugged::SORT_DATE)
      walker.push(commit_sha)
      commits = walker.map do |commit|
        #commit.parents.size == 1 &&
        diff_options = {paths: [path]} if path
        if commit.diff(diff_options).size > 0
          if commit.parents.size > 0
            diff = @rugged_repo.diff(commit.parents.first.oid,commit.oid)
            diff.find_similar!(:all => true)
            delta = diff.deltas.first
            path = delta.old_file[:path] if delta && delta.renamed? && options[:follow]
          end
          #commit
          Commit.new(commit)
        else
          nil
        end
      end.compact
      options = {:max_count => commits.size, :skip => 0}.merge(options)
      commits.drop(options[:skip]).take(options[:max_count])
      #options[:max_count]?  : commits
      #commits.map{ |c| puts c } #c.inspect
      # http://stackoverflow.com/questions/21302073/access-git-log-data-using-ruby-rugged-gem
      # https://github.com/libgit2/rugged/blob/development/test/diff_test.rb#L83
      # https://github.com/libgit2/rugged/blob/development/test/blob_test.rb#L193
    end
    # @wiki.repo.git.checkout({}, 'HEAD', '--', path)
    def checkout(options,commit,c,path)
      options[:paths] = [path]
      require "tmpdir"
      @rugged_repo.workdir = tmp if @rugged_repo.bare?
      @rugged_repo.checkout(commit, :strategy => :force)
    end
    def exist?
      File.exist?(self.git_dir)
    end
    # @wiki.repo.git.rm({'f' => true}, '--', path)
    def rm(options, b, path)#(options,commit,c,path)
      errors = options['f'] ? Rugged::IndexError : nil
      begin
        @index.delete(path)
      rescue errors
      end
      FileUtils.rm(File.expand_path(path, @index.repo.rugged_repo.workdir))
    end
  end
  class Diff
    attr_reader :rugged_diff
    def initialize(rugged_diff)
      @rugged_diff = rugged_diff
    end
    def diff
      # @rugged_diff.inspect
      @rugged_diff.to_s
    end
  end
  class Ref
    def initialize(rugged_ref)
      @rugged_ref = rugged_ref
    end
    def commit
      Commit.new(@rugged_ref.target)
    end
  end
  class Repo
    attr_reader :rugged_repo, :git, :working_dir
    def update_ref(head, commit_sha)
      @rugged_repo.
        create_branch(head,Rugged::Commit.lookup(@rugged_repo, commit_sha))
    end
    def log(commit = 'master', path = nil, options = {})
      # https://github.com/gitlabhq/grit/blob/master/lib/grit/repo.rb#L555
      self.git.log({:pretty => "raw"}.merge(options),commit,nil,path)
    end
    def head
      Ref.new(@rugged_repo.head)
    end
    def index
      Index.new(self)
    end
    def config
      @rugged_repo.config
    end
    def path
      @rugged_repo.path
    end
    def diff(a, b, *paths)
      @rugged_repo.diff(a,b).find_similar!(:all => true).
        patches.map{|patches| Diff.new(patches)}.reverse
    end
    def bare
      @rugged_repo.bare?
    end
    def initialize(path, options = {})
      @rugged_repo = ::Rugged::Repository.new(path)
      @git = Git.new(self, path)
    end
    def self.init_bare(path, git_options = {}, repo_options = {})
      ::Rugged::Repository.init_at(path, :bare)
      self.new(path, repo_options)
    end
    def self.init(path, git_options = {}, repo_options = {})
      ::Rugged::Repository.init_at(path, false)
      self.new(path, repo_options)
    end
    def commit(ref)
      # return Rugged ref or Grit commit from reference
      begin
        #::Rugged::Branch.lookup(@rugged_repo, ref) ||
        if @rugged_repo.branches[ref]
          Commit.new(@rugged_repo.lookup(@rugged_repo.branches[ref].target_id))
          #Commit.new(@rugged_repo.branches[ref])
        else
          Commit.new(@rugged_repo.lookup(ref))
        end
        # p "comm",commit
        # commit
      rescue Rugged::InvalidError, Rugged::ReferenceError
        nil
      end
    end
    def commits(start = 'master', max_count = 10, skip = 0)
      walker = Rugged::Walker.new(@rugged_repo)
      walker.push(start)
      walker.map{ |c| Commit.new(c) }#puts c.inspect
    end
    def lstree(treeish = 'master', options = {})
      obj = commit(treeish)
      list = []
      obj.tree.walk_blobs(:postorder) { |root, e|
        list << {:type => "blob", :sha => e[:oid], :path => "#{root}#{e[:name]}" , :mode => e[:filemode].to_s(8)}
      }
      list
    end
  end
end

module Rugged
  class Tree
    include Enumerable
    # http://ref.xaio.jp/ruby/classes/module/alias_method
    alias_method :orig_each_blob, :each_blob
    #should return blob?
    def each_blob(&block)
      # http://sekai.hateblo.jp/entry/2013/10/02/010712
      if block_given?
        #self.each { |e| yield e if e[:type] == :blob }
        #::Grit::Blob.new(e)
        orig_each_blob block
      else
        #self.to_enum(:each_blob)#orig?
        self.to_enum(:orig_each_blob)#orig?
      end
    end
    alias :blobs :each_blob
  end
end

module Gollum
  # Controls all access to the Git objects from Gollum.  Extend this class to
  # add custom caching for special cases.
  class GitAccess
    # Initializes the GitAccess instance.
    #
    # path          - The String path to the Git repository that holds the
    #                 Gollum site.
    # page_file_dir - String the directory in which all page files reside
    #
    # Returns this instance.
    def initialize(path, page_file_dir = nil, bare = false)
      @page_file_dir = page_file_dir
      @path          = path
      begin
        @repo = Grit::Repo.new(path, { :is_bare => bare })
      rescue Grit::InvalidGitRepositoryError
        raise Gollum::InvalidGitRepositoryError
      rescue Grit::NoSuchPathError
        raise Gollum::NoSuchPathError
      end
      clear
    end

    # Public: Determines whether the Git repository exists on disk.
    #
    # Returns true if it exists, or false.
    def exist?
      @repo.git.exist?
    end

    # Public: Converts a given Git reference to a SHA, using the cache if
    # available.
    #
    # ref - a String Git reference (ex: "master")
    #
    # Returns a String, or nil if the ref isn't found.
    def ref_to_sha(ref)
      ref = ref.to_s
      return if ref.empty?
      sha =
          if sha?(ref)
            ref
          else
            get_cache(:ref, ref) { ref_to_sha!(ref) }
          end.to_s
      sha.empty? ? nil : sha
    end

    # Public: Gets a recursive list of Git blobs for the whole tree at the
    # given commit.
    #
    # ref - A String Git reference or Git SHA to a commit.
    #
    # Returns an Array of BlobEntry instances.
    def tree(ref)
      if sha = ref_to_sha(ref)
        get_cache(:tree, sha) { tree!(sha) }
      else
        []
      end
    end

    # Public: Fetches the contents of the Git blob at the given SHA.
    #
    # sha - A String Git SHA.
    #
    # Returns the String content of the blob.
    def blob(sha)
      cat_file!(sha)
    end

    # Public: Looks up the Git commit using the given Git SHA or ref.
    #
    # ref - A String Git SHA or ref.
    #
    # Returns a Grit::Commit.
    def commit(ref)
      if sha?(ref)
        get_cache(:commit, ref) { commit!(ref) }
      else
        if sha = get_cache(:ref, ref)
          commit(sha)
        else
          if cm = commit!(ref)
            set_cache(:ref, ref, cm.id)
            set_cache(:commit, cm.id, cm)
          end
        end
      end
    end

    # Public: Clears all of the cached data that this GitAccess is tracking.
    #
    # Returns nothing.
    def clear
      @ref_map    = {}
      @tree_map   = {}
      @commit_map = {}
    end

    # Public: Refreshes just the cached Git reference data.  This should
    # be called after every Gollum update.
    #
    # Returns nothing.
    def refresh
      @ref_map.clear
    end

    #########################################################################
    #
    # Internal Methods
    #
    #########################################################################

    # Gets the String path to the Git repository.
    attr_reader :path

    # Gets the Grit::Repo instance for the Git repository.
    attr_reader :repo

    # Gets a Hash cache of refs to commit SHAs.
    #
    #   {"master" => "abc123", ...}
    #
    attr_reader :ref_map

    # Gets a Hash cache of commit SHAs to a recursive tree of blobs.
    #
    #   {"abc123" => [<BlobEntry>, <BlobEntry>]}
    #
    attr_reader :tree_map

    # Gets a Hash cache of commit SHAs to the Grit::Commit instance.
    #
    #     {"abcd123" => <Grit::Commit>}
    #
    attr_reader :commit_map

    # Checks to see if the given String is a 40 character hex SHA.
    #
    # str - Possible String SHA.
    #
    # Returns true if the String is a SHA, or false.
    def sha?(str)
      !!(str =~ /^[0-9a-f]{40}$/)
    end

    # Looks up the Git SHA for the given Git ref.
    #
    # ref - String Git ref.
    #
    # Returns a String SHA.
    def ref_to_sha!(ref)
      commit = @repo.commit(ref)
      commit ? commit.id : nil
    end

    # Looks up the Git blobs for a given commit.
    #
    # sha - String commit SHA.
    #
    # Returns an Array of BlobEntry instances.
    def tree!(sha)
      tree  = @repo.lstree(sha, { :recursive => true })
      items = []
      tree.each do |entry|
        if entry[:type] == 'blob'
          items << BlobEntry.new(entry[:sha], entry[:path], entry[:size], entry[:mode].to_i(8))
        end
      end
      if dir = @page_file_dir
        regex = /^#{dir}\//
        items.select { |i| i.path =~ regex }
      else
        items
      end
    end

    # Reads the content from the Git db at the given SHA.
    #
    # sha - The String SHA.
    #
    # Returns the String content of the Git object.
    def cat_file!(sha)
      @repo.git.cat_file({ :p => true }, sha)
    end

    # Reads a Git commit.
    #
    # sha - The string SHA of the Git commit.
    #
    # Returns a Grit::Commit.
    def commit!(sha)
      @repo.commit(sha)
    end

    # Attempts to get the given data from a cache.  If it doesn't exist, it'll
    # pass the results of the yielded block to the cache for future accesses.
    #
    # name - The cache prefix used in building the full cache key.
    # key  - The unique cache key suffix, usually a String Git SHA.
    #
    # Yields a block to pass to the cache.
    # Returns the cached result.
    def get_cache(name, key)
      cache = instance_variable_get("@#{name}_map")
      value = cache[key]
      if value.nil? && block_given?
        set_cache(name, key, value = yield)
      end
      value == :_nil ? nil : value
    end

    # Writes some data to the internal cache.
    #
    # name  - The cache prefix used in building the full cache key.
    # key   - The unique cache key suffix, usually a String Git SHA.
    # value - The value to write to the cache.
    #
    # Returns nothing.
    def set_cache(name, key, value)
      cache      = instance_variable_get("@#{name}_map")
      cache[key] = value || :_nil
    end

    # Parses a line of output from the `ls-tree` command.
    #
    # line - A String line of output:
    #          "100644 blob 839c2291b30495b9a882c17d08254d3c90d8fb53  Home.md"
    #
    # Returns an Array of BlobEntry instances.
    def parse_tree_line(line)
      mode, type, sha, size, *name = line.split(/\s+/)
      BlobEntry.new(sha, name.join(' '), size.to_i, mode.to_i(8))
    end

    # Decode octal sequences (\NNN) in tree path names.
    #
    # path - String path name.
    #
    # Returns a decoded String.
    def decode_git_path(path)
      if path[0] == ?" && path[-1] == ?"
        path = path[1...-1]
        path.gsub!(/\\\d{3}/) { |m| m[1..-1].to_i(8).chr }
      end
      path.gsub!(/\\[rn"\\]/) { |m| eval(%("#{m.to_s}")) }
      path
    end
  end
end
