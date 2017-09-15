require 'typed_dag/sql/relation_access'

module TypedDag::Sql::TruncateClosure
  def self.sql(deleted_relation)
    Sql.new(deleted_relation).sql
  end

  class Sql
    include TypedDag::Sql::RelationAccess

    def initialize(relation)
      self.relation = relation
    end

    def sql
      <<-SQL
        DELETE FROM
          #{table_name}
        WHERE id IN
          (SELECT id
          FROM (
            SELECT COUNT(id) count, #{from_column}, #{to_column}, #{type_select_list}
            FROM (

               #{select_relations_joined_by_to_and_from}

             UNION ALL

                #{select_relations_starting_from_to}

             UNION ALL

                #{select_relations_ending_in_from}

             ) aggregation
             GROUP BY #{from_column}, #{to_column}, #{type_select_list}) criteria

          JOIN
            (#{rank_similar_relations}) ranked
          ON
            #{ranked_critieria_join_condition})
      SQL
    end

    private

    attr_accessor :relation

    def select_relations_joined_by_to_and_from
      <<-SQL
        SELECT froms.id, froms.#{from_column}, tos.#{to_column}, #{type_sums_select_list}
          FROM
            #{table_name} froms
          JOIN
            #{table_name} tos
          ON
              froms.#{to_column} = #{from_id_value} AND tos.#{from_column} = #{from_id_value}
            AND
              froms.#{to_column} = tos.#{from_column}
      SQL
    end

    def select_relations_starting_from_to
      <<-SQL
        SELECT id, #{from_id_value}, #{to_column}, #{type_sum_value_select_list}
          FROM #{table_name}
          WHERE #{from_column} = #{to_id_value}
      SQL
    end

    def select_relations_ending_in_from
      <<-SQL
        SELECT id, #{from_column}, #{to_id_value}, #{type_sum_value_select_list}
             FROM #{table_name}
             WHERE #{to_column} = #{from_id_value}
      SQL
    end

    def rank_similar_relations
      if mysql_db?
        rank_similar_relations_mysql
      else
        rank_similar_relations_postgresql
      end
    end

    def ranked_critieria_join_condition
      <<-SQL
        ranked.#{from_column} = criteria.#{from_column}
        AND ranked.#{to_column} = criteria.#{to_column}
        AND #{types_equality_condition}
        AND count >= row_number
      SQL
    end

    def type_column_values_pairs
      type_columns.map do |column|
        [column, relation.send(column)]
      end
    end

    def types_equality_condition
      type_columns.map do |column|
        "ranked.#{column} = criteria.#{column}"
      end.join(' AND ')
    end

    def type_sum_value_select_list
      type_column_values_pairs.map do |column, value|
        "#{column} + #{value}"
      end.join(', ')
    end

    def type_sums_select_list
      type_columns.map do |column|
        "froms.#{column} + tos.#{column} AS #{column}"
      end.join(', ')
    end

    def mysql_db?
      ActiveRecord::Base.connection.adapter_name == 'Mysql2'
    end

    def rank_similar_relations_mysql
      <<-SQL
        SELECT
          id,
          #{from_column},
          #{to_column},
          #{type_select_list},
          greatest(@cur_count := IF(#{compare_mysql_variables},
                                 @cur_count + 1, 1),
                   least(0, #{assign_mysql_variables})) AS row_number
        FROM
          #{table_name}

        CROSS JOIN (SELECT #{initialize_mysql_variables}) params_initialization

        WHERE
          #{only_relations_in_closure_condition}

        ORDER BY #{from_column}, #{to_column}, #{type_select_list}
      SQL
    end

    def rank_similar_relations_postgresql
      <<-SQL
        SELECT *, ROW_NUMBER() OVER(
          PARTITION BY #{from_column}, #{to_column}, #{type_select_list}
        )
        FROM
          #{table_name}
        WHERE
          #{only_relations_in_closure_condition}
      SQL
    end

    def only_relations_in_closure_condition
      <<-SQL
        #{from_column} IN (SELECT #{from_column} FROM #{table_name} WHERE #{to_column} = #{from_id_value}) OR #{from_column} = #{from_id_value}
      AND
        #{to_column} IN (SELECT #{to_column} FROM #{table_name} WHERE #{from_column} = #{from_id_value})
      SQL
    end

    def initialize_mysql_variables
      variable_string = "@cur_count := NULL,
                         @cur_#{from_column} := NULL,
                         @cur_#{to_column} := NULL"

      type_columns.each do |column|
        variable_string += ", @cur_#{column} := NULL"
      end

      variable_string
    end

    def assign_mysql_variables
      variable_string = "@cur_#{from_column} := #{from_column},
                         @cur_#{to_column} := #{to_column}"

      type_columns.each do |column|
        variable_string += ", @cur_#{column} := #{column}"
      end

      variable_string
    end

    def compare_mysql_variables
      variable_string = "@cur_#{from_column} = #{from_column} AND
                         @cur_#{to_column} = #{to_column}"

      type_columns.each do |column|
        variable_string += " AND @cur_#{column} = #{column}"
      end

      variable_string
    end
  end
end
