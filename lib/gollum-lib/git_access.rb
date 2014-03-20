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
  class Index
    #todo
  end
  class Blob
    def self.create(repo, atts)
      #{:id=>"4571349a92aa180e230345e4e44c9be7d9d4f96c", :name=>"Elrond.md", :s
      obj=repo.rugged_repo.lookup(atts[:id])
      obj.name = atts[:name]
      obj.mode = atts[:mode]
      obj
    end
  end
  class Commit
    def self.list_from_string(repo, text)
      text
    end
    def initialize(rugged_commit)
      @rugged_commit = rugged_commit
    end
    def id
      @rugged_commit.id
    end
    def sha
      @rugged_commit.sha
    end
    # Grit::GitRuby::Commit
    def author
      a = @rugged_commit.author
      Actor.new(a[:email], a[:name])
    end
  end
  class Actor
    attr_reader :email, :name
    def initialize(email, name)
      @email = email
      @name = name
    end
  end
  class Repo
    attr_reader :rugged_repo
    def log(commit = 'master', path = nil, options = {})
      # https://github.com/gitlabhq/grit/blob/master/lib/grit/repo.rb#L555
      @rugged_repo.log({:pretty => "raw"}.merge(options),commit,nil,path)
    end
    def head
      @rugged_repo.head
    end
    def git
      #alias
      @rugged_repo
    end
    def index
      #todo
      nil
    end
    def config
      @rugged_repo.config
    end
    def path
      @rugged_repo.path
    end
    def diff(a, b, *paths)
      @rugged_repo.diff(a,b)#,paths)
    end
    def bare
      @rugged_repo.bare?
    end
    def initialize(path, options = {})
      @rugged_repo = ::Rugged::Repository.new(path)
    end
    def commit(ref)
      # return sha1 from reference
      begin
        ::Rugged::Branch.lookup(@rugged_repo, ref) ||
          Commit.new(@rugged_repo.lookup(ref))
      rescue Rugged::InvalidError, Rugged::ReferenceError
        nil
      end
    end
    def commits
      walker = Rugged::Walker.new(@rugged_repo)
      #walker.sorting(Rugged::SORT_TOPO | Rugged::SORT_REVERSE) # optional
      walker.push('master')
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
      self
    end
    def sha
      self.target
    end
  end
  class Repository
    # def apply_patch(options = {}, head_sha = nil, patch = nil)
    #   "hoge"
    # end
    # a {:follow=>true, :pretty=>"raw"}
    # b "master"
    # c "--"
    # d "My-Precious.md"
    def log(options,commit,c,path)
      # p options
      # p commit
      # p c
      # p path
      # modified
      # "f25eccd98e9b667f9e22946f3e2f945378b8a72d",
      # first commit
      # "5bc1aaec6149e854078f1d0f8b71933bbc6c2e43"
      walker = Rugged::Walker.new(self)
      walker.sorting(Rugged::SORT_DATE)
      walker.push(commit)
      commits = walker.map do |commit|
        #commit.parents.size == 1 &&
        if commit.diff(paths: [path]).size > 0
          delta = self.diff(commit.parents.first.oid,commit.oid).
            find_similar!(:all => true).deltas.first if commit.parents.first
          path = delta.old_file[:path] if delta && delta.renamed? && options[:follow]
          commit
        else
          nil
        end
      end.compact
      #commits.map{ |c| puts c } #c.inspect
      # http://stackoverflow.com/questions/21302073/access-git-log-data-using-ruby-rugged-gem
      # https://github.com/libgit2/rugged/blob/development/test/diff_test.rb#L83
      # https://github.com/libgit2/rugged/blob/development/test/blob_test.rb#L193
    end
  end
  class Branch
    def id
      self.tip.oid
    end
    def sha
      self.tip.oid
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
