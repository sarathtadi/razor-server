require 'singleton'
require 'yaml'

module Razor
  class InvalidConfigurationError < RuntimeError
    attr_reader :key
    def initialize(key, msg = "setting is invalid")
      super("entry #{key}: #{msg}")
      @key = key
    end
  end

  class Config
    # The config paths that templates have access to
    TEMPLATE_PATHS = [ "microkernel.debug_level", "microkernel.kernel_args",
                       "checkin_interval" ]

    def initialize(env, fname = nil)
      fname ||= ENV["RAZOR_CONFIG"] ||
        File::join(File::dirname(__FILE__), '..', '..', 'config.yaml')
      yaml = File::open(fname, "r") { |fp| YAML::load(fp) } || {}
      @values = yaml["all"] || {}
      @values.merge!(yaml[Razor.env] || {})
    end

    # Lookup an entry. To look up a nested value, you can pass in the
    # nested keys separated by a '.', so that passing "a.b" has the same
    # effect as +self["a"]["b"]+
    def [](key)
      key.to_s.split(".").inject(@values) { |v, k| v[k] if v }
    end

    def installer_paths
      expand_paths('installer')
    end

    def broker_paths
      expand_paths('broker')
    end

    def fact_blacklisted?(name)
      !! facts_blacklist_rx.match(name)
    end

    def validate!
      validate_facts_blacklist_rx
    end

    private
    def expand_paths(what)
      option_name  = what + '_path' # eg: broker_path, installer_path

      if self[option_name]
        self[option_name].split(':').map do |path|
          path.empty? and next
          path.start_with?('/') and path or
            File::expand_path(File::join(Razor.root, path))
        end.compact
      else
        [File::expand_path(File::join(Razor.root, what.pluralize))]
      end
    end

    def facts_blacklist_rx
      @facts_blacklist_rx ||=
        Regexp.compile("\\A((" + Array(self["facts.blacklist"]).map do |s|
                         if s =~ %r{\A/(.*)/\Z}
                           $1
                         else
                           Regexp.quote(s)
                         end
                       end.join(")|(") + "))\\Z")
    end

    # Validations
    def raise_ice(key, msg)
      raise InvalidConfigurationError.new(key, msg)
    end

    def validate_facts_blacklist_rx
      list = Array(self["facts.blacklist"])
      list.map { |s| s =~ %r{\A/(.*)/\Z} and $1 }.compact.each do |s|
        begin
          Regexp.compile(s)
        rescue RegexpError => e
          raise_ice("facts.blacklist",
                    "entry #{s} is not a valid regular expression: #{e.message}")
        end
      end
    end
  end
end
