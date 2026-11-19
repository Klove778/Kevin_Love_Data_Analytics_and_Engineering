{% macro clean_text(column_name) -%}
    nullif(btrim({{ column_name }}), '')
{%- endmacro %}

{% macro clean_numeric(column_name) -%}
    {{ clean_text(column_name) }}::numeric
{%- endmacro %}
