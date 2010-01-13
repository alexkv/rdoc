require 'rdoc/code_objects'
require 'fileutils'

##
# A set of ri data.
#
# The store manages reading and writing ri data for a project (gem, path,
# etc.) and maintains a cache of methods, classes and ancestors in the
# store.

class RDoc::RI::Store

  attr_reader :cache
  attr_reader :path

  ##
  # Creates a new Store that will load or save to +path+

  def initialize path
    @path = path

    @cache = {
      :class_methods => {},
      :instance_methods => {},
      :modules => [],
      :ancestors => {},
    }
  end

  ##
  # Ancestors cache accessor.  Maps a klass name to an Array of its ancestors
  # in this store.  If Foo in this store inherits from Object, Kernel won't be
  # listed (it will be included from ruby's ri store).

  def ancestors
    @cache[:ancestors]
  end

  ##
  # Path to the cache file

  def cache_path
    File.join @path, 'cache.ri'
  end

  ##
  # Path to the ri data for +klass_name+

  def class_file klass_name
    name = klass_name.split('::').last
    File.join class_path(klass_name), "cdesc-#{name}.ri"
  end

  ##
  # Class methods cache accessor.  Maps a class to an Array of it's class
  # methods (not full name).

  def class_methods
    @cache[:class_methods]
  end

  ##
  # Path where data for +klass_name+ will be stored (methods or class data)

  def class_path klass_name
    File.join @path, *klass_name.split('::')
  end

  ##
  # Instance methods cache accessor.  Maps a class to an Array of it's
  # instance methods (not full name).

  def instance_methods
    @cache[:instance_methods]
  end

  ##
  # Loads cache file for this store

  def load_cache
    open cache_path, 'rb' do |io|
      @cache = Marshal.load io.read
    end
  rescue Errno::ENOENT
  end

  ##
  # Loads ri data for +klass_name+

  def load_class klass_name
    open class_file(klass_name), 'rb' do |io|
      Marshal.load io.read
    end
  end

  ##
  # Loads ri data for +method_name+ in +klass_name+

  def load_method klass_name, method_name
    open method_file(klass_name, method_name), 'rb' do |io|
      Marshal.load io.read
    end
  end

  ##
  # Path to the ri data for +method_name+ in +klass_name+

  def method_file klass_name, method_name
    method_name = method_name.split('::').last
    method_name =~ /#(.*)/
    method_type = $1 ? 'i' : 'c'
    method_name = $1 if $1

    method_name = if ''.respond_to? :ord then
                    method_name.gsub(/\W/) { "%%%02x" % $&[0].ord }
                  else
                    method_name.gsub(/\W/) { "%%%02x" % $&[0] }
                  end

    File.join class_path(klass_name), "#{method_name}-#{method_type}.ri"
  end

  ##
  # Modules cache accessor.  An Array of all the modules (and classes) in the
  # store.

  def modules
    @cache[:modules]
  end

  ##
  # Writes the cache file for this store

  def save_cache
    open cache_path, 'wb' do |io|
      Marshal.dump @cache, io
    end
  end

  ##
  # Writes the ri data for +klass+

  def save_class klass
    FileUtils.mkdir_p class_path(klass.full_name)

    @cache[:modules] << klass.full_name

    path = class_file klass.full_name

    begin
      disk_klass = nil

      open path, 'rb' do |io|
        disk_klass = Marshal.load io.read
      end

      klass.merge disk_klass
    rescue Errno::ENOENT
    end

    ancestors = klass.ancestors.map do |ancestor|
      # HACK for classes we don't know about (class X < RuntimeError)
      String === ancestor ? ancestor : ancestor.full_name
    end

    @cache[:ancestors][klass.full_name] ||= []
    @cache[:ancestors][klass.full_name].push(*ancestors)

    open path, 'wb' do |io|
      Marshal.dump klass, io
    end
  end

  ##
  # Writes the ri data for +method+ on +klass+
   
  def save_method klass, method
    FileUtils.mkdir_p class_path(klass.full_name)

    cache = if method.singleton then
              @cache[:class_methods]
            else
              @cache[:instance_methods]
            end
    cache[klass.full_name] ||= []
    cache[klass.full_name] << method.name

    open method_file(klass.full_name, method.full_name), 'wb' do |io|
      Marshal.dump method, io
    end
  end

end
