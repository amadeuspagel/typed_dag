require 'active_support/concern'
require 'typed_dag/configuration'
require 'typed_dag/sql'

module TypedDag::Edge
  extend ActiveSupport::Concern

  module ClassMethods
    def acts_as_dag_edge(options)
      @acts_as_dag_edge_options = TypedDag::Configuration.new(options)

      include InstanceMethods
      include Associations
    end

    def _dag_options
      @acts_as_dag_edge_options
    end
  end

  module InstanceMethods
    def _dag_options
      self.class._dag_options
    end

    def direct_edge?
      _dag_options.type_columns.one? { |type_column| send(type_column) == 1 }
    end

    private

    def add_closures
      return unless direct_edge?

      self.class.connection.execute add_dag_closure_sql
    end

    def truncate_closures
      return unless direct_edge?

      self.class.connection.execute truncate_dag_closure_sql
    end

    def add_dag_closure_sql
      TypedDag::Sql::AddClosure.sql(self)
    end

    def truncate_dag_closure_sql
      TypedDag::Sql::TruncateClosure.sql(self)
    end

    def ancestor_id_value
      send(_dag_options.ancestor_column)
    end

    def descendant_id_value
      send(_dag_options.descendant_column)
    end
  end

  module Associations
    extend ActiveSupport::Concern

    included do
      after_create :add_closures
      after_destroy :truncate_closures

      belongs_to :ancestor,
                 class_name: _dag_options.node_class_name,
                 foreign_key: _dag_options.ancestor_column
      belongs_to :descendant,
                 class_name: _dag_options.node_class_name,
                 foreign_key: _dag_options.descendant_column
    end
  end
end
