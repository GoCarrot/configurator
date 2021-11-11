# frozen_string_literal: true

require 'lifecycle/op_base'

require 'optparse'

module Op
  class ParseMetaCli < Lifecycle::OpBase
    DEFAULT_SYSTEMD_DIRECTORY = '/run/systemd/system'

    reads :argv, :env
    writes :configuration_directory, :logs_directory, :systemd_directory, :early_exit

    # Add expand_path to string because the safe accessor is nice to use.
    module CoreExt
      refine String do
        def expand_path
          File.expand_path(self)
        end
      end
    end

    using CoreExt

    def call
      self.early_exit = false

      parser = OptionParser.new do |opts|
        opts.on('-v', '--version', 'Display the version') do
          self.early_exit = true
        end

        opts.on('-h', '--help', 'Prints this help') do
          puts opts
          self.early_exit = true
        end

        opts.on(
          '-c', '--configuration-directory directory',
          'Read configuration from the given directory instead of from $CONFIGURATION_DIRECTORY'
        ) do |dir|
          self.configuration_directory = dir
        end

        opts.on(
          '-l', '--logs-directory directory',
          'Use the given directory for writing log files instead of $LOGS_DIRECTORY'
        ) do |dir|
          self.logs_directory = dir
        end

        opts.on(
          '-s', '--systemd-directory directory',
          "Write out systemd configuration to the given directory instead of #{DEFAULT_SYSTEMD_DIRECTORY}"
        ) do |dir|
          self.systemd_directory = dir
        end
      end

      parser.parse(argv)

      self.configuration_directory ||= env['CONFIGURATION_DIRECTORY']
      self.logs_directory ||= env['LOGS_DIRECTORY']
      self.systemd_directory ||= DEFAULT_SYSTEMD_DIRECTORY

      self.configuration_directory = configuration_directory&.expand_path
    end

    def validate
      return if early_exit

      if configuration_directory.nil? || configuration_directory.empty?
        error :configuration_directory, 'must be present'
      end
    end
  end
end
