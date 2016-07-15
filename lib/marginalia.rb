require 'marginalia/railtie'
require 'marginalia/comment'

module Marginalia
  mattr_accessor :application_name

  module ActiveRecordInstrumentation
    def self.included(instrumented_class)
      instrumented_class.class_eval do
        if instrumented_class.method_defined?(:execute)
          alias_method :execute_without_marginalia, :execute
          alias_method :execute, :execute_with_marginalia
        end

        is_mysql2 = defined?(ActiveRecord::ConnectionAdapters::Mysql2Adapter) &&
          ActiveRecord::ConnectionAdapters::Mysql2Adapter == instrumented_class
        # Dont instrument exec_query on mysql2 and AR 3.2+, as it calls execute internally
        unless is_mysql2 && ActiveRecord::VERSION::STRING > "3.1"
          if instrumented_class.method_defined?(:exec_query)
            alias_method :exec_query_without_marginalia, :exec_query
            alias_method :exec_query, :exec_query_with_marginalia
          end
        end

        is_postgres = defined?(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter) &&
          ActiveRecord::ConnectionAdapters::PostgreSQLAdapter == instrumented_class
        # Instrument exec_delete and exec_update on AR 3.2+, since they don't
        # call execute internally
        if is_postgres && ActiveRecord::VERSION::STRING > "3.1"
          if instrumented_class.method_defined?(:exec_delete)
            alias_method :exec_delete_without_marginalia, :exec_delete
            alias_method :exec_delete, :exec_delete_with_marginalia
          end
          if instrumented_class.method_defined?(:exec_update)
            alias_method :exec_update_without_marginalia, :exec_update
            alias_method :exec_update, :exec_update_with_marginalia
          end
        end
      end
    end

    def log_stack_trace(sql)
      stack_trace = Marginalia::Comment.stack_trace
      if stack_trace.present? && defined?(WM::Logger) && defined?(APP_CONFIG)
        WM::Logger.new(APP_CONFIG['new_aws']).message(
          feature_key: 'sql_stack_trace',
          message: {
            sql: sql,
            stack_trace: stack_trace
          }
        )
      end

      sql
    end

    def execute_with_marginalia(sql, name = nil)
      execute_without_marginalia(log_stack_trace(sql), name)
    end

    def exec_query_with_marginalia(sql, name = 'SQL', binds = [])
      exec_query_without_marginalia(log_stack_trace(sql), name, binds)
    end

    if ActiveRecord::VERSION::MAJOR >= 5
      def exec_query_with_marginalia(sql, name = 'SQL', binds = [], options = {})
        options[:prepare] ||= false
        exec_query_without_marginalia(log_stack_trace(sql), name, binds, options)
      end
    end

    def exec_delete_with_marginalia(sql, name = 'SQL', binds = [])
      exec_delete_without_marginalia(log_stack_trace(sql), name, binds)
    end

    def exec_update_with_marginalia(sql, name = 'SQL', binds = [])
      exec_update_without_marginalia(log_stack_trace(sql), name, binds)
    end
  end

  module ActionControllerInstrumentation
    def self.included(instrumented_class)
      instrumented_class.class_eval do
        if respond_to?(:around_action)
          around_action :record_query_comment
        else
          around_filter :record_query_comment
        end
      end
    end

    def record_query_comment
      Marginalia::Comment.update!(self)
      yield
    ensure
      Marginalia::Comment.clear!
    end
  end
end
