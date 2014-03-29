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
    def initialize(rugged_tree, rugged_repo)
      @rugged_tree = rugged_tree
      @rugged_repo = rugged_repo
    end
    def id
      @rugged_tree.oid
    end
    def /(file)
      if file =~ /\//
        file.split("/").inject(self) { |acc, x| acc/x } rescue nil
      else
        obj = @rugged_tree.path(file)
        Tree.new(@rugged_repo.lookup(obj[:oid]), @rugged_repo) if
          obj[:type] == :tree
      #   # @rugged_tree.walk(:postorder) { |root, entry| }
      #   #puts "#{root}#{entry[:name]} [#{entry[:oid]}]" }
      #   #self.contents.find { |c| c.name == file }
      #   obj = @rugged_tree.select { |c| c[:name] == file }.first
      #   hoge
      end
    end
    def blobs
      # @rugged_tree.each_blob
      self
    end
    def each
      @rugged_tree.each_blob.map{ |x| Blob.new(x) }.each{ |x| yield x }
    end
  end
  class Index
    attr_reader :rugged_index, :current_tree, :tree, :rugged_repo, :repo
    def inspect
      "#<Grit::Index:#{object_id} {rugged_index: #{rugged_index}, current_tree: #{current_tree}, tree:#{tree}, rugged_repo: #{rugged_repo}, repo: #{repo}}>"
    end
    def initialize(repo)
      @rugged_index = ::Rugged::Index.new
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
      #p @rugged_repo.lookup(tree)
      #p treeish # master
      tree = @repo.commit(treeish)
      #p "commit", tree
      # Rugged refs to Rugged commit
      tree = @rugged_repo.lookup(tree.target_id) if tree.type == :direct
      # Rugged commit to Rugged tree
      tree = tree.tree if tree.type == :commit
      #p "commit2", tree
      #tree = tree.rugged_commit
      #p "tree", tree
      @rugged_index.read_tree(tree)
      @current_tree = Tree.new(tree, @rugged_repo)
    end
    def add(path, data)
      oid = @rugged_repo.write(data, :blob)
      @rugged_index.add(:path => path, :oid => oid, :mode => 0100644)
      add_grit(path, data)
    end
    def commit(message, parents = nil, actor = nil, last_tree = nil, head = 'master')
      # p "pare:", parents.map{ |p| @rugged_repo.lookup(p.id) }
      # p("target:", [ @rugged_repo.head.target ].compact) unless @rugged_repo.empty?
      # p "last_tree:", last_tree, head
      # index = wiki.repo.index
      # index.read_tree 'master'
      # index.add('Foobar/Elrond.md', 'Baz')
      # index.commit 'Add Foobar/Elrond.', [wiki.repo.commits.last], Grit::Actor.new('Tom Preston-Werner', 'tom@github.com')
      options = {}
      # if @current_tree
      #   # p @rugged_repo.references["refs/heads/master"]
      #   # p @rugged_repo.branches["master"]
      #   head_sha = @rugged_repo.references["refs/heads/" + head].resolve.target_id
      #   tree = @rugged_repo.lookup(head_sha).tree
      #   @rugged_index.read_tree(tree)
      #   options[:tree] = tree.id
      # else
      # @rugged_repo.checkout(@rugged_repo.branches[head]) if @rugged_repo.branches[head]
      # end
      options[:tree] = @rugged_index.write_tree(@rugged_repo)
      # p "pare2:", parents.map{ |p| @rugged_repo.lookup(p.id) }
      # p("target2:", [ @rugged_repo.head.target ].compact) unless @rugged_repo.empty?

      #p options[:tree]
      #
        # @rugged_index.write_tree(@rugged_repo) # @current_tree.rugged_tree.oid
      # p message, parents , actor, last_tree
      options[:author] = { :email => actor.email , :name => actor.name, :time => Time.now } if actor
      options[:committer] = { :email => actor.email , :name => actor.name, :time => Time.now } if actor
      options[:message] = message || ''
      #options[:message] = "hoge"
      # todo
      #p "h:", head, parents.map{ |p| p.id }, #@rugged_repo.head.target
      # options[:parents] = @rugged_repo.empty? ? [] :
      #   [ @rugged_repo.head.target ].compact
      options[:parents] = @rugged_repo.empty? ? [] : [ @rugged_repo.head.target ].compact
      #parents.map{ |p| p.id }
      options[:update_ref] = "refs/heads/" + head #head #'HEAD'
      #p options
      Rugged::Commit.create(@rugged_repo, options)
    end
    def delete(path)
      # @rugged_index.remove(path)
      head_sha = @rugged_repo.references['HEAD'].resolve.target_id
      tree = @rugged_repo.lookup(head_sha).tree

      index = @rugged_repo.index
      index.read_tree(tree)
      @rugged_index.remove(path)

      index_tree_sha = index.write_tree
      index_tree = @rugged_repo.lookup(index_tree_sha)
      @current_tree = Tree.new(index_tree, @rugged_repo)
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
    attr_reader :rugged_blob, :name, :oid, :filemode, :type
    def initialize(blob)
      @name = blob[:name]
      @oid = blob[:oid]
      @filemode = blob[:filemode]
      @type = blob[:type]
    end
    def self.create(repo, atts)
      #{:id=>"4571349a92aa180e230345e4e44c9be7d9d4f96c", :name=>"Elrond.md", :s
      obj=repo.rugged_repo.lookup(atts[:id])
      obj.name = atts[:name]
      obj.mode = atts[:mode]
      obj
    end
  end
  class Commit
    attr_reader :rugged_commit,:type
    def self.list_from_string(repo, text)
      text
    end
    def initialize(rugged_commit)
      @rugged_commit = rugged_commit
      @type = :commit
    end
    def id
      @rugged_commit.id
    end
    def sha
      @rugged_commit.sha
    end
    def message
      @rugged_commit.message
    end
    def tree
      return @rugged_commit.tree if @rugged_commit.type == :commit
      return @rugged_commit if @rugged_commit.type == :tree
    end
    # Grit::GitRuby::Commit
    def author
      a = @rugged_commit.author
      Actor.new(a[:name], a[:email])
    end
    def parents
      @rugged_commit.parents
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
    def log(options,commit,c,path)
      #p "op", options, commit, path
      #options = {:max_count => 500}.merge(options)
      walker = Rugged::Walker.new(@rugged_repo)
      walker.sorting(Rugged::SORT_DATE)
      walker.push(commit)
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
          commit
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
  class Repo
    attr_reader :rugged_repo, :git, :working_dir
    def update_ref(head, commit_sha)
    # when Rugged::Object
    #   target = sha_or_ref.oid
    # else
    #   target = rev_parse_oid(sha_or_ref)
    # end
      #b = @rugged_repo.references.create("refs/heads/" + head,commit_sha)
      #p "t", b.target.oid, commit_sha
      #p "cl:", Rugged::Commit.lookup(@rugged_repo, commit_sha)
      ref = @rugged_repo.create_branch(head, Rugged::Commit.lookup(@rugged_repo, commit_sha))
      #p "ref:", ref.type, ref.target, ref.name, ref.branch?, ref.canonical_name, ref.head?
      @rugged_repo.branches[head]
      ref
      # p "t", b.target.oid, commit_sha
    end
    def log(commit = 'master', path = nil, options = {})
      # https://github.com/gitlabhq/grit/blob/master/lib/grit/repo.rb#L555
      self.git.log({:pretty => "raw"}.merge(options),commit,nil,path)
    end
    def head
      @rugged_repo.head
    end
    def index
      #todo
      Index.new(self)
      #nil
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
      #.map{ |patch| patch.to_s }
      #deltas
      #,paths)
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
      #git_options = {:base => false}.merge(git_options)
      #p git_options
      # todo bare?
      #::Rugged::Repository.init_at('.', :bare)
      ::Rugged::Repository.init_at(path, false)
      self.new(path, repo_options)
    end
    def commit(ref)
      # return Rugged ref or Grit commit from reference
      begin
        #::Rugged::Branch.lookup(@rugged_repo, ref) ||
        commit = @rugged_repo.branches[ref] ||
                 Commit.new(@rugged_repo.lookup(ref))
        # p "comm",commit
        # commit
      rescue Rugged::InvalidError, Rugged::ReferenceError
        nil
      end
    end
    def commits(start = 'master', max_count = 10, skip = 0)
      walker = Rugged::Walker.new(@rugged_repo)
      #walker.sorting(Rugged::SORT_TOPO | Rugged::SORT_REVERSE) # optional
      walker.push(start)
      #walker.push(@repo.ref)
      walker.map{ |c| Commit.new(c) }#puts c.inspect
    end
    # http://rubydoc.info/gems/gitlab-grit/2.6.4/frames
    def lstree_rec(tree, path, list)
      tree.each do |e|
        if e[:type] == :blob
          #     items << BlobEntry.new(entry[:sha], entry[:path], entry[:size], entry[:mode].to_i(8))          #   end
          # end
          list << {:type => "blob", :sha => e[:oid], :path => path + e[:name],
                   :mode => e[:filemode].to_s(8)}#to_s for compati
        elsif e[:type] == :tree
          lstree_rec(@rugged_repo.lookup(e[:oid]), e[:name] + '/', list)
        end
      end
    end
    def lstree(treeish = 'master', options = {})
      #walk is ok?
      obj = @rugged_repo.lookup(treeish)
      list = []
      lstree_rec(obj.tree, '', list)
      list
    end
  end
end

module Rugged
  class Object
    def id
      self.oid
    end
    def sha
      self.oid
    end
  end
  class Reference
    def commit
      self.target
    end
    # def sha
    #   self.target
    # end
  end
  class Repository
  end
  class Branch
    def id
      #self.tip.oid
      self.target_id
    end
    def sha
      #self.tip.oid
      self.target_id
    end
    def tree
      self.target.tree
    end
  end
  class Blob
    attr_accessor :name, :mode
    def data
      self.read_raw.data
    end
    #copy from grit_ext.rb
    def is_symlink
      self.mode == 0120000
    end
    def symlink_target(base_path = nil)
      target = self.data
      new_path = File.expand_path(File.join('..', target), base_path)
      if File.file? new_path
        return new_path
      end
    end
  end
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
      @path = path
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
            set_cache(:ref,    ref,   cm.id)
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
      tree = @repo.lstree(sha, {:recursive => true})
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
      @repo.git.cat_file({:p => true}, sha)
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
        path.gsub!(/\\\d{3}/)   { |m| m[1..-1].to_i(8).chr }
      end
      path.gsub!(/\\[rn"\\]/) { |m| eval(%("#{m.to_s}")) }
      path
    end
  end
end
