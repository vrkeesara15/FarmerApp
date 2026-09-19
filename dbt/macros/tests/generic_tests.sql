{# Generic tests used by the marts (no dbt_utils dependency: `dbt build` needs no `dbt deps`). #}

{# The combination of columns is unique (a mart's grain). #}
{% test unique_combination(model, combination_of_columns) %}
select {{ combination_of_columns | join(', ') }}, count(*) as n
from {{ model }}
group by {{ combination_of_columns | join(', ') }}
having count(*) > 1
{% endtest %}

{# Every row satisfies a boolean SQL expression. #}
{% test expression_is_true(model, expression, column_name=none) %}
select * from {{ model }} where not ({{ expression }})
{% endtest %}

{# A ratio column is NULL or within [0, 1]. #}
{% test ratio_between_0_and_1(model, column_name) %}
select * from {{ model }}
where {{ column_name }} is not null and ({{ column_name }} < 0 or {{ column_name }} > 1)
{% endtest %}

{# A money / count column is never negative. #}
{% test non_negative(model, column_name) %}
select * from {{ model }} where {{ column_name }} < 0
{% endtest %}
