{% macro clean_text(column_name) -%}
    nullif(btrim({{ column_name }}), '')
{%- endmacro %}

{% macro clean_numeric(column_name) -%}
    {{ clean_text(column_name) }}::numeric
{%- endmacro %}

{% macro normalize_icd9_code(column_name) -%}
    nullif(replace(upper(btrim({{ column_name }})), '.', ''), '')
{%- endmacro %}
