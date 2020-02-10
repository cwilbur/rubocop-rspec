# frozen_string_literal: true

module RuboCop
  module Cop
    module RSpec
      # Checks that spec file paths are consistent with the test subject.
      #
      # Checks the path of the spec file and enforces that it reflects the
      # described class/module and its optionally called out method.
      #
      # With the configuration option `IgnoreMethods` the called out method will
      # be ignored when determining the enforced path.
      #
      # With the configuration option `CustomTransform` modules or classes can
      # be specified that should not as usual be transformed from CamelCase to
      # snake_case (e.g. 'RuboCop' => 'rubocop' ).
      #
      # @example
      #   # bad
      #   whatever_spec.rb         # describe MyClass
      #
      #   # bad
      #   my_class_spec.rb         # describe MyClass, '#method'
      #
      #   # good
      #   my_class_spec.rb         # describe MyClass
      #
      #   # good
      #   my_class_method_spec.rb  # describe MyClass, '#method'
      #
      #   # good
      #   my_class/method_spec.rb  # describe MyClass, '#method'
      #
      # @example when configuration is `IgnoreMethods: true`
      #   # bad
      #   whatever_spec.rb         # describe MyClass
      #
      #   # good
      #   my_class_spec.rb         # describe MyClass
      #
      #   # good
      #   my_class_spec.rb         # describe MyClass, '#method'
      #
      # RSpec, by convention, names spec files with the
      # extension `_spec.rb`. rubocop-rspec analyzes the
      # subset of ruby files that match the list of patterns
      # provided in the global configuration under  `AllCops/Rspec`.
      #
      # @example default pattern configuration
      #
      #   AllCops:
      #     RSpec:
      #       Patterns:
      #       - '_test.rb$''
      #       - '(?:^|/)test/'
      #
      # By default, with no additional configuration, a spec
      # file name must match at least one of those regular
      # expressios to be considered correct.
      #
      # This behavior can be overridden. If the cop
      # configuration option `SpecFilePatterns` contains a
      # list, it will be treated as a list of patterns and
      # replace the patterns in the global configuration.
      #
      # Further, the cop configuration option
      # `RequiredPatternMatches` can be set to make the
      # requirements more stringent.  Its default value is
      # `:any`, meaning that the spec file name is
      # acceptable if any pattern matches. It can be set to
      # ':all`, requiring that all patterns be matched; or
      # it can be set to a list of patterns that the spec
      # file name must match.
      #
      # @example default file_extension behavior
      #
      #   # good - it matches `%r{_spec.rb$}`
      #   my_class_spec.rb         # describe MyClass
      #
      #   # good - it matches `%r{(?:^|/)test/}`
      #   /spec/my_class           # describe MyClass
      #
      #   # bad
      #   my_class.rb              # describe MyClass
      #
      #   # bad
      #   lib/my_class_test.rb      # describe MyClass
      #
      # @example when `SpecFilePatterns` is [ '.spec.rb' ]
      #
      #   # good
      #   my_class.spec.rb         # describe MyClass
      #
      #   # bad - SpecFilePatterns overrides the global list
      #   my_class_spec.rb         # describe MyClass
      #
      # @example with default configuration and  `RequiredPatternMatches` = :all
      #
      #   #good
      #   /spec/my_class_spec.rb   # describe MyClass

      #   #good
      #   spec/my_class_spec.rb   # describe MyClass
      #
      #   #good
      #   testing/spec/my_class_spec.rb
      #                           # describe MyClass
      #
      #   # bad
      #   on_spec/my_class_spec.rb # describe MyClass
      #
      # @example default configuration plsu `RequiredPatternMatches` = `[ '\.rb$' ]`
      #
      #   # good
      #   my_class_spec.rb         # describe MyClass
      #
      #   # bad - it doesn't match the required pattern
      #   /spec/my_class           # describe MyClass
      #
      #   # bad
      #   my_class.rb              # describe MyClass
      #
      #   # bad
      #   lib/my_class_test.rb      # describe MyClass
      #
      class FilePath < Cop
        include RuboCop::RSpec::TopLevelDescribe

        MSG = 'Spec path %<must_conditions>.'

        def_node_search :const_described?,  '(send _ :describe (const ...) ...)'
        def_node_search :routing_metadata?, '(pair (sym :type) (sym :routing))'

        def on_top_level_describe(node, args)
          return unless const_described?(node) && single_top_level_describe?
          return if routing_spec?(args)

          problems = []

          unless filename_starts_with?(path_glob_for_args(args))
            problems.push(path_explanation_for_args(args))
          end

          unless filename_matches_one_of?(rspec_pattern_strings)
            problems.push(extension_explanation_for_patterns(rspec_pattern_strings))
          end

          return if problems.empty?

          add_offense(
            node,
            message: format(MSG, must_conditions: problems.join(' and '))
          )
        end

        private

        def routing_spec?(args)
          args.any?(&method(:routing_metadata?))
        end

        # determining the expected path/filename

        def ignore_methods?
          cop_config['IgnoreMethods']
        end

        def path_segment_for_class(constant)
          File.join(
            constant.const_name.split('::').map do |name|
              custom_transform.fetch(name) { camel_to_snake_case(name) }
            end
          ).to_s
        end

        def path_segment_for_method(method_name)
          return unless method_name&.str_type?
          return if ignore_methds?

          method_name.str.content.gsub(/\W/, '')
        end

        def camel_to_snake_case(string)
          string
            .gsub(/([^A-Z])([A-Z]+)/, '\1_\2')
            .gsub(/([A-Z])([A-Z][^A-Z\d]+)/, '\1_\2')
            .downcase
        end

        def custom_transform
          cop_config.fetch('CustomTransform', {})
        end

        # support code to turn the expected path segments into a glob
        # and into human-readable error messages

        def path_glob_fmt
          if ignore_methods?
            '*%<class_segment>*'
          else
            '*%<class_segment>.[/_]%<%method_segment>*'
          end
        end

        def path_glob_for_args((described_class, method_name))
          format(path_glob_fmt,
                 class_segment: path_segment_for_class(described_class),
                 method_segment: path_segment_for_method(method_name))
        end

        def path_explanation_fmt
          if ignore_methods?
            'must start with `%<class_segment>`'
          else
            'must start with `%<class_segment>/%<method_segment>`' \
            ' or `%<class_segment>_%<method_segment>`'
          end
        end

        def path_explanation_for_args((described_class, _method_name))
          format(path_explanation_fmt,
                 class_segment: path_segment_for_class(described_class),
                      method_segment: path_segment_for_method(method_name))
        end

        def filename_starts_with?(glob)
          File.fnmatch?(glob, processed_source.buffer.name)
        end

        # extension patterns - these are not globs but regexes

        def default_rspec_pattern_strings
          RuboCop::RSpec::CONFIG.fetch('AllCops')
            &.fetch('RSpec')&.fetch('Patterns') || []
        end

        def rspec_pattern_strings
          config.for_all_cops.fetch('RSpec')&.fetch('AllCops')
            &.fetch('Patterns') || default_rspec_pattern_strings
        end

        def extension_explanation_for_pattern_strings(pattern_strings)
          quoted = pattern_strings.map { |str| "/#{str}/" }
          quoted.last.prepend('or ') if quoted.count > 1
          quoted_list = quoted.join(quoted.count > 3 ? ', ' : ' ')
          "must match at least one of #{quoted_list}"
        end

        def filename_matches_one_of?(pattern_strings)
          pattern_strings.any do |str|
            Regexp.new(str) =~ processed_source.buffer.name
          end
        end

        def relevant_rubocop_rspec_file?(_file)
          true
        end
      end
    end
  end
end
